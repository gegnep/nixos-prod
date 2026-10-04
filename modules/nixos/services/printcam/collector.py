# printcam-collector: Core One telemetry for cam.pengeg.com.
#
# Two inputs, one ring buffer, a tiny HTTP API:
#   - PrusaLink (digest auth), polled every SAMPLE_S: job, state, nozzle/bed,
#     Z, speed/flow, fan RPM.
#   - Buddy firmware UDP metrics (syslog framing + InfluxDB line protocol),
#     pushed by the printer: chamber, heatbreak, board/MCU, fan %, xBuddy
#     extension fans, 24V. Which metric feeds which page key is UDP_MAP,
#     overridable from Nix (PRINTCAM_UDP_MAP) without touching this file.
#
# Every SAMPLE_S one row is appended (PrusaLink values + fresh UDP values).
# Routes: /  /printer/status  /printer/history  /printer/thumb  /printer/metrics
import json
import os
import re
import signal
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def env(name, default=None):
    v = os.environ.get(name)
    return v if v not in (None, "") else default


HTTP_BIND = env("PRINTCAM_BIND", "0.0.0.0")
HTTP_PORT = int(env("PRINTCAM_PORT", "1986"))
UDP_PORT = int(env("PRINTCAM_METRICS_PORT", "8514"))
PRINTER = env("PRUSALINK_HOST")
# Comma-separated: a printer on Ethernet + Wi-Fi can send UDP from either IP.
METRICS_FROM = {a.strip() for a in env("PRINTCAM_METRICS_FROM", (PRINTER or "").split(":")[0]).split(",") if a.strip()}
PL_USER = env("PRUSALINK_USER", "maker")
PL_PASS_FILE = env("PRUSALINK_PASSWORD_FILE")
STREAM = env("PRINTCAM_STREAM", "coreone")
INDEX = env("PRINTCAM_INDEX")
STATE_DIR = env("STATE_DIRECTORY", ".")
SAMPLE_S = float(env("PRINTCAM_SAMPLE_S", "2"))
HISTORY_H = float(env("PRINTCAM_HISTORY_H", "12"))
UDP_STALE_S = float(env("PRINTCAM_UDP_STALE_S", "6"))

# page key -> metric. m: metric name, tags: required tag values,
# f: field ("v" for plain metrics, "value"/"pwm"/"st"/... for custom ones).
# Transforms, applied in this order: abs, map ({"raw": out}, unmapped -> null),
# ranges ([[lo, hi, out], ...], lo <= v < hi, no match -> null), scale.
# agg: how /history buckets it ("mean" | "max" | "min").
# Names/encodings verified against Buddy fw 6.8.1 source + a live Core One+ dump.
UDP_MAP = {
    "chm": {"m": "chamber_temp"},
    "hbr": {"m": "temp_hbr", "tags": {"a": "1"}, "f": "value"},
    "brd": {"m": "temp_brd"},
    "mcu": {"m": "temp_mcu"},  # fw records it every loop (~900/s): leave it off on the printer unless wanted
    "cpu": {"m": "cpu_usage"},
    "f_print": {"m": "fan", "tags": {"fan": "print"}, "f": "pwm"},
    "f_hbr": {"m": "fan", "tags": {"fan": "heatbreak"}, "f": "pwm"},
    "f_chm": {"m": "xbe_fan", "tags": {"fan": "1"}, "f": "pwm", "scale": 100 / 255},
    "r_chm": {"m": "xbe_fan", "tags": {"fan": "1"}, "f": "rpm"},
    "f_flt": {"m": "xbe_fan", "tags": {"fan": "3"}, "f": "pwm", "scale": 100 / 255},
    "r_flt": {"m": "xbe_fan", "tags": {"fan": "3"}, "f": "rpm"},
    "p_noz": {"m": "nozzle_pwm", "scale": 100 / 255},
    "p_bed": {"m": "bed_pwm", "scale": 100 / 255},
    "v24": {"m": "bed_voltage"},  # Core One has no 24VVoltage metric
    "i_in": {"m": "input_current", "abs": True},  # reads negative on the Core One+
    "i_heat": {"m": "heater_current"},
    # 12-bit ADC: < 0x3ff closed, < 0xcff open, above = sensor detached (null)
    "door": {"m": "door_sensor", "ranges": [[0, 1023, 0], [1023, 3327, 1]], "agg": "max"},
    # FilamentSensorState: 2 HasFilament, 3 NoFilament; the rest (uncalibrated, disabled, ...) -> null
    "fil": {"m": "fsensor", "tags": {"n": "0"}, "f": "st", "map": {"2": 1, "3": 0}, "agg": "min"},
}
UDP_MAP.update(json.loads(env("PRINTCAM_UDP_MAP", "{}")))
UDP_MAP = {k: v for k, v in UDP_MAP.items() if v}  # null in Nix = drop a default

