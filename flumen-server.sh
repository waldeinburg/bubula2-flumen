#!/usr/bin/env bash

# Must be the first statement to avoid absolute path to config file.
cd $(dirname "$0") || exit 1

source flumen-common.inc.sh
source config-flumen-server.inc.sh

# Values from config-flumen-common.inc.sh
# - MAIN_PORT: Port (must also be known by flumen-entrance-server.sh)

# Values from config-flumen-server.inc.sh:
# - TREAT_SELF: Allow my own IP to view the site without advancing the counter.
# Hard code IP instead of using "host flumen.bubula2.com" (assumes that the site
# is running under my couch) to avoid installing "host" on the small Raspberry Pi.
# - SELF_IP: My IP.
# - WAIT_SECS: Number of seconds the user must wait before being allowed to view a new image.
# Limits for preventing users from hitting reload violently to get the next image:
# - REQ_LIMIT: Max reloads that are rejected within one image.
# - MAX_WARNS: Max warnings before the user is banned.

# Values unlikely to change:
IMAGES_DIR="img"
MEM_FS_EXTRA_K=10
MEM_DIR="$MAIN_MEM_DIR"
MEM_IMG_DATA_DIR="${MEM_DIR}/img_data"
IP_DIR="${MEM_DIR}/ip"
COUNTER="${MEM_DIR}/counter"

# May be overriden by dev.
ENTRANCE_URL="http://flumen.bubula2.com"

# Setup for common functions:
NAME="flumen"
PORT="$MAIN_PORT"

# Will be set up
SECRET_PATH=

img_order () {
    # Alternative: sort
    shuf
}

process_request () {
    ip_and_request=$(wait_for_ip_and_request) || return
    http_method=$(get_field "$ip_and_request" 2)

    if [[ "$http_method" != "GET" ]]; then
        text_response "$HEADER_BAD_REQUEST" <<EOF
Bad baad request!
EOF
        log_result "NOOP"
        return
    fi

    http_path=$(get_field "$ip_and_request" 3)

    handle_robots_and_favicon "$http_path" && return

    if [[ "$http_path" != "$SECRET_PATH" ]]; then
        html_response "$HEADER_NOT_FOUND" <<EOF
<h1>You are not supposed to be here!</h1>
<p>Please go to <a href="${ENTRANCE_URL}">the entrance</a> to enter.</p>
EOF
        log_result "NOT_FOUND"
        return
    fi

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

    wait_msg="You may <a href=\"javascript:location.reload(true)\">reload</a>\
              the page to see another image in ${wait_time} seconds from now."

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
}


# Setup

img_mem_size=$(du "$IMAGES_DIR" -k -d0 | cut -f1)
# Size increase for base64 is ceil(n / 3) * 4.
MEM_SIZE_K=$(( (img_mem_size / 3 + 1) * 4 + MEM_FS_EXTRA_K ))

setup_server

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

# Generate secret path
token=$(head -c32 /dev/urandom | base64)
SECRET_PATH="/${token}"
echo -n "$SECRET_PATH" > "$SECRET_PATH_FILE"

if [[ "$DEV" ]]; then
    ENTRANCE_URL="http://localhost:${MAIN_PORT}"
fi

run_server
