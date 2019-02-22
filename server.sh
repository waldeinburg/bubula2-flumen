#!/usr/bin/env bash

DEBUG=1
PORT=8080
PIPE="server_pipe"
MEM_DIR="mem"
IP_DIR="${MEM_DIR}/ip"
NC_ERR="${MEM_DIR}/nc_err"
WAIT_SECS=10

HTTP_STR="HTTP/1.0"
HEADER_OK="$HTTP_STR 200 OK"
HEADER_BAD_REQUEST="$HTTP_STR 400 BAD REQUEST"
HEADER_NOT_FOUND="$HTTP_STR 404 NOT FOUND"
CT="Content-Type"
CT_TEXT="$CT: text/plain"
CT_HTML="$CT: text/html"
HTML_HEADER=$(cat <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<meta name="author" content="Daniel Lundsgaard Skovenborg"/>
<link rel="shortcut icon" href="http://bubula2.com/img/favicon.ico"/>
<title>Bubula² Flow</title>
</head>
<body>
EOF
)
HTML_FOOTER=$(cat <<EOF
</body>
</html>
EOF
)

get_request_element () {
    echo "$1" | cut -d' ' -f$2
}

set_headers () {
    while [[ $# > 0 ]]; do
        printf "${1}\r\n"
        shift
    done
    printf "\r\n"
}

nn () {
    tr '\n' ' '
}

html_body () {
    echo "$HTML_HEADER" | nn
    cat | nn
    echo "$HTML_FOOTER" | nn
}

process_request () {
    read request
    if [[ -z "$request" ]]; then
        set_headers "$HEADER_BAD_REQUEST"
        return
    fi
    [[ "$DEBUG" ]] && echo "$request" >&2

    ip=$(grep "^Connection" "$NC_ERR" | sed -r "s/^Connection from \[(([0-9]+\.){3}[0-9]+)].*/ip=\1/")
    ip_file="${IP_DIR}/${ip}"
    new_ip=$([[ -f "$ip_file" ]] || echo 1)
    must_wait=
    if [[ ${new_ip} ]]; then
        touch "$ip_file"
    else
        ip_time=$(stat -c %Y "$ip_file")
        cur_time=$(date +%s)
        elapsed=$(( ${cur_time} - ${ip_time} ))
        if [[ ${elapsed} -lt ${WAIT_SECS} ]]; then
            must_wait=1
        else
            # Waiting time is over. Update time.
            touch "$ip_file"
        fi
    fi

    http_method=$(get_request_element "$request" 1)
    http_path=$(get_request_element "$request" 2)

    [[ "$http_method" = 'GET' ]] || return

    case "$http_path" in
    '/favicon.ico')
        set_headers "$HEADER_NOT_FOUND" "$CT_TEXT"
        echo "There's no favicon. This is not an easter egg. Or maybe it is."
       ;;
    '/robots.txt')
        set_headers "$HEADER_OK" "$CT_TEXT"
        cat <<EOF
User-agent: *
Disallow: /
EOF
        ;;
    *)
        set_headers "$HEADER_OK" "$CT_HTML"
        html_body <<EOF
<h1>Hello World</h1>
Hello $([[ ${new_ip} ]] && echo there || echo again).
$([[ ${must_wait} ]] && echo "Please wait!")
EOF
        ;;
    esac
}

cd $(dirname "$0") || exit 1

rm -rf "$PIPE" "$MEM_DIR"
trap "rm -rf '$PIPE' '$MEM_DIR'" EXIT

mkdir "$MEM_DIR" "$IP_DIR" || exit 2
touch "$NC_ERR"

umask 077
mkfifo "$PIPE"

# TODO: create ramfs on MEM_DIR

# Consider socat instead of nc to get rid of blocking.
while :; do
    cat "$PIPE" | process_request | nc -vlp "$PORT" 2> "$NC_ERR" > "$PIPE"
done