PL_KEYS = ["noz", "noz_t", "bed", "bed_t", "z", "r_print", "r_hbr"]
KEYS = PL_KEYS + sorted(UDP_MAP)
MAXROWS = int(HISTORY_H * 3600 / SAMPLE_S) + 1


def log(*a):
    print(*a, file=sys.stderr, flush=True)


lock = threading.Lock()
rows = deque(maxlen=MAXROWS)      # (t, [values in KEYS order])
events = deque(maxlen=500)        # {"t", "l"}
latest = {}                       # metric -> {tags tuple: (fields, t)}
udp_last = 0.0
status = {"state": "OFFLINE", "online": False, "job": None, "printer": {}, "info": {}}
last_job = None
thumbs = {}                       # job id -> png bytes


# ---------------------------------------------------------------- UDP metrics
SYSLOG = re.compile(r"^<\d+>1 \S+ \S+ (\S+) \S+ \S+ \S+ (.*)$", re.S)


def split_unquoted(s, sep):
    out, cur, q, esc = [], [], False, False
    for ch in s:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            cur.append(ch)
            esc = True
        elif ch == '"':
            cur.append(ch)
            q = not q
        elif ch == sep and not q:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def parse_value(v):
    if v.startswith('"'):
        return v[1:-1].replace('\\"', '"')
    if v == "T":
        return True
    try:
        return int(v[:-1]) if v.endswith("i") else float(v)
    except ValueError:
        return None


def parse_line(line):
    line = line.strip()
    if not line or " " not in line:
        return None
    head, _, rest = line.partition(" ")
    fields_s, _, _ts = rest.rpartition(" ")
    if not fields_s:
        fields_s = rest
    parts = head.split(",")
    tags = tuple(sorted(tuple(p.split("=", 1)) for p in parts[1:] if "=" in p))
    fields = {}
    for kv in split_unquoted(fields_s, ","):
        k, _, v = kv.partition("=")
        if k:
            fields[k] = parse_value(v)
    return parts[0], tags, fields


def handle_datagram(data):
    global udp_last
    m = SYSLOG.match(data.decode("utf-8", "replace"))
    if not m or m.group(1) != "buddy":
        return
    _header, _, body = m.group(2).strip().partition(" ")
    now = time.time()
    with lock:
        for line in body.splitlines():
            p = parse_line(line)
            if p:
                latest.setdefault(p[0], {})[p[1]] = (p[2], now)
        udp_last = now


def udp_loop():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", UDP_PORT))
    log(f"udp metrics on :{UDP_PORT}" + (f" (from {', '.join(sorted(METRICS_FROM))})" if METRICS_FROM else ""))
    while True:
        data, addr = s.recvfrom(4096)
        if METRICS_FROM and addr[0] not in METRICS_FROM:
            continue
        try:
            handle_datagram(data)
        except Exception as e:  # one bad packet must not kill the listener
            log("udp parse error:", e)


def udp_value(spec, now):
    best = None
    for tags, (fields, t) in latest.get(spec["m"], {}).items():
        if now - t > UDP_STALE_S:
            continue
        td = dict(tags)
        if any(td.get(k) != str(v) for k, v in spec.get("tags", {}).items()):
            continue
        v = fields.get(spec.get("f", "v"))
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v:
            continue
        if best is None or t > best[1]:
            best = (v, t)
    if best is None:
        return None
    v = best[0]
    if spec.get("abs"):
        v = abs(v)
    if "map" in spec:
        v = spec["map"].get(str(int(v)))
        if v is None:
            return None
    if "ranges" in spec:
        v = next((out for lo, hi, out in spec["ranges"] if lo <= v < hi), None)
        if v is None:
            return None
    return round(v * spec.get("scale", 1), 2)


