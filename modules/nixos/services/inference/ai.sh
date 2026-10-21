# ai: operate this host's model stack.
# llama-swap is the front door; each model is one YAML file in $AI_MODELS_DIR,
# which llama-swap watches and reloads. Engines and globals come from Nix.
# Environment (set by inference.nix): AI_URL AI_BASE_CONFIG AI_MODELS_DIR
# AI_CACHE AI_ENGINES AI_STUDIO AI_OWNER AI_SUDO (empty = run as the caller).

: "${AI_URL:?}" "${AI_BASE_CONFIG:?}" "${AI_MODELS_DIR:?}" "${AI_CACHE:?}"
: "${AI_ENGINES:=llama}" "${AI_STUDIO:=0}" "${AI_OWNER:=llama-swap}" "${AI_SUDO=sudo}"

die() {
  echo "ai: $*" >&2
  exit 1
}

# Temp files live until the script exits; locals would be unset by then.
tmpfiles=()
cleanup() { rm -rf "${tmpfiles[@]}"; }
trap cleanup EXIT

usage() {
  cat <<EOF
usage: ai [command]   (no command: interactive menu)

  st                       loaded model, GPUs, engine units
  ls                       registered models
  add ID (--model PATH | --from REPO[:GLOB]) [--engine E] [--name N]
         [--ttl SECONDS] [--resident] [--yes] [-- ENGINE ARGS...]
                           register a model (engines here: $AI_ENGINES)
  edit ID                  edit a model file in \$EDITOR, validate, install
  rm ID [--purge] [--yes]  remove a model; --purge also deletes its weights
  pull REPO [GLOB]         download weights into $AI_CACHE/llama
  up ID                    load a model now
  down [ID]                unload one model, or all
  logs [ID]                follow llama-swap logs (all, or one model)
  bench ID [MAX_TOKENS]    ~1.9k-token prompt, report prefill and decode speed
EOF
  if [ "$AI_STUDIO" = 1 ]; then
    echo "  train on|off|st          hand the GPUs to Unsloth Studio, or take them back"
  fi
}

# Run a command as root (or as the caller when AI_SUDO is empty).
root() {
  if [ -n "$AI_SUDO" ]; then "$AI_SUDO" "$@"; else "$@"; fi
}

# Run a command as the llama-swap user, so pulled weights carry its ownership.
as_owner() {
  if [ -n "$AI_SUDO" ]; then "$AI_SUDO" -u "$AI_OWNER" "$@"; else "$@"; fi
}

interactive() { [ -t 0 ] && [ -t 1 ]; }

confirm() {
  if [ "${yes:-0}" = 1 ]; then return 0; fi
  interactive || die "$1 (rerun with --yes to proceed non-interactively)"
  gum confirm "$1"
}

