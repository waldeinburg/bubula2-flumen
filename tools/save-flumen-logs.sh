#!/usr/bin/env bash
DATE_STR=$(date +%Y-%m-%d)
DIR="/var/log/flumen"
FILE_MAIN="${DIR}/flumen-main-${DATE_STR}.log"
FILE_ENTRANCE="${DIR}/flumen-entrance-${DATE_STR}.log"

mkdir -p "$DIR"

journalctl _SYSTEMD_UNIT=flumen.service > "$FILE_MAIN"
journalctl _SYSTEMD_UNIT=flumen-entrance.service > "$FILE_ENTRANCE"
