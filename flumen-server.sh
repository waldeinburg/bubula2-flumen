#!/usr/bin/env bash

# Must be the first statement to avoid absolute path to config file.
cd $(dirname "$0") || exit 1

source config-flumen-server.inc.sh

# Values from config file:
# - LOG: Do log.
# - TREAT_SELF: Allow my own IP to view the site without advancing the counter.
# Hard code IP instead of using "host flumen.bubula2.com" (assumes that the site
# is running under my couch) to avoid installing "host" on the small Raspberry Pi.
# - SELF_IP: My IP.
# - PORT: Port.
# - TIMEOUT: Request timeout. The value should probably never be more than the
#   minimum, 1 second, because the server is not even available while another is
#   connected (i.e., the browser will give up immediately, not wait).
# - WAIT_SECS: Number of seconds the user must wait before being allowed to view a new image.
# Limits for preventing users from hitting reload violently to get the next image:
# - REQ_LIMIT: Max reloads that are rejected within one image.
# - MAX_WARNS: Max warnings before the user is banned.

# Values unlikely to change:
PIPE="server_pipe"
IMAGES_DIR="img"
MEM_DIR="mem"
MEM_FS_EXTRA_K=10
MEM_IMG_DATA_DIR="${MEM_DIR}/img_data"
IP_DIR="${MEM_DIR}/ip"
NC_ERR="${MEM_DIR}/nc_err"
COUNTER="${MEM_DIR}/counter"

HTTP_STR="HTTP/1.0"
HEADER_OK="$HTTP_STR 200 OK"
HEADER_BAD_REQUEST="$HTTP_STR 400 Bad Request"
HEADER_NOT_FOUND="$HTTP_STR 404 Not Found"
HEADER_TOO_MANY_REQ="$HTTP_STR 429 Too Many Requests"
CT="Content-Type"
CT_TEXT="$CT: text/plain"
CT_HTML="$CT: text/html"

NC_CMD="nc -vlp $PORT"

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
        padding: 10px;
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

img_order () {
    # Alternative: sort
    shuf
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

process_request () {
    ip=
    while [[ -z "$ip" ]]; do
        # Different versions of nc have different messages for connection.
        ip=$(grep -i "connect" "$NC_ERR" | sed -r "s/^.+? from [^[]*\[(([0-9]+\.){3}[0-9]+)].*/\1/")
        # Doing a loop with cat and while read turns out to be impossible to
        # break out of for some reason. Sleep a little to ease the CPU usage.
        sleep 0.1
    done

    log "$ip"

    # Timeout to prevent blocking the server by opening a connection without sending data.
    read -t "$TIMEOUT" request
    if [[ $? -ne 0 ]]; then
        log_result "TIMEOUT"
        return
    fi

    # Empty or malformed requests will just result in empty variables.
    http_method=$(get_request_element "$request" 1)
    http_path=$(get_request_element "$request" 2)

    # Logging $request leads to weird behaviour because of CR.
    log "$http_method $http_path"

    # We might want read some headers here for logging.

    if [[ "$http_method" != "GET" ]]; then
        text_response "$HEADER_BAD_REQUEST"
        log_result "NOOP"
        return
    fi

    case "$http_path" in
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
    *)  # Any request
        n=$(cat "$COUNTER")
        if [[ ${n} -gt ${IMAGES_COUNT} ]]; then
            html_response "$HEADER_OK" <<EOF
<h1>Sorry, show's over!</h1>
<p>Please try again next week!</p>
EOF
            log_result "END_OF_SHOW"
            return
        fi

        ip_file="${IP_DIR}/${ip}"
        ip_count_file="${ip_file}_count"
        ip_warn_file="${ip_file}_warn"
        ip_ban_file="${ip_file}_ban"
        new_ip=$([[ -f "$ip_file" ]] || echo 1)
        must_wait=
        wait_time=${WAIT_SECS}
        overrule_rules=$([[ "$TREAT_SELF" && "$ip" = "$SELF_IP" ]] && echo y)

        if [[ ${new_ip} ]]; then
            touch "$ip_file"
            echo -n 0 > "$ip_count_file"
        else
            if [[ -f "$ip_ban_file" ]]; then
                html_response "$HEADER_TOO_MANY_REQ" <<EOF
<h1>I said, You are banned from this session!</h1>
<p>You really must try again next week and take it easy then.</p>
<p>But I mean it: If you were banned because multiple persons were accessing the site from the same network,
consider making Bubula² Flumen a social event around the same machine!</p>
EOF
                log_result "BAN_REPEAT"
                return
            fi

            ip_time=$(stat -c %Y "$ip_file")
            cur_time=$(date +%s)
            elapsed=$((cur_time - ip_time))
            if [[ ${elapsed} -lt ${WAIT_SECS} ]]; then
                count_val=$(cat "$ip_count_file")
                echo -n $((count_val + 1)) > "$ip_count_file"
                if [[ "$count_val" -gt "$REQ_LIMIT" ]]; then
                    if [[ ! -f "$ip_warn_file" ]]; then
                        html_response "$HEADER_TOO_MANY_REQ" <<EOF
<h1>Hey, take it easy!</h1>
<p><em>This is a warning!</em>
If you keep reloading the page like that, I will ban you for this session.</p>
EOF
                        echo -n 1 > "$ip_warn_file"
                        log_result "WARN 1"
                        return
                    else
                        warn_count_val=$(cat "$ip_warn_file")
                        echo -n $((warn_count_val + 1)) > "$ip_warn_file"
                        if [[ ! "$warn_count_val" -gt "$MAX_WARNS" ]]; then
                            html_response "$HEADER_TOO_MANY_REQ" <<EOF
<h1>I've already warned you!</h1>
<p><em>This is another warning!</em>
If you keep reloading the page like that, I will ban you for this session of Bubula² Flumen.</p>
EOF
                            log_result "WARN ${warn_count_val}"
                            return
                        else
                            html_response "$HEADER_TOO_MANY_REQ" <<EOF
<h1>You are banned from this session!</h1>
<p>Try again next week and take it easy then.</p>
<p>If you were banned because multiple persons were accessing the site from the same network,
consider making Bubula² Flumen a social event around the same machine!</p>
EOF
                            touch "$ip_ban_file"
                            log_result "BAN"
                            return
                        fi
                    fi
                fi

                must_wait=1
                wait_time=$((WAIT_SECS - elapsed))
            else
                # Waiting time is over. Update time.
                touch "$ip_file"
                echo -n 0 > "$ip_count_file"
            fi
        fi

        wait_msg="You may reload the page to see another image in ${wait_time} seconds from now."

        if [[ ${must_wait} && ! "$overrule_rules" ]]; then
            html_response "$HEADER_TOO_MANY_REQ" <<EOF
<h1>Sorry, you need to wait a bin</h1>
<p>${wait_msg}</p>
<blockquote>
<p>Bin (s): Unit of measurement. The shortest period of time you may use
staring contemplatively in front of every painting in a museum to ensure
that everyone else won't think that you are a complete moron.<br/>
1 bin = 8.5 seconds</p>
<p>(Anders Lund Madsen, "Madsens ÆØÅ", my translation.)
</blockquote>
<p>
If you see this message unexpectedly there's someone else on your network
having the same obscure interests as you. You should drink a cup of coffee
together!
</p>
EOF
            log_result "WAIT"
            return
        fi

        IMG_DATA=$(cat "${MEM_IMG_DATA_DIR}/${n}")

        html_response "$HEADER_OK" <<EOF
<p><img alt="image" src="data:image/png;base64,${IMG_DATA}"/>
<p>${n} of ${IMAGES_COUNT}</p>
<p>${wait_msg}</p>
<p><a href="http://bubula2.com">Copyright © 2012-$(date +%Y) Daniel Lundsgaard Skovenborg (Waldeinburg).</a></p>
EOF

        log_result "SHOW ${n}"

        # Increment counter.
        if [[ ! "$overrule_rules" ]]; then
            echo -n $((n + 1)) > "$COUNTER"
        fi
        ;;
    esac
}

