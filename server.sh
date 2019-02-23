#!/usr/bin/env bash

DEBUG=1
PORT=8080
PIPE="server_pipe"
IMAGES_DIR="img"
MEM_DIR="mem"
IP_DIR="${MEM_DIR}/ip"
NC_ERR="${MEM_DIR}/nc_err"
COUNTER="${MEM_DIR}/counter"
WAIT_SECS=8

HTTP_STR="HTTP/1.0"
HEADER_OK="$HTTP_STR 200 OK"
HEADER_BAD_REQUEST="$HTTP_STR 400 Bad Request"
HEADER_NOT_FOUND="$HTTP_STR 404 Not Found"
HEADER_TOO_MANY_REQ="$HTTP_STR 429 Too Many Requests"
CT="Content-Type"
CT_TEXT="$CT: text/plain"
CT_HTML="$CT: text/html"

norm () {
    tr '\n' ' ' | sed 's/ +/ /g'
}

HTML_HEADER=$(cat <<EOF | norm
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
HTML_FOOTER=$(cat <<EOF | norm
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

html_body () {
    echo "$HTML_HEADER"
    cat | norm
    echo "$HTML_FOOTER"
}

process_request () {
    read request
    if [[ -z "$request" ]]; then
        set_headers "$HEADER_BAD_REQUEST"
        return
    fi
    [[ "$DEBUG" ]] && echo "$request" >&2

    http_method=$(get_request_element "$request" 1)

    [[ "$http_method" = 'GET' ]] || return

    http_path=$(get_request_element "$request" 2)

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
    *)  # Any request
        n=$(cat "$COUNTER")
        if [[ ${n} -gt ${IMAGES_COUNT} ]]; then
            set_headers "$HEADER_OK" "$CT_HTML"
            html_body <<EOF
<h1>Sorry, show's over!</h1>
<p>Please try again next week!</p>
EOF
            return
        fi

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

        if [[ ${must_wait} ]]; then
            set_headers "$HEADER_TOO_MANY_REQ" "$CT_HTML"
            html_body <<-EOF
<h1>Sorry, you need to wait bit</h1>
<p>
If you see this message unexpectedly there's someone else on your network
having the same obscure interests as you. You should drink a cup of coffee
together!
</p>
EOF
            return
        fi

        IMG=$(echo "$IMAGES" | sed -n "${n}{p;q}")
        IMG_DATA=$(base64 -w0 "$IMG")
        set_headers "$HEADER_OK" "$CT_HTML"
        html_body <<EOF
<p><img alt="image" src="data:image/png;base64,${IMG_DATA}"/>
<p>${n} of ${IMAGES_COUNT}</p>
EOF
        # Increment counter.
        echo -n $(( ${n} + 1 )) > "$COUNTER"
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

IMAGES=$(find "$IMAGES_DIR" -name "*.png")
IMAGES_COUNT=$(echo "$IMAGES" | wc -l)
echo -n 1 > "$COUNTER"

# TODO: create ramfs on MEM_DIR

# Consider socat instead of nc to get rid of blocking.
while :; do
    cat "$PIPE" | process_request | nc -vlp "$PORT" 2> "$NC_ERR" > "$PIPE"
done
