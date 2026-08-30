{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.tinyfish-search;

  shim =
    pkgs.writers.writePython3Bin "tinyfish-search-shim"
      {
        flakeIgnore = [
          "E501"
          "E265"
        ];
      }
      ''
        # Three routes, one bearer token:
        #   POST /search        Open WebUI `external` web search contract
        #   POST /tools/search  richer search results for the Open WebUI Tool
        #   POST /tools/fetch   TinyFish Fetch API passthrough
        # The TinyFish API key stays here, out of the Open WebUI database.
        import hmac
        import json
        import os
        import urllib.parse
        import urllib.request
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        SEARCH_UPSTREAM = "https://api.search.tinyfish.ai"
        FETCH_UPSTREAM = "https://api.fetch.tinyfish.ai"
        PORT = int(os.environ["SHIM_PORT"])
        MAX_CHARS = 20000


        def read_secret(var):
            with open(os.environ[var]) as f:
                return f.read().strip()


        API_KEY = read_secret("TINYFISH_API_KEY_FILE")
        TOKEN = read_secret("SHIM_TOKEN_FILE")


        def tf_get(url):
            req = urllib.request.Request(url, headers={"X-API-Key": API_KEY})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)


        def tf_post(url, payload):
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode(),
                headers={
                    "X-API-Key": API_KEY,
                    "Content-Type": "application/json",
                },
            )
            # Fetch allows 110s per URL and a 120s CDN ceiling; docs advise 150s.
            with urllib.request.urlopen(req, timeout=150) as resp:
                return json.load(resp)


        def raw_search(query):
            params = {"query": query, "location": "US", "language": "en"}
            url = SEARCH_UPSTREAM + "?" + urllib.parse.urlencode(params)
            return tf_get(url).get("results", [])


        def search_owui(query, count):
            out = []
            for r in raw_search(query)[:count]:
                link = r.get("url")
                if not link:
                    continue
                out.append({
                    "link": link,
                    "title": r.get("title") or link,
                    "snippet": r.get("snippet") or "",
                })
            return out


        def search_tool(query, count):
            out = []
            for r in raw_search(query)[:count]:
                out.append({
                    "url": r.get("url"),
                    "title": r.get("title"),
                    "snippet": r.get("snippet"),
                    "domain": r.get("domain"),
                    "date": r.get("date"),
                })
            return out


        def fetch_tool(urls):
            body = tf_post(FETCH_UPSTREAM, {"urls": urls[:10], "format": "markdown"})
            out = []
            for r in body.get("results", []):
                text = r.get("text") or ""
                if isinstance(text, str) and len(text) > MAX_CHARS:
                    text = text[:MAX_CHARS] + "\n\n[truncated]"
                out.append({
                    "url": r.get("final_url") or r.get("url"),
                    "title": r.get("title"),
                    "text": text,
                })
            for e in body.get("errors", []):
                out.append({"url": e.get("url"), "error": e.get("error")})
            return out


        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def reply(self, code, payload):
                data = json.dumps(payload).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def authed(self):
                expected = "Bearer " + TOKEN
                got = self.headers.get("Authorization", "")
                return hmac.compare_digest(got, expected)

            def body(self):
                n = int(self.headers.get("Content-Length", 0))
                return json.loads(self.rfile.read(n) or b"{}")

            def do_POST(self):
                route = self.path.split("?")[0]
                if route not in ("/search", "/tools/search", "/tools/fetch"):
                    self.reply(404, {"detail": "not found"})
                    return
                if not self.authed():
                    self.reply(401, {"detail": "unauthorized"})
                    return
                try:
                    req = self.body()
                    if route == "/tools/fetch":
                        urls = req["urls"]
                        if not isinstance(urls, list) or not urls:
                            raise ValueError("urls must be a non-empty list")
                        args = (urls,)
                    else:
                        args = (req["query"], int(req.get("count", 5)))
                except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                    self.reply(400, {"detail": "bad request"})
                    return

                try:
                    if route == "/search":
                        self.reply(200, search_owui(*args))
                    elif route == "/tools/search":
                        self.reply(200, search_tool(*args))
                    else:
                        self.reply(200, fetch_tool(*args))
                except Exception as e:
                    print("tinyfish call failed: %r" % e, flush=True)
                    # /search must degrade to [] per the Open WebUI contract;
                    # the tool routes surface the error so the model can react.
                    if route == "/search":
                        self.reply(200, [])
                    else:
                        self.reply(200, {"error": repr(e)})

            def log_message(self, fmt, *args):
                print(fmt % args, flush=True)


        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
      '';
in
{
  options.mySystem.services.tinyfish-search = {
    enable = lib.mkEnableOption "TinyFish search shim for Open WebUI";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8111;
      description = "Loopback port for the shim";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.tinyfish-api-key.restartUnits = [ "tinyfish-search.service" ];
    sops.secrets.owui-search-token.restartUnits = [ "tinyfish-search.service" ];

    systemd.services.tinyfish-search = {
      description = "TinyFish search shim for Open WebUI";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        SHIM_PORT = toString cfg.port;
        # %d is CREDENTIALS_DIRECTORY: systemd copies the sops secrets there
        # as root at start, readable by the dynamic uid.
        TINYFISH_API_KEY_FILE = "%d/tinyfish";
        SHIM_TOKEN_FILE = "%d/token";
      };

      serviceConfig = {
        ExecStart = lib.getExe shim;
        Restart = "on-failure";
        RestartSec = 10;

        DynamicUser = true;
        LoadCredential = [
          "tinyfish:${config.sops.secrets.tinyfish-api-key.path}"
          "token:${config.sops.secrets.owui-search-token.path}"
        ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
