#!/usr/bin/env bash

# Must be the first statement to avoid absolute path to config file.
cd $(dirname "$0") || exit 1

source flumen-common.inc.sh
source config-flumen-entrance-server.inc.sh

PROCESS_REQUEST="./flumen-entrance-server-req-proc.sh"

# Setup

if ! pgrep -f 'flumen-server\.sh' >/dev/null; then
    echo "flumen-server.sh must be running!" >&2
    exit 1
fi

# We want the bots to ruin a little as possible.
# Use socat here but keep that nc hack in the main server.
run_socat_server