# Wrapper around process_request to ensure that the connection cannot be hold
# after output has been sent.
process_request_and_end () {
    nc_pid=$(pgrep -f "$NC_CMD")
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


# Setup

rm -rf "$PIPE" "$MEM_DIR"

mkdir "$MEM_DIR" || exit 2

if [[ ${EUID} -eq 0 ]]; then
    # Create ramdisk on MEM_DIR if running as root.
    img_mem_size=$(du "$IMAGES_DIR" -k -d0 | cut -f1)
    # Size increase for base64 is ceil(n / 3) * 4.
    mem_size=$(( (img_mem_size / 3 + 1) * 4 + MEM_FS_EXTRA_K ))
    mount -t ramfs -o size="${mem_size}k" ramfs "$MEM_DIR"
    trap "rm -f '$PIPE'; umount '$MEM_DIR'; rmdir '$MEM_DIR'" EXIT
else
    # Else MEM_DIR is a temporary directory.
    trap "rm -rf '$PIPE' '$MEM_DIR'" EXIT
fi

mkdir "$IP_DIR" || exit 2
echo -n 1 > "$COUNTER"

# "Preload" images by storing image base64 data on ramdisk.
# This way we won't read from the SD while running.
mkdir "$MEM_IMG_DATA_DIR" || exit 2
n=0
find "$IMAGES_DIR" -name "*.png" | img_order | while read f; do
    n=$((n + 1))
    base64 -w0 "$f" > "${MEM_IMG_DATA_DIR}/${n}"
done
IMAGES_COUNT=$(find "$MEM_IMG_DATA_DIR" -type f | wc -l)

umask 077
mkfifo "$PIPE"


# Consider socat instead of nc to get rid of blocking (though it's some of the fun).
while :; do
    # Netcat command is a variable to be able to find it with pgrep.
    # -v: Then process_request can read IP address from the redirected stderr.
    # The following order of commands avoids "broken pipe" error by cat contrary
    # to the example in the nc man page.
    ${NC_CMD} <"$PIPE" 2>"$NC_ERR" | process_request_and_end >"$PIPE"
done
