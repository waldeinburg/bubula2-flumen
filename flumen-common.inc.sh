#!/usr/bin/env bash

source config-flumen-common.inc.sh

# Values from config-flumen-common.inc.sh:
# - LOG: Do log.
# - MEM_DIR: directory of temporary files (ramdisk)
# - TIMEOUT: Request timeout. The value should probably never be more than the
#   minimum, 1 second, because the server is not even available while another is
#   connected (i.e., the browser will give up immediately, not wait).

# Expected to be set by services:
# Port
PORT=
# Memory size in kilobytes for ramdisk.
# Only necessary if using nc or memory directory for other purposes.
MEM_SIZE_K=
# Unique name (prefix for pipe). Only necessary if using nc.
NAME=
# Name of process_request script. Only necessary if using socat.
PROCESS_REQUEST=

# Set by setup_server.
PIPE=
MEM_DIR=
NC_ERR=

HTTP_STR="HTTP/1.0"
HEADER_OK="$HTTP_STR 200 OK"
HEADER_BAD_REQUEST="$HTTP_STR 400 Bad Request"
HEADER_NOT_FOUND="$HTTP_STR 404 Not Found"
HEADER_TOO_MANY_REQ="$HTTP_STR 429 Too Many Requests"
# Since we use HTTP/1.0 I guess this redirection is actually correct.
HEADER_REDIR="$HTTP_STR 302 Moved Temporarily"
CT="Content-Type"
CT_TEXT="$CT: text/plain"
CT_HTML="$CT: text/html"

# Excpect cd to script directory.
SCRIPT="./$(basename "$0")"
PROC_REQ_ARG="procreq"
NC_CMD_BASE="nc -vlp"

norm () {
    # Replace newlines (tr), normalize space and trim
    # (there will usually be a trailing newline converted to space).
    tr '\n' ' ' | sed -r 's/ +/ /g; s/ $//'
}

HTML_HEADER=$(cat <<EOF | norm
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"/>
    <meta name="author" content="Daniel Lundsgaard Skovenborg"/>
    <link rel="shortcut icon" href="http://bubula2.com/img/favicon.ico"/>
    <title>Bubula² Flumen</title>
    <style>
      body {
        max-width: 800px;
        margin: 10px;
      }
    </style>
</head>
<body>
EOF
)
HTML_FOOTER=$(cat <<EOF | norm
<p><a href="http://bubula2.com/en/flumen/">About Bubula² Flumen.</a></p>
</body>
</html>
EOF
)

# Log each request in one line.
log () {
    [[ "$LOG" ]] && echo -n "${1}; " >&2
}

log_ln () {
    [[ "$LOG" ]] && echo "$1" >&2
}

# Just an alias.
log_result () {
    log_ln "$1"
}


get_field () {
    echo "$1" | cut -f$2
}

get_request_element () {
    echo "$1" | cut -d' ' -f$2
}

# The following uses redirect of stderr to /dev/null and return on error to
# avoid cluttering log with "write error: Broken pipe" when client has
# disconnected before we have finished writing.

