#!/usr/bin/env bash

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

./copy-to-rpi.sh config-flumen-server.inc.sh "${SERVER_DIR}/"
./copy-to-rpi.sh flumen-server.sh "${SERVER_DIR}/"
./copy-to-rpi.sh flumen.service /etc/systemd/system/
./copy-to-rpi.sh shutdown-after-flumen.timer /etc/systemd/system/
./copy-to-rpi.sh shutdown.service /etc/systemd/system/
./copy-to-rpi.sh flumen-log.sh "${TOOLS_DIR}/"

if [[ "$INSTALL" ]]; then
    ssh_run "chmod 754 ${SERVER_DIR}/flumen-server.sh"
    ssh_run "chmod 644 /etc/systemd/system/flumen.service"
    ssh_run "chmod 644 /etc/systemd/system/shutdown.service"
    ssh_run "chmod 644 /etc/systemd/system/shutdown-after-flumen.timer"
    ssh_run "chmod 755 ${TOOLS_DIR}/flumen-log.sh"
    ssh_run "systemctl enable flumen.service"
    ssh_run "systemctl enable shutdown-after-flumen.timer"
else
    ssh_run "systemctl daemon-reload"
    ssh_run "systemctl restart flumen"
fi

echo "Done!"
