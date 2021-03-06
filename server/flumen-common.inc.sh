#!/usr/bin/env bash

source config-flumen-common.inc.sh

# Values from config-flumen-common.inc.sh:
# - LOG: Do log.
# - MEM_DIR: directory of temporary files (ramdisk)
# - TIMEOUT: Request timeout. The value should probably never be more than the
#   minimum, 1 second, because the server is not even available while another is
#   connected (i.e., the browser will give up immediately, not wait).

# Expected to be set by services:
# NC or SOCAT
MODE=
# Port
PORT=
# Memory size in kilobytes for ramdisk.
# Only necessary if using nc or memory directory for other purposes.
MEM_SIZE_K=
# Unique name (prefix for pipe). Only necessary if using nc.
NAME=
# Optional: Extra content in HTML head.
HEAD=

# Set by setup.
PIPE=
# MEM_DIR will not be overriden if set.
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

# Will be set by setup
HTML_HEADER=
HTML_FOOTER=

PROC_REQ=
[[ "$1" = "$PROC_REQ_ARG" ]] && PROC_REQ=1

norm () {
    # Replace newlines (tr), normalize space and trim
    # (there will usually be a trailing newline converted to space).
    tr '\n' ' ' | sed -r 's/ +/ /g; s/ $//'
}

html_header () {
    cat <<EOF | norm
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
    ${HEAD}
</head>
<body>
EOF
}

html_footer () {
    cat <<EOF | norm
<p><a href="http://bubula2.com/en/flumen/">About Bubula² Flumen.</a></p>
</body>
</html>
EOF
}

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
    if [[ "$MODE" = NC ]]; then
        # Different versions of nc have different messages for connection.
        grep -i "connect" "$NC_ERR" | sed -r "s/^.+? from [^[]*\[(([0-9]+\.){3}[0-9]+)].*/\1/"
    else
        echo "$SOCAT_PEERADDR"
    fi
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
process_request_and_kill_nc () {
    nc_pid=$(pgrep -f "${NC_CMD_BASE} ${PORT}")
    process_request
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
    [[ -z "$MEM_DIR" ]] && MEM_DIR="${NAME}_mem"
}

create_pipe () {
    # Service must register trap to remove.
    rm -f "$PIPE"
    umask 077
    mkfifo "$PIPE" || exit 2
}

mk_mem_dir_and_trap () {
    # Make sure it works even after a dirty shutdown or other error.
    rm -rf "$MEM_DIR"
    mkdir "$MEM_DIR" || exit 2

    trap_base=:
    [[ "$MODE" = NC ]] && trap_base="rm -f '$PIPE'"

    if [[ ${EUID} -eq 0 ]]; then
        # Create ramdisk on MEM_DIR if running as root.
        mount -t ramfs -o size="${MEM_SIZE_K}k" ramfs "$MEM_DIR"
        trap "${trap_base}; umount '$MEM_DIR'; rmdir '$MEM_DIR'" EXIT
    else
        # Else MEM_DIR is a temporary directory.
        trap "${trap_base}; rm -rf '$MEM_DIR'" EXIT
    fi
}

base-setup () {
    # With nc this will make the header/footer generated only once.
    HTML_HEADER=$(html_header)
    HTML_FOOTER=$(html_footer)

    # No further setup if processing a request for socat.
    [[ "$PROC_REQ" ]] && return

    # Set arg 1 make mem_dir even for
    use_mem_dir="$1"
    if [[ "$MODE" = NC ]]; then
        set_vars
        mk_mem_dir_and_trap
        create_pipe
    elif [[ "$use_mem_dir" ]]; then
        mk_mem_dir_and_trap
    fi
}

run_nc_server () {
    while :; do
        # Netcat command is a variable to be able to find it with pgrep.
        # -v: Then process_request can read IP address from the redirected stderr.
        # The following order of commands avoids "broken pipe" error by cat contrary
        # to the example in the nc man page.
        ${NC_CMD_BASE} ${PORT} <"$PIPE" 2>"$NC_ERR" | process_request_and_kill_nc >"$PIPE"
    done
}

run_socat_server () {
    # Not crlf option; we handle CR outself to be compatible with nc.
    # Not -d to avoid "Connection reset by peer" all the time.
    # The timeout needs to be much higher because the entrance server makes a service call to reCAPTCHA.
    # The other timeout still applies to reading, though.
    socat -T"$SOCAT_TIMEOUT" TCP-LISTEN:${PORT},reuseaddr,fork SYSTEM:"${SCRIPT} ${PROC_REQ_ARG}"
}

gogogo () {
    # If the process request argument was given to the script is called because
    # of a connection to socat.
    if [[ "$PROC_REQ" ]]; then
        process_request
        return
    fi

    # Run server.
    case "$MODE" in
    NC      ) run_nc_server ;;
    SOCAT   ) run_socat_server ;;
    *       ) echo "Invalid mode: '${MODE}'"; exit 3 ;;
    esac
}
