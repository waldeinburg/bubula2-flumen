#!/usr/bin/env bash

SERVER_SRC="server"
SYSTEMD_SRC="systemd"
TOOLS_SRC="tools"

SERVER_DIR="/var/flumen"
TOOLS_DIR="/root"

INSTALL=

[[ "$1" = "INSTALL" ]] && INSTALL=1

cd $(dirname "$0") || exit 1

source config-dev.inc.sh

# Required packages:
# - nc

ssh_run () {
    CMD="$1"
    echo "Running: ${CMD}"
    echo "$CMD" | ssh "$SSH_USER"@"$SSH_HOST" bash
}

[[ "$INSTALL" ]] && ssh_run "mkdir -p /var/flumen/img"

./copy-to-rpi.sh "${SERVER_SRC}/config-flumen-common.inc.sh" "${SERVER_DIR}/"
./copy-to-rpi.sh "${SERVER_SRC}/config-flumen-server.inc.sh" "${SERVER_DIR}/"
./copy-to-rpi.sh "${SERVER_SRC}/config-flumen-entrance-server.inc.sh" "${SERVER_DIR}/"
./copy-to-rpi.sh "${SERVER_SRC}/flumen-common.inc.sh" "${SERVER_DIR}/"
./copy-to-rpi.sh "${SERVER_SRC}/flumen-server.sh" "${SERVER_DIR}/"
./copy-to-rpi.sh "${SERVER_SRC}/flumen-entrance-server.sh" "${SERVER_DIR}/"
./copy-to-rpi.sh "${SYSTEMD_SRC}/flumen.service" /etc/systemd/system/
./copy-to-rpi.sh "${SYSTEMD_SRC}/flumen-entrance.service" /etc/systemd/system/
./copy-to-rpi.sh "${SYSTEMD_SRC}/shutdown-after-flumen.timer" /etc/systemd/system/
./copy-to-rpi.sh "${SYSTEMD_SRC}/shutdown.service" /etc/systemd/system/
./copy-to-rpi.sh "${TOOLS_SRC}/flumen-log.sh" "${TOOLS_DIR}/"
./copy-to-rpi.sh "${TOOLS_SRC}/entrance-log.sh" "${TOOLS_DIR}/"

if [[ "$INSTALL" ]]; then
    ssh_run "chmod 754 ${SERVER_DIR}/flumen-server.sh"
    ssh_run "chmod 754 ${SERVER_DIR}/flumen-entrance-server.sh"
    ssh_run "chmod 644 /etc/systemd/system/flumen.service"
    ssh_run "chmod 644 /etc/systemd/system/flumen-entrance.service"
    ssh_run "chmod 644 /etc/systemd/system/shutdown.service"
    ssh_run "chmod 644 /etc/systemd/system/shutdown-after-flumen.timer"
    ssh_run "chmod 755 ${TOOLS_DIR}/flumen-log.sh"
    ssh_run "chmod 755 ${TOOLS_DIR}/entrance-log.sh"
    ssh_run "systemctl enable flumen.service"
    ssh_run "systemctl enable flumen-entrance.service"
    ssh_run "systemctl enable shutdown-after-flumen.timer"
else
    ssh_run "systemctl daemon-reload"
    ssh_run "systemctl restart flumen"
fi

echo "Done!"
