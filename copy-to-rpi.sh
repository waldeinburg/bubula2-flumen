#!/usr/bin/env bash
# Copy via SSH when scp is missing.

cd $(dirname "$0") || exit 1
source config-dev.inc.sh
cd - > /dev/null

DEST_DIR=${@:$#}

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 SOURCE... DEST_DIR" >&2
    exit 1
fi

tar -c "${@:1:$#-1}" | ssh "$SSH_USER"@"$SSH_HOST" \
  "[[ -d '${DEST_DIR}' ]] && tar --no-same-owner -x -C '${DEST_DIR}' || echo '${DEST_DIR} is not a directory!' >&2"
