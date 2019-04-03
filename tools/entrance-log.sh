#!/usr/bin/env bash
# Or -u to get everything related to the service.
journalctl _SYSTEMD_UNIT=flumen-entrance.service "$@"
