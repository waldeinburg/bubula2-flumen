#!/usr/bin/env bash

source config-flumen-common.inc.sh

# Override in services
PORT=
PIPE=
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
    echo "$ip"
}

# Common handling of IP and request parsing and logging.
# Returns 1 on timeout.
wait_for_ip_and_request () {
    ip=$(wait_for_ip)

    log "$ip"

    # Timeout to prevent blocking the server by opening a connection without sending data.
    read -t "$TIMEOUT" request
    if [[ $? -ne 0 ]]; then
        log_result "TIMEOUT"
        return 1
    fi

    # Empty or malformed requests will just result in empty variables.
    http_method=$(get_request_element "$request" 1)
    http_path=$(get_request_element "$request" 2)

    # Logging $request leads to weird behaviour because of CR.
    log "$http_method $http_path"

    # We might want read some headers here for logging.
    printf '%s\t%s\t%s' "$ip" "$http_method" "$http_path"
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

create_pipe () {
    # Service must register trap to remove.
    rm -f "$PIPE"
    umask 077
    mkfifo "$PIPE"
}

run_server () {
    create_pipe

    # Consider socat instead of nc to get rid of blocking (though it's some of the fun).
    while :; do
        # Netcat command is a variable to be able to find it with pgrep.
        # -v: Then process_request can read IP address from the redirected stderr.
        # The following order of commands avoids "broken pipe" error by cat contrary
        # to the example in the nc man page.
        ${NC_CMD_BASE} ${PORT} <"$PIPE" 2>"$NC_ERR" | process_request_and_end >"$PIPE"
    done
}