# ---------------------------------------------------------------- PrusaLink
def make_opener():
    if not (PRINTER and PL_PASS_FILE):
        return None
    with open(PL_PASS_FILE) as f:
        pw = f.read().strip()
    mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    mgr.add_password(None, f"http://{PRINTER}/", PL_USER, pw)
    return urllib.request.build_opener(urllib.request.HTTPDigestAuthHandler(mgr))


opener = None
pl_down = False


def pl_get(path, raw=False, timeout=4):
    global pl_down
    try:
        with opener.open(f"http://{PRINTER}{path}", timeout=timeout) as r:
            body = r.read()
        if pl_down:
            log("prusalink reachable again")
            pl_down = False
        return body if raw else json.loads(body)
    except (urllib.error.URLError, OSError, ValueError) as e:
        if not pl_down:  # log the transition, not every 2 s while the printer is off
            log(f"prusalink {path}: {e}")
            pl_down = True
        return None


def refresh_job(st_job, now):
    """New job id seen: fetch name, thumbnail ref, slicer estimate, material."""
    j = pl_get("/api/v1/job") or {}
    legacy = pl_get("/api/job") or {}
    prn = pl_get("/api/printer") or {}
    f = j.get("file") or {}
    return {
        "id": st_job.get("id"),
        "name": f.get("display_name") or f.get("name") or "",
        "thumb": (f.get("refs") or {}).get("thumbnail"),
        "slicer_est": (legacy.get("job") or {}).get("estimatedPrintTime"),
        "material": (prn.get("telemetry") or {}).get("material"),
        "start": now - (st_job.get("time_printing") or 0),
    }


def poll_once(now):
    global last_job
    st = pl_get("/api/v1/status")
    if st is None:
        with lock:
            status.update(online=False, state="OFFLINE")
        return {}
    p = st.get("printer") or {}
    sj = st.get("job")
    state = p.get("state", "UNKNOWN")
    prev = status.get("state")
    new_events = []
    if prev not in (None, "OFFLINE", state):
        if state in ("PAUSED", "ATTENTION", "FINISHED", "STOPPED", "ERROR"):
            new_events.append({"t": now, "l": state.lower()})
        elif state == "PRINTING" and prev in ("PAUSED", "ATTENTION"):
            new_events.append({"t": now, "l": "resumed"})

    job = status.get("job")
    if sj:
        if not job or job.get("id") != sj.get("id"):
            job = refresh_job(sj, now)  # network I/O, outside the lock
            if not any(e["l"] == "start" and abs(e["t"] - job["start"]) < 300 for e in list(events)):
                new_events.append({"t": job["start"], "l": "start"})  # skip if restored from disk
            log(f"job {job['id']}: {job['name']}")
        job.update(
            progress=sj.get("progress"),
            time_printing=sj.get("time_printing"),
            time_remaining=sj.get("time_remaining"),
            filament_change_in=sj.get("filament_change_in"),
        )
        last_job = job
    else:
        job = None
    with lock:
        events.extend(new_events)
        status.update(online=True, state=state, job=job, last_job=last_job,
                      printer={"speed": p.get("speed"), "flow": p.get("flow"), "z": p.get("axis_z")})
    return {
        "noz": p.get("temp_nozzle"), "noz_t": p.get("target_nozzle"),
        "bed": p.get("temp_bed"), "bed_t": p.get("target_bed"),
        "z": p.get("axis_z"), "r_print": p.get("fan_print"), "r_hbr": p.get("fan_hotend"),
    }


def refresh_info():
    v = pl_get("/api/version") or {}
    if v:
        status["info"] = {"fw": v.get("firmware"), "link": v.get("server"), "host": v.get("hostname")}


def sample_loop():
    n = 0
    while True:
        t0 = time.time()
        if n % 1800 == 0 or not status["info"]:
            refresh_info()
        vals = poll_once(t0)
        with lock:
            for k, spec in UDP_MAP.items():
                vals[k] = udp_value(spec, t0)
            rows.append((round(t0, 1), [vals.get(k) for k in KEYS]))
            status["v"] = {k: vals.get(k) for k in KEYS}
            status["t"] = round(t0, 1)
            status["udp"] = t0 - udp_last < UDP_STALE_S
        n += 1
        if n % 150 == 0:
            save()
        time.sleep(max(0.2, SAMPLE_S - (time.time() - t0)))


# ---------------------------------------------------------------- persistence
def state_path():
    return os.path.join(STATE_DIR, "history.json")


