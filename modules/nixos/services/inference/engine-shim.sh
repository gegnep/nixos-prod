# engine-shim ENGINE ID [ARGS...]
#
# llama-swap's `cmd` for engines that run as systemd units (radiance@, maya@).
# Runs as user llama-swap; polkit (inference.nix) lets it start and stop those
# units and nothing else. llama-swap health-checks the engine's port, so this
# process only has to live exactly as long as the unit:
#   1. refuse while Unsloth Studio holds the GPUs
#   2. stop any other engine unit (llama-swap already unloaded its model, so a
#      unit still up is an orphan or still releasing VRAM)
#   3. write ARGS to /run/llama-swap/ENGINE-ID.env for the unit's ExecStart
#   4. start the unit, then wait while it runs; exit 1 if it stops by itself
#   5. on SIGTERM (unload, swap, llama-swap stop): stop the unit, then exit
#
# The unit word-splits ENGINE_ARGS ($ENGINE_ARGS in ExecStart, no shell), and
# the args land after the image name, so a model file can change engine flags
# only, never mounts, devices or the image.

say() { echo "engine-shim: $*"; }
die() {
  echo "engine-shim: $*" >&2
  exit 1
}

[ $# -ge 2 ] || die "usage: engine-shim ENGINE ID [ARGS...]"
engine=$1
id=$2
shift 2
case $engine in
  radiance | maya) ;;
  *) die "unknown engine '$engine'" ;;
esac
[[ $id =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "invalid model id '$id'"
for a in "$@"; do
  [[ $a =~ ^[A-Za-z0-9._/:=,+@-]+$ ]] ||
    die "argument '$a' has a character the env file cannot carry (allowed: A-Z a-z 0-9 . _ / : = , + @ -)"
done

unit="$engine@$id.service"
envfile="/run/llama-swap/$engine-$id.env"
# llama-swap runs with ProtectProc=invisible, so /proc/1 is hidden and
# systemctl's chroot probe cannot compare roots. Skip the probe outright.
export SYSTEMD_IGNORE_CHROOT=1
sctl() { systemctl --no-ask-password "$@"; }

if systemctl is-active --quiet podman-unsloth.service; then
  die "Unsloth Studio holds the GPUs; run ai train off first"
fi

mapfile -t others < <(systemctl list-units --plain --no-legend \
  --state=active,activating,deactivating 'radiance@*.service' 'maya@*.service' | awk '{print $1}')
for u in "${others[@]}"; do
  say "stopping $u before $unit"
  sctl stop "$u" || die "could not stop $u"
done

printf 'ENGINE_ARGS=%s\n' "$*" >"$envfile.tmp"
mv -f "$envfile.tmp" "$envfile"
trap 'rm -f "$envfile"' EXIT

stopping=0
stop_unit() {
  stopping=1
  say "stopping $unit"
  sctl stop "$unit"
  exit 0
}
trap stop_unit TERM INT

say "starting $unit: $*"
# Blocks until the container runs (Type=notify), including an image pull on
# first use. A SIGTERM meanwhile kills this client too, and the trap stops the unit.
if ! sctl start "$unit"; then
  [ "$stopping" = 1 ] || die "$unit failed to start; journalctl -u $unit"
fi

while :; do
  state=$(systemctl show -P ActiveState "$unit")
  case $state in
    active | activating | reloading) ;;
    *) die "$unit is $state ($(systemctl show -P Result "$unit")); journalctl -u $unit" ;;
  esac
  sleep 2 &
  wait $! || true
done
