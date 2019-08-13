#!/usr/bin/env bash

SERVER_SRC="server"
SYSTEMD_SRC="systemd"
TOOLS_SRC="tools"

SERVER_DIR="/var/flumen"
TOOLS_DIR="/usr/local/bin"

SERVER_FILES=(
    config-flumen-common.inc.sh
    config-flumen-entrance-server.inc.sh
    config-flumen-server.inc.sh
    flumen-common.inc.sh
    flumen-entrance-server.sh
    flumen-server.sh
)
SYSTEMD_FILES=(
    flumen.service
    flumen-entrance.service
    shutdown-after-flumen.timer
    shutdown.service
)
TOOLS_FILES=(
    entrance-log.sh
    flumen-log.sh
    save-flumen-logs.sh
)

INSTALL=

[[ "$1" = "INSTALL" ]] && INSTALL=1

ROOT_DIR=$(dirname "$0")
cd "$ROOT_DIR" || exit 1

source config-dev.inc.sh

# Required packages:
# - nc

ssh_run () {
    CMD="$1"
    echo "Running: ${CMD}"
    echo "$CMD" | ssh "$SSH_USER"@"$SSH_HOST" bash
}

[[ "$INSTALL" ]] && ssh_run "mkdir -p /var/flumen/img"

echo "Copying server files ..."
cd "${SERVER_SRC}" || exit 1
../copy-to-rpi.sh "${SERVER_FILES[@]}" "${SERVER_DIR}" || exit 2
cd - > /dev/null

echo "Copying systemd files ..."
cd "${SYSTEMD_SRC}" || exit 1
../copy-to-rpi.sh "${SYSTEMD_FILES[@]}" /etc/systemd/system || exit 2
cd - > /dev/null

echo "Copying tools ..."
cd "${TOOLS_SRC}" || exit 1
../copy-to-rpi.sh "${TOOLS_FILES[@]}" "${TOOLS_DIR}" || exit 2
cd - > /dev/null

if [[ "$INSTALL" ]]; then
    ssh_run "systemctl enable flumen.service" || exit 3
    ssh_run "systemctl enable flumen-entrance.service" || exit 3
    ssh_run "systemctl enable shutdown-after-flumen.timer" || exit 3
else
    ssh_run "systemctl daemon-reload" || exit 3
    ssh_run "systemctl restart flumen" || exit 3
fi

echo "Done!"
