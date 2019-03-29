#!/usr/bin/env bash

source config-flumen-entrance-server.inc.sh
source flumen-common.inc.sh

# Values from config-flumen-common.inc.sh: Cf. flumen-server.sh
# Values from config-flumen-entrance-server.inc.sh
# - PORT: Port
# - MAIN_PORT_EXTERN: External port of main server.
# - RECAPTCHA_SITE_KEY: Site key for reCAPTCHA.
# - RECAPTCHA_SECRET_KEY: Server side secret key for reCAPTCHA.
# - DEV_RECAPTCHA_SITE_KEY: For localhost.
# - DEV_RECAPTCHA_SECRET_KEY: For localhost.

# Values unlikely to change:
PIPE="entrance_server_pipe"
BASE_DIR="${MEM_DIR}/entrance-server"
NC_ERR="${BASE_DIR}/nc_err"

# May be overridden by dev:
MAIN_HOST="flumen.bubula2.com:${MAIN_PORT_EXTERN}"
SITE_KEY="$RECAPTCHA_SITE_KEY"
SECRET_KEY="$RECAPCHA_SECRET_KEY"

# Setup for common functions:
PORT="$ENTRANCE_PORT"

# Will be set up
MAIN_URL=

curl_google_verify () {
    curl -sd "secret=${SECRET_KEY}&response=${1}&remoteip=${2}" https://www.google.com/recaptcha/api/siteverify
}

is_really_not_a_robot () {
    response=$(curl_google_verify "$1" "$2") # token and ip
    echo "$response" | grep -q '"success": *true' || return 1
}

process_request () {
    ip_and_request=$(wait_for_ip_and_request) || return
    http_method=$(get_field "$ip_and_request" 2)

    if [[ "$http_method" = "GET" ]]; then
        http_path=$(get_field "$ip_and_request" 3)
        handle_robots_and_favicon "$http_path" && return

        html_response "$HEADER_OK" <<EOF
<script src="https://www.google.com/recaptcha/api.js" async defer></script>
<h1>Welcome to Bubula² Flumen</h1>
<p>Access is free for carbon based life forms. Please verify that you are so.</p>
<form action="/" method="POST">
  <div class="g-recaptcha" data-sitekey="${SITE_KEY}"></div>
  <input type="submit" value="Submit">
</form>
EOF
        log_result "PAGE"
    fi

    if [[ "$http_method" != "POST" ]]; then
        text_response "$HEADER_BAD_REQUEST" <<EOF
Bad baad request!
EOF
        log_result "NOOP"
        return
    fi

    headers=$(read_headers) || return
    len=$(get_header "$headers" "Content-Length")
    if ! echo "$len" | grep -qE '^[0-9]+$'; then
        text_response "$HEADER_BAD_REQUEST" <<EOF
Bad Content-Length header: ${len}
EOF
        log_result "BAD_CL"
        return
    fi

    data=$(read_conn_line "$len") || return
    if ! echo "$data" | grep -q "^g-recaptcha-response="; then
        text_response "$HEADER_BAD_REQUEST" <<EOF
Bad data: ${data}
EOF
        log_result "BAD_DATA"
        return
    fi

    ip=$(get_field "$ip_and_request" 1)
    token=$(echo "$data" | sed -r 's/^g-recaptcha-response=(.*)/\1/')

    if is_really_not_a_robot "$token" "$ip"; then
        text_response "$HEADER_REDIR" "Location: ${MAIN_URL}" <<EOF
        Welcome, earthling!
EOF
        log_result "REDIR"
    else
        text_response "$HEADER_BAD_REQUEST" <<EOF
Red Robot World Domination
EOF
        log_result "BAD_ROBOT"
    fi
}


# Setup

if ! pgrep -f 'flumen-server\.sh' >/dev/null; then
    echo "flumen-server.sh must be running!" >&2
    exit 1
fi

mkdir "$BASE_DIR" || exit 2
trap "rm -rf '$PIPE' '$BASE_DIR'" EXIT

if [[ "$DEV" ]]; then
    MAIN_HOST="localhost:${MAIN_PORT}"
    SITE_KEY="$DEV_RECAPTCHA_SITE_KEY"
    SECRET_KEY="$DEV_RECAPTCHA_SECRET_KEY"
fi

# Wait for main server to create secret path.
while [[ ! -f "$SECRET_PATH_FILE" ]]; do :; done

secret_path=$(cat "$SECRET_PATH_FILE")
MAIN_URL="http://${MAIN_HOST}${secret_path}"

run_server
