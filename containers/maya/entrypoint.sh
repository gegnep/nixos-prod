#!/bin/bash
# containers/maya/entrypoint.sh  (gegnep/nixos-prod)
#
# maya-entrypoint setup|serve COMMIT [maya.sh args...]
#
# /data is /var/lib/models/cache/maya: re-creatable, outside btrbk and restic.
#   /data/src/<commit>  the checkout, with its .venv, build-hip/ and configs
#   /data/models        weights (<quant>/ folders) and the packs next to them
#   /data/home          HOME: pip's cache, ~/.config/project-maya
# A pin bump is a new src folder, so it needs a setup again (ai maya-setup).
set -euo pipefail

mode=${1:?usage: maya-entrypoint setup|serve COMMIT [args...]}
commit=${2:?usage: maya-entrypoint setup|serve COMMIT [args...]}
shift 2
[[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "maya-entrypoint: not a commit: $commit" >&2; exit 1; }

src=/data/src/$commit
export HOME=/data/home
mkdir -p "$HOME" /data/src /data/models

if [ ! -e "$src/.maya-commit" ]; then
  if [ "$mode" != setup ]; then
    echo "maya-entrypoint: no checkout of $commit; run: ai maya-setup <quant>" >&2
    exit 1
  fi
  echo "maya-entrypoint: fetching project-maya $commit"
  rm -rf "$src.tmp"
  git init -q "$src.tmp"
  git -C "$src.tmp" fetch -q --depth 1 https://github.com/mw00/project-maya "$commit"
  git -C "$src.tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD
  echo "$commit" >"$src.tmp/.maya-commit"
  mv "$src.tmp" "$src"
fi

case $mode in
  setup | serve) ;;
  *) echo "maya-entrypoint: unknown mode $mode" >&2; exit 1 ;;
esac
cd "$src"
exec ./maya.sh "$@"