def save():
    with lock:
        data = {"keys": KEYS, "rows": list(rows), "events": list(events), "last_job": last_job}
    tmp = state_path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(tmp, state_path())


def load():
    global last_job
    try:
        with open(state_path()) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return
    idx = [data["keys"].index(k) if k in data["keys"] else None for k in KEYS]
    cut = time.time() - HISTORY_H * 3600
    for t, vals in data.get("rows", []):
        if t >= cut:
            rows.append((t, [vals[i] if i is not None else None for i in idx]))
    events.extend(e for e in data.get("events", []) if e["t"] >= cut)
    last_job = data.get("last_job")
    status["last_job"] = last_job
    log(f"restored {len(rows)} rows")


# ---------------------------------------------------------------- HTTP
def agg_of(k):
    return (UDP_MAP.get(k) or {}).get("agg", "mean")


def history(since, points):
    with lock:
        sel = [r for r in rows if r[0] >= since]
        ev = [e for e in events if e["t"] >= since]
    out = {"keys": KEYS, "t": [], "events": ev}
    cols = {k: [] for k in KEYS}
    if sel and len(sel) > points:
        width = (sel[-1][0] - sel[0][0]) / points or 1
        buckets, cur, edge = [], [], sel[0][0] + width
        for r in sel:
            if r[0] >= edge and cur:
                buckets.append(cur)
                cur = []
                while r[0] >= edge:
                    edge += width
            cur.append(r)
        buckets.append(cur)
    else:
        buckets = [[r] for r in sel]
    for b in buckets:
        out["t"].append(b[-1][0])
        for i, k in enumerate(KEYS):
            vs = [r[1][i] for r in b if r[1][i] is not None]
            if not vs:
                v = None
            elif len(vs) == 1:
                v = vs[0]
            else:
                a = agg_of(k)
                v = max(vs) if a == "max" else min(vs) if a == "min" else round(sum(vs) / len(vs), 2)
            cols[k].append(v)
    out.update(cols)
    return out


def metrics_dump():
    now = time.time()
    with lock:
        return {
            name: [{"tags": dict(tags), "fields": fields, "age": round(now - t, 1)}
                   for tags, (fields, t) in by_tags.items()]
            for name, by_tags in sorted(latest.items())
        }


INDEX_HTML = b""


class Handler(BaseHTTPRequestHandler):
    server_version = "printcam"

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json", cache="no-store"):
        if not isinstance(body, (bytes, bytearray)):
            body = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(u.query)
        try:
            if u.path in ("/", "/index.html"):
                return self.send(200, INDEX_HTML, "text/html; charset=utf-8")
            if u.path == "/printer/status":
                with lock:
                    body = json.dumps(status, separators=(",", ":"))
                return self.send(200, body.encode())
            if u.path == "/printer/history":
                since = float(q.get("since", ["0"])[0])
                points = max(10, min(5000, int(q.get("points", ["1500"])[0])))
                return self.send(200, history(since, points))
            if u.path == "/printer/thumb":
                return self.thumb()
            if u.path == "/printer/metrics":
                return self.send(200, metrics_dump())
        except ValueError:
            return self.send(400, {"error": "bad query"})
        self.send(404, {"error": "not found"})

    def thumb(self):
        job = status.get("job") or status.get("last_job") or {}
        ref, jid = job.get("thumb"), job.get("id")
        if not ref:
            return self.send(404, {"error": "no thumbnail"})
        if jid not in thumbs:
            png = pl_get(ref, raw=True)
            if not png:
                return self.send(502, {"error": "printer unreachable"})
            thumbs.clear()
            thumbs[jid] = png
        self.send(200, thumbs[jid], "image/png", "max-age=86400")


def main():
    global opener, INDEX_HTML
    opener = make_opener()
    if INDEX:
        with open(INDEX, "rb") as f:
            INDEX_HTML = f.read().replace(b"__STREAM__", STREAM.encode())
    load()

    def stop(*_):
        save()
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    threading.Thread(target=udp_loop, daemon=True).start()
    if opener:
        threading.Thread(target=sample_loop, daemon=True).start()
    else:
        log("PRUSALINK_HOST / PRUSALINK_PASSWORD_FILE unset: UDP only, no sampling")
    log(f"http on {HTTP_BIND}:{HTTP_PORT}, keys: {' '.join(KEYS)}")
    ThreadingHTTPServer((HTTP_BIND, HTTP_PORT), Handler).serve_forever()


main()
