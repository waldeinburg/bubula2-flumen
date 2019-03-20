#!/usr/bin/env bash
# Copy via SSH when scp is missing.
source config-copy-to-pi.inc.sh

SRC="$1"
DEST="$2"

if [[ ! -f "$SRC" ]]; then
    echo "$SRC is not a regular file" >&2
    exit 1
fi

# Allow copy to folder.
if [[ "$(echo -n "$DEST" | tail -c1)" = "/" ]]; then
    DEST="${DEST}/$(basename "$SRC")"
fi

echo "echo $(base64 -w0 "$SRC") | base64 -d > '$DEST'" | ssh "$SSH_USER"@"$SSH_HOST" bash
# TODO: change permissions
