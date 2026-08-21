#!/usr/bin/env bash
# containers/unsloth/entrypoint.sh  (gegnep/nixos-prod)
#
# Sync baked studio code into the persistent volume on image-version change.
# Code dirs get rsync --delete; state (studio.db, auth/, datasets, everything
# else at the top of ~/.unsloth and ~/.unsloth/studio) is never touched.
set -euo pipefail

PRISTINE=/opt/unsloth-pristine
UHOME=/home/unsloth/.unsloth
STAMP_SRC="$PRISTINE/.image-stamp"
STAMP_DST="$UHOME/.image-stamp"

mkdir -p "$UHOME/studio"

if ! cmp -s "$STAMP_SRC" "$STAMP_DST" 2>/dev/null; then
    echo "[entrypoint] image stamp $(cat "$STAMP_SRC") != volume stamp $(cat "$STAMP_DST" 2>/dev/null || echo '<none>'); syncing runtime"
    # venv (includes frontend dist in site-packages)
    rsync -a --delete "$PRISTINE/studio/unsloth_studio/" "$UHOME/studio/unsloth_studio/"
    # llama.cpp lives at ~/.unsloth/llama.cpp (legacy-default shared build path);
    # this replaces the manual tarball seed permanently.
    rsync -a --delete "$PRISTINE/llama.cpp/" "$UHOME/llama.cpp/"
    cp "$STAMP_SRC" "$STAMP_DST"
    echo "[entrypoint] sync done"
fi

exec "$UHOME/studio/unsloth_studio/bin/unsloth" studio \
    --host 0.0.0.0 --port 8000 "$@"