set_headers () {
    while [[ $# > 0 ]]; do
        printf "${1}\r\n" || return 1
        shift
    done
}

finish_response () {
    body=$(cat)
    len=$(echo -n "$body" | wc -c)
    set_headers "Content-Length: ${len}" || return
    printf "\r\n" || return
    echo -n "$body"
}

text_response () {
    set_headers "$@" "$CT_TEXT" 2>/dev/null || return
    finish_response 2>/dev/null
}

html_response () {
    set_headers "$@" "$CT_HTML" 2>/dev/null || return
    {
        echo -n "$HTML_HEADER"
        cat | norm
        echo -n "$HTML_FOOTER"
    } | finish_response 2>/dev/null
}


get_ip () {
        # Different versions of nc have different messages for connection.
    grep -i "connect" "$NC_ERR" | sed -r "s/^.+? from [^[]*\[(([0-9]+\.){3}[0-9]+)].*/\1/"
}

wait_for_ip () {
    ip=$(get_ip)
    while [[ -z "$ip" ]]; do
        # Doing a loop with cat and while read turns out to be impossible to
        # break out of for some reason. Sleep a little to ease the CPU usage.
        sleep 0.1
        ip=$(get_ip)
    done

    log "$ip"
    echo "$ip"
}

# Read line from connection; return 0 on timeout.
read_conn_line () {
    # Arg 1: limit to n bytes.
    n=
    [[ "$1" ]] && n="-n $1"

    # Timeout to prevent blocking the server by opening a connection without sending data.
    read ${n} -t "$TIMEOUT" l
    if [[ $? -ne 0 ]]; then
        log_result "TIMEOUT"
        return 1
    fi
    echo "$l"
}

read_headers () {
    h=
    while [[ "$h" != $'\r' ]]; do
        h=$(read_conn_line) || return 1
        echo "$h" | tr -d '\r'
    done
}

# Assumes input from read_headers, i.e. stripped CR.
get_header () {
    headers="$1"
    name="$2"
    l=$(echo "$1" | grep -E "^${name}: ") || return 1
    echo "$l" | sed -r "s/^${name}: (.*)/\1/"
}

# Common handling of IP and request parsing and logging.
# Returns 1 on timeout.
wait_for_request () {
    request=$(read_conn_line) || return 1

    # Empty or malformed requests will just result in empty variables.
    http_method=$(get_request_element "$request" 1)
    http_path=$(get_request_element "$request" 2)

    # Logging $request leads to weird behaviour because of CR.
    log "$http_method $http_path"

    # We might want read some headers here for logging.
    printf '%s\t%s' "$http_method" "$http_path"
}

# Common handling of robots.txt and favicon.ico.
# Returns 0 of request was handled or 1 if not.
handle_robots_and_favicon () {
    # case path
    case "$1" in
    '/favicon.ico')
        echo -n "There's no favicon. This is not an easter egg. Or maybe it is." |
        text_response "$HEADER_NOT_FOUND"
        log_result "FAVICON"
       ;;
    '/robots.txt')
        text_response "$HEADER_OK" <<EOF
User-agent: *
Disallow: /
EOF
        log_result "ROBOTS"
        ;;
    *)  return 1
    esac
}

# Wrapper around process_request to ensure that the connection cannot be hold
# after output has been sent.
process_request_and_end () {
    nc_pid=$(pgrep -f "${NC_CMD_BASE} ${PORT}")
    process_request_nc
    # Give some time to flush the pipe. Also exit if client have closed connection
    # which the browser will do when received data indicated by Content-Length.
    n=0
    while [[ ${n} -lt 10 ]] && kill -0 "$nc_pid" 2>/dev/null; do
        n=$((n + 1))
        sleep 0.1
    done
    # Client may already have closed connection because all data is downloaded.
    # Else, kill to prevent holding the connection, thereby blocking the server.
    kill "$nc_pid" 2>/dev/null
}

set_vars () {
    PIPE="${NAME}_pipe"
    NC_ERR="${MEM_DIR}/nc_err"
}

create_pipe () {
    # Service must register trap to remove.
    rm -f "$PIPE"
    umask 077
    mkfifo "$PIPE"
}

mk_mem_dir_and_trap () {
    mkdir "$MEM_DIR" || exit 2

    trap_base="rm -f '$PIPE'"
    if [[ ${EUID} -eq 0 ]]; then
        # Create ramdisk on MEM_DIR if running as root.
        mount -t ramfs -o size="${MEM_SIZE_K}k" ramfs "$MEM_DIR"
        trap "${trap_base}; umount '$MEM_DIR'; rmdir '$MEM_DIR'" EXIT
    else
        # Else MEM_DIR is a temporary directory.
        trap "${trap_base}; rm -rf '$MEM_DIR'" EXIT
    fi
}

setup_nc_server () {
    set_vars
    mk_mem_dir_and_trap
    create_pipe
}

run_nc_server () {
    # Consider socat instead of nc to get rid of blocking (though it's some of the fun).
    while :; do
        # Netcat command is a variable to be able to find it with pgrep.
        # -v: Then process_request can read IP address from the redirected stderr.
        # The following order of commands avoids "broken pipe" error by cat contrary
        # to the example in the nc man page.
        ${NC_CMD_BASE} ${PORT} <"$PIPE" 2>"$NC_ERR" | process_request_and_end >"$PIPE"
    done
}

run_socat_server () {
    # Not crlf option; we handle CR outself to be compatible with nc.
    # Not -d to avoid "Connection reset by peer" all the time.
    socat -T"$TIMEOUT" TCP-LISTEN:${PORT},reuseaddr,fork SYSTEM:"${SCRIPT} ${PROC_REQ_ARG}"
}
