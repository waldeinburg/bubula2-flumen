#!/usr/bin/env bash

DEBUG=1
PORT=8080
PIPE=server_pipe

get_request_element () {
    echo "$1" | cut -d' ' -f$2
}

process_request () {
    read REQUEST
    if [ -z "$REQUEST" ]; then
        echo "ERROR BADDATA"
        return
    fi
    [ $DEBUG ] && echo $REQUEST >&2

    HTTP_METHOD=$(get_request_element "$REQUEST" 1)
    HTTP_PATH=$(get_request_element "$REQUEST" 2)

    [ "$HTTP_METHOD" = 'GET' ] || return 

    if [ "$HTTP_PATH" = '/favicon.ico' ]; then
        cat <<EOF
HTTP/1.1 404 NOT FOUND
Content-Type: text/plain

There's no favicon. This is not an easter egg. Or maybe it is.
EOF
        return
    fi
    
    cat <<EOF
HTTP/1.1 200 OK

Hello world
EOF
}


umask 077 
trap "rm -f $PIPE" EXIT
mkfifo $PIPE

# Consider socat instead of nc to get rid of blocking.
while :; do
    cat $PIPE | process_request | nc -vl $PORT > $PIPE
done

