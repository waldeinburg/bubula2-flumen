#!/usr/bin/env bash
# Copy via SSH when scp is missing.
source config-copy-to-pi.inc.sh
echo "echo $(base64 -w0 "$1") | base64 -d > '$2'" | ssh "$SSH_USER"@"$SSH_HOST" bash

