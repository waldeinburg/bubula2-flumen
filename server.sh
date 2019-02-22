#!/usr/bin/env bash

DEBUG=1
PORT=8080
PIPE=server_pipe

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

# Echo without newlines

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
Lorem ipsum
EOF
        ;;
    esac
}


rm -f "$PIPE"
umask 077
trap "rm -f '$PIPE'" EXIT
mkfifo "$PIPE"

# Consider socat instead of nc to get rid of blocking.
while :; do
    cat "$PIPE" | process_request | nc -vl "$PORT" > "$PIPE"
done

