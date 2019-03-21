#!/usr/bin/env bash

SERVER_DIR="/var/flumen"
TOOLS_DIR="/root"

INSTALL=

[[ "$1" = "INSTALL" ]] && INSTALL=1

cd $(dirname "$0") || exit 1

source config-dev.inc.sh

# Required packages:
# - nc
# - dbus
# Required setup:
# $ systemctl unmask systemd-logind

ssh_cmd () {
    CMD="$1"
    echo "Running: ${CMD}"
    ssh "$SSH_USER"@"$SSH_HOST" "$1"
}

[[ "$INSTALL" ]] && ssh_cmd "mkdir -p /var/flumen/img"

./copy-to-rpi.sh flumen-server.sh "${SERVER_DIR}/"
./copy-to-rpi.sh flumen.service /etc/systemd/system/
./copy-to-rpi.sh shutdown-after-flumen.service /etc/systemd/system/
./copy-to-rpi.sh flumen-log.sh "${TOOLS_DIR}/"

if [[ "$INSTALL" ]]; then
    ssh_cmd "chmod 754 ${SERVER_DIR}/flumen-server.sh"
    ssh_cmd "chmod 644 /etc/systemd/system/flumen.service"
    ssh_cmd "chmod 644 /etc/systemd/system/shutdown-after-flumen.service"
    ssh_cmd "chmod 755 ${TOOLS_DIR}/flumen-log.sh"
    ssh_cmd "systemctl enable flumen.service"
    ssh_cmd "systemctl enable shutdown-after-flumen.service"
else
    ssh_cmd "systemctl daemon-reload"
    ssh_cmd "systemctl restart flumen"
fi

echo "Done!"