valid_id() {
  [[ $1 =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "invalid model id '$1' (use [a-z0-9._-], starting alphanumeric)"
}

model_file() { printf '%s/%s.yaml\n' "$AI_MODELS_DIR" "$1"; }

model_ids() {
  local f
  for f in "$AI_MODELS_DIR"/*.yaml; do
    [ -e "$f" ] || continue
    yq -r '.models // {} | keys | .[]' "$f"
  done
}

running_ids() {
  curl -fsS -m 5 "$AI_URL/running" | jq -r '.running[]?.model'
}

pick_model() {
  local ids
  ids=$(model_ids)
  [ -n "$ids" ] || die "no models registered (ai add)"
  gum choose --header "${1:-model}" <<<"$ids"
}

# llama-swap polls models.d every 2s. Wait until /v1/models shows the change,
# so a following `ai up` does not race the reload. $2: present | absent | changed.
await_reload() {
  local id=$1 want=$2 i listed
  if ! curl -fsS -m 2 "$AI_URL/health" >/dev/null 2>&1; then
    echo "ai: llama-swap is not running; the change applies when it starts" >&2
    return 0
  fi
  if [ "$want" = changed ]; then
    sleep 3 # same id before and after: nothing to poll for
    return 0
  fi
  for i in $(seq 1 15); do
    listed=absent
    if curl -fsS -m 2 "$AI_URL/v1/models" | jq -e --arg id "$id" 'any(.data[]; .id == $id)' >/dev/null; then
      listed=present
    fi
    if [ "$listed" = "$want" ]; then return 0; fi
    sleep 1
  done
  echo "ai: llama-swap has not reloaded after ${i}s; check ai logs" >&2
}

# Validate the merged config with $2 installed as $1's file, then install it.
# A reload unloads whatever is running, so confirm first when something is.
install_model_file() {
  local id=$1 src=$2 staging running out
  staging=$(mktemp -d)
  tmpfiles+=("$staging")
  find "$AI_MODELS_DIR" -maxdepth 1 -name '*.yaml' ! -name "$id.yaml" -exec cp -t "$staging" {} +
  cp "$src" "$staging/$id.yaml"
  if ! out=$(llama-swap -validate -config "$AI_BASE_CONFIG" -config-dir "$staging" 2>&1); then
    echo "$out" >&2
    die "config does not validate; nothing installed"
  fi
  running=$(running_ids 2>/dev/null | paste -sd, - || true)
  if [ -n "$running" ]; then
    confirm "llama-swap reloads and unloads $running. Continue?" || die "aborted"
  fi
  root install -m 0644 -o "$AI_OWNER" -g "$AI_OWNER" "$src" "$AI_MODELS_DIR/.$id.yaml.tmp"
  root mv -f "$AI_MODELS_DIR/.$id.yaml.tmp" "$(model_file "$id")"
}

hf_env() {
  local token=
  if root test -r /run/secrets/hf-token; then token=$(root cat /run/secrets/hf-token); fi
  printf 'HF_HOME=%s\nHF_TOKEN=%s\n' "$AI_CACHE/hf-home" "$token"
}

cmd_pull() {
  local repo=${1:-} glob=${2:-} dest
  [ -n "$repo" ] || die "usage: ai pull REPO [GLOB]"
  [[ $repo =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "invalid repo '$repo'"
  dest=$AI_CACHE/llama/$repo
  as_owner mkdir -p "$dest"
  local args=(download "$repo" --local-dir "$dest")
  if [ -n "$glob" ]; then args+=(--include "$glob"); fi
  # shellcheck disable=SC2046 # hf_env prints KEY=VALUE words for env
  as_owner env $(hf_env) "$(command -v hf)" "${args[@]}" >&2
  printf '%s\n' "$dest"
}

# Pick the model file in a pulled directory: one GGUF, or the first shard.
pick_gguf() {
  local dir=$1 glob=$2 files
  mapfile -t files < <(find "$dir" -name '*.gguf' ! -name 'mmproj*' -path "*${glob:-}*" | sort)
  [ ${#files[@]} -gt 0 ] || die "no .gguf in $dir matching '${glob:-*}'"
  if [ ${#files[@]} -gt 1 ]; then
    local shards
    mapfile -t shards < <(printf '%s\n' "${files[@]}" | grep -E -- '-00001-of-[0-9]+\.gguf$' || true)
    [ ${#shards[@]} -eq 1 ] || die "several GGUFs match; pass --model with one of:$(printf '\n  %s' "${files[@]}")"
    files=("${shards[0]}")
  fi
  printf '%s\n' "${files[0]}"
}

cmd_add() {
  local id=${1:-}
  [ -n "$id" ] || die "usage: ai add ID (--model PATH | --from REPO[:GLOB]) [-- ARGS...]"
  shift
  valid_id "$id"
  [ ! -e "$(model_file "$id")" ] || die "$id exists; use ai edit $id"
  local engine=llama model='' from='' name='' ttl='' resident=0 extra=()
  yes=0
  while [ $# -gt 0 ]; do
    case $1 in
      --engine) engine=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --from) from=$2; shift 2 ;;
      --name) name=$2; shift 2 ;;
      --ttl) ttl=$2; shift 2 ;;
      --resident) resident=1; shift ;;
      --yes) yes=1; shift ;;
      --) shift; extra=("$@"); break ;;
      *) die "unknown flag $1" ;;
    esac
  done
  [[ " $AI_ENGINES " == *" $engine "* ]] || die "engine '$engine' is not enabled on this host (have: $AI_ENGINES)"
  [ "$engine" = llama ] || die "engine '$engine' is not wired into ai yet"
  if [ -n "$ttl" ] && ! [[ $ttl =~ ^[0-9]+$ ]]; then die "--ttl takes seconds"; fi

  if [ -n "$from" ]; then
    [ -z "$model" ] || die "pass --model or --from, not both"
    local repo=${from%%:*} glob='' dir
    if [[ $from == *:* ]]; then glob=${from#*:}; fi
    dir=$(cmd_pull "$repo" "$glob")
    model=$(pick_gguf "$dir" "$glob")
  fi
  [ -n "$model" ] || die "pass --model PATH or --from REPO[:GLOB]"
  [ -r "$model" ] || die "cannot read $model"

  # shellcheck disable=SC2016 # ${llama} is a llama-swap macro, expanded by llama-swap
  local cmd='${llama}' arg mmproj
  cmd+=" -m $(printf '%q' "$model")"
  # A vision model ships its projector next to the weights.
  mmproj=$(find "$(dirname "$model")" -maxdepth 1 -name 'mmproj*.gguf' | sort | head -n1)
  if [ -n "$mmproj" ]; then
    cmd+=" --mmproj $(printf '%q' "$mmproj")"
    echo "ai: using projector $mmproj (drop it with ai edit $id)" >&2
  fi
  for arg in "${extra[@]}"; do cmd+=" $(printf '%q' "$arg")"; done

  local tmp
  tmp=$(mktemp)
  tmpfiles+=("$tmp")
  ID=$id CMD=$cmd yq -n '.models[strenv(ID)].cmd = strenv(CMD)' >"$tmp"
  if [ -n "$name" ]; then ID=$id NAME=$name yq -i '.models[strenv(ID)].name = strenv(NAME)' "$tmp"; fi
  if [ -n "$ttl" ]; then ID=$id TTL=$ttl yq -i '.models[strenv(ID)].ttl = (strenv(TTL) | tonumber)' "$tmp"; fi
  if [ "$resident" = 1 ]; then
    # Its own group: stays loaded, never evicts or is evicted by the swap group.
    ID=$id yq -i '.routing.router.settings.groups[strenv(ID)] = {"members": [strenv(ID)], "swap": false, "exclusive": false, "persistent": true}' "$tmp"
  fi
  sed -i "1i # managed by ai; edit with: ai edit $id" "$tmp"
  install_model_file "$id" "$tmp"
  await_reload "$id" present
  echo "ai: added $id"
  cat "$(model_file "$id")"
}

cmd_edit() {
  local id=${1:-} tmp
  [ -n "$id" ] || { interactive && id=$(pick_model "edit"); }
  [ -n "$id" ] || die "usage: ai edit ID"
  [ -e "$(model_file "$id")" ] || die "no model $id"
  tmp=$(mktemp --suffix=.yaml)
  tmpfiles+=("$tmp")
  cp "$(model_file "$id")" "$tmp"
  "${EDITOR:-vi}" "$tmp"
  if cmp -s "$tmp" "$(model_file "$id")"; then
    echo "ai: no changes"
    return
  fi
  yes=0
  install_model_file "$id" "$tmp"
  await_reload "$id" changed
  echo "ai: updated $id"
}

# Weight paths a model file references (-m and --mmproj values).
model_paths() {
  yq -r '.models[].cmd' "$1" | grep -oE -- '(^| )(-m|--mmproj) [^ ]+' | awk '{print $NF}'
}

cmd_rm() {
  local id='' purge=0 f
  yes=0
  while [ $# -gt 0 ]; do
    case $1 in
      --purge) purge=1; shift ;;
      --yes) yes=1; shift ;;
      -*) die "unknown flag $1" ;;
      *) id=$1; shift ;;
    esac
  done
  [ -n "$id" ] || { interactive && id=$(pick_model "remove"); }
  [ -n "$id" ] || die "usage: ai rm ID [--purge] [--yes]"
  f=$(model_file "$id")
  [ -e "$f" ] || die "no model $id"
  local paths=() p other
  if [ "$purge" = 1 ]; then
    mapfile -t paths < <(model_paths "$f")
  fi
  confirm "Remove $id$([ "$purge" = 1 ] && echo " and its weights")?" || die "aborted"
  root rm -f "$f"
  await_reload "$id" absent
  echo "ai: removed $id"
  for p in "${paths[@]}"; do
    [[ $p == "$AI_CACHE"/* ]] || { echo "ai: keeping $p (outside $AI_CACHE)"; continue; }
    other=$(grep -lF -- "$p" "$AI_MODELS_DIR"/*.yaml 2>/dev/null || true)
    if [ -n "$other" ]; then
      echo "ai: keeping $p (used by $other)"
    else
      root rm -f -- "$p"
      echo "ai: deleted $p"
    fi
  done
}

cmd_ls() {
  local running f id cmd state
  running=" $(running_ids 2>/dev/null | paste -sd' ' - || true) "
  {
    echo "ID STATE ENGINE MODEL"
    for f in "$AI_MODELS_DIR"/*.yaml; do
      [ -e "$f" ] || continue
      while IFS= read -r id; do
        cmd=$(ID=$id yq -r '.models[strenv(ID)].cmd' "$f")
        state=-
        if [[ $running == *" $id "* ]]; then state=loaded; fi
        printf '%s %s %s %s\n' "$id" "$state" \
          "$(sed -E 's/^\$\{([a-z]+)\}.*/\1/' <<<"$cmd")" \
          "$(grep -oE -- '-m [^ ]+' <<<"$cmd" | cut -d' ' -f2 | xargs -r basename)"
      done < <(yq -r '.models // {} | keys | .[]' "$f")
    done
  } | column -t
}

gpu_status() {
  local d mem used total busy temp name
  if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu \
      --format=csv,noheader
  fi
  for d in /sys/class/drm/card[0-9]*/device; do
    [ "$(cat "$d/vendor" 2>/dev/null)" = 0x1002 ] || continue
    used=$(($(cat "$d/mem_info_vram_used") / 1048576))
    total=$(($(cat "$d/mem_info_vram_total") / 1048576))
    busy=$(cat "$d/gpu_busy_percent" 2>/dev/null || echo '?')
    temp='?'
    for mem in "$d"/hwmon/hwmon*/temp2_input; do
      if [ -r "$mem" ]; then temp=$(($(cat "$mem") / 1000)); fi
    done
    name=$(basename "$(readlink -f "$d")")
    printf '%s, %s MiB / %s MiB, %s %%, junction %s C\n' "$name" "$used" "$total" "$busy" "$temp"
  done
}

cmd_st() {
  echo "== loaded"
  curl -fsS -m 5 "$AI_URL/running" | jq -r '.running[]? | "\(.model)  \(.state)"' ||
    echo "llama-swap unreachable at $AI_URL"
  echo "== gpus"
  gpu_status
  local units
  units=$(systemctl list-units --no-legend --plain 'radiance@*' 'maya@*' 'podman-unsloth.service' 2>/dev/null | awk '{print $1, $3, $4}')
  if [ -n "$units" ]; then
    echo "== units"
    echo "$units"
  fi
}

cmd_up() {
  local id=${1:-}
  [ -n "$id" ] || { interactive && id=$(pick_model "load"); }
  [ -n "$id" ] || die "usage: ai up ID"
  echo "ai: loading $id (large models take minutes)"
  curl -fsS -m 1800 -o /dev/null "$AI_URL/upstream/$id/health" || die "load failed; see ai logs $id"
  echo "ai: $id ready"
}

cmd_down() {
  local id=${1:-}
  if [ -n "$id" ]; then
    curl -fsS -X POST "$AI_URL/api/models/unload/$id" >/dev/null
    echo "ai: unloaded $id"
  else
    curl -fsS -X POST "$AI_URL/api/models/unload" >/dev/null
    echo "ai: unloaded all"
  fi
}

cmd_logs() {
  local id=${1:-}
  exec curl -fsSN "$AI_URL/logs/stream${id:+/$id}"
}

cmd_bench() {
  local id=${1:-} max=${2:-256} body start end resp para prompt i
  [ -n "$id" ] || { interactive && id=$(pick_model "bench"); }
  [ -n "$id" ] || die "usage: ai bench ID [MAX_TOKENS]"
  cmd_up "$id" >/dev/null
  # ~1.9k prompt tokens on a typical tokenizer: big enough that prefill measures
  # throughput, small enough for a model whose context is split over several slots.
  # The leading nonce changes the prefix, so no engine serves it from a prompt cache.
  para="The engineer reviews a B-tree implementation: node splits on insertion, key redistribution between siblings, merges on deletion, and the invariant that every leaf sits at the same depth."
  prompt="Run $RANDOM$RANDOM. Summarize these repeated review notes in three sentences."
  for i in $(seq 1 40); do prompt+=" $para"; done
  body=$(jq -n --arg m "$id" --argjson n "$max" --arg p "$prompt" '{
    model: $m, max_tokens: $n, temperature: 0, stream: false,
    messages: [{role: "user", content: $p}]
  }')
  start=$(date +%s.%N)
  resp=$(curl -sS -m 1800 "$AI_URL/v1/chat/completions" -H 'Content-Type: application/json' -d "$body")
  end=$(date +%s.%N)
  if jq -e '.error' <<<"$resp" >/dev/null 2>&1; then
    die "bench failed: $(jq -r '.error.message // .error' <<<"$resp")"
  fi
  jq -r --arg wall "$(awk -v s="$start" -v e="$end" 'BEGIN { print e - s }')" '
    if .timings then
      "prefill \(.timings.prompt_n) tok @ \(.timings.prompt_per_second | floor) tok/s, decode \(.timings.predicted_n) tok @ \(.timings.predicted_per_second * 10 | floor / 10) tok/s"
    else
      "\(.usage.prompt_tokens) prompt + \(.usage.completion_tokens) completion tokens in \($wall | tonumber * 100 | floor / 100) s (no engine timings)"
    end' <<<"$resp"
}

cmd_train() {
  [ "$AI_STUDIO" = 1 ] || die "Unsloth Studio is not enabled on this host"
  case ${1:-st} in
    on)
      # Stop the front door, not just unload: a stray request would reload a
      # model onto the GPUs under the training run.
      root systemctl stop llama-swap.service
      root systemctl start podman-unsloth.service
      echo "ai: Studio up; llama-swap stopped until ai train off"
      ;;
    off)
      root systemctl stop podman-unsloth.service
      root systemctl start llama-swap.service
      # start returns before llama-swap listens; a command right after would get
      # connection refused.
      for _ in $(seq 1 30); do
        if curl -fs -m 2 -o /dev/null "$AI_URL/running"; then
          echo "ai: Studio stopped; llama-swap back"
          return 0
        fi
        sleep 1
      done
      die "llama-swap started but not answering at $AI_URL after 30s; see journalctl -u llama-swap"
      ;;
    st) systemctl is-active podman-unsloth.service || true ;;
    *) die "usage: ai train on|off|st" ;;
  esac
}

menu() {
  interactive || {
    usage
    exit 1
  }
  local choice
  local items=(st ls up down bench logs add edit rm)
  if [ "$AI_STUDIO" = 1 ]; then items+=("train on" "train off"); fi
  choice=$(gum choose --header "ai" "${items[@]}") || exit 0
  case $choice in
    add)
      local id src
      id=$(gum input --placeholder "model id (a-z0-9._-)")
      src=$(gum input --placeholder "HF repo[:glob] or /path/to/model.gguf")
      if [[ $src == /* ]]; then cmd_add "$id" --model "$src"; else cmd_add "$id" --from "$src"; fi
      ;;
    "train on") cmd_train on ;;
    "train off") cmd_train off ;;
    *) "cmd_$choice" ;;
  esac
}

sub=${1:-}
if [ $# -gt 0 ]; then shift; fi
case $sub in
  "") menu ;;
  st | ls | add | edit | rm | pull | up | down | logs | bench | train) "cmd_$sub" "$@" ;;
  -h | --help | help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
