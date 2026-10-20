# Bump external version pins in pins.json to the latest upstream release.
#   update-pins            update every pin that is set (null pins are skipped)
#   update-pins NAME...    update only NAMEs; creates the pin if missing or null
# Pins: unsloth radiance maya llamaCpp

root=$(git rev-parse --show-toplevel)
pins=$root/pins.json
[ -f "$pins" ] || {
  echo "error: no pins.json at $root" >&2
  exit 1
}

# latest_tag URL ERE: highest version-sorted tag whose name matches ERE
latest_tag() {
  git ls-remote --tags --refs "$1" | sed 's|.*refs/tags/||' | grep -E "$2" | sort -V | tail -n1
}

# tag_commit URL TAG: commit sha for TAG; annotated tags are peeled
tag_commit() {
  local refs sha
  refs=$(git ls-remote --tags "$1")
  sha=$(awk -v t="refs/tags/$2^{}" '$2 == t { print $1 }' <<<"$refs")
  [ -n "$sha" ] || sha=$(awk -v t="refs/tags/$2" '$2 == t { print $1 }' <<<"$refs")
  [ -n "$sha" ] || {
    echo "error: no tag $2 at $1" >&2
    return 1
  }
  printf '%s\n' "$sha"
}

# set_pin NAME JSON: atomic write, prints the change
set_pin() {
  local old tmp
  old=$(jq -c --arg k "$1" '.[$k]' "$pins")
  if [ "$old" = "$(jq -c . <<<"$2")" ]; then
    echo "$1: unchanged"
    return
  fi
  tmp=$(mktemp "$pins.XXXXXX")
  jq --indent 2 --arg k "$1" --argjson v "$2" '.[$k] = $v' "$pins" >"$tmp"
  mv "$tmp" "$pins"
  echo "$1: $old -> $(jq -c . <<<"$2")"
}

update_unsloth() {
  local version ref
  version=$(curl -fsS https://pypi.org/pypi/unsloth/json | jq -er .info.version)
  ref=$(latest_tag https://github.com/unslothai/unsloth '^v[0-9]+\.[0-9]+\.[0-9]+(-beta)?$')
  set_pin unsloth "$(jq -n --arg v "$version" --arg r "$ref" '{version: $v, studioRef: $r}')"
}

update_radiance() {
  local image=docker.io/stilldeadcode/radiance digest
  # Docker Hub publishes `latest` only, so the digest is the pin.
  digest=$(skopeo inspect --no-tags "docker://$image:latest" | jq -er .Digest)
  set_pin radiance "$(jq -n --arg i "$image" --arg d "$digest" '{image: $i, digest: $d}')"
}

update_maya() {
  local url=https://github.com/mw00/project-maya tag commit
  tag=$(latest_tag "$url" '^v[0-9]+\.[0-9]+\.[0-9]+$')
  commit=$(tag_commit "$url" "$tag")
  set_pin maya "$(jq -n --arg t "$tag" --arg c "$commit" '{tag: $t, commit: $c}')"
}

update_llamacpp() {
  local tag pf hash src npm
  tag=$(latest_tag https://github.com/ggml-org/llama.cpp '^v[0-9]+\.[0-9]+\.[0-9]+$')
  pf=$(nix flake prefetch --json "github:ggml-org/llama.cpp/$tag")
  hash=$(jq -er '.hash // .narHash' <<<"$pf")
  src=$(jq -er .storePath <<<"$pf")
  npm=$(prefetch-npm-deps "$src/tools/ui/package-lock.json")
  set_pin llamaCpp "$(jq -n --arg v "${tag#v}" --arg h "$hash" --arg n "$npm" \
    '{version: $v, hash: $h, npmDepsHash: $n}')"
}

if [ $# -eq 0 ]; then
  mapfile -t names < <(jq -r 'to_entries[] | select(.value != null) | .key' "$pins")
else
  names=("$@")
fi

for name in "${names[@]}"; do
  case $name in
    unsloth) update_unsloth ;;
    radiance) update_radiance ;;
    maya) update_maya ;;
    llamaCpp) update_llamacpp ;;
    *)
      echo "error: unknown pin '$name' (known: unsloth radiance maya llamaCpp)" >&2
      exit 1
      ;;
  esac
done
