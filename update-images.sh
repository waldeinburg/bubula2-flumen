#!/usr/bin/env bash
# Take an image in org_img, resize, and put in img.

SIZE=800
ORG_IMG_DIR="org_img"
IMG_DIR="server/img"
SERVER_IMG_DIR="/var/flumen/img"

cd $(dirname "$0") || exit 1

source config-dev.inc.sh

MOUNTED=
if [[ -d "${SD_MEDIA_PATH}${SERVER_IMG_DIR}" ]]; then
    MOUNTED=1
    SERVER_IMG_DIR="${SD_MEDIA_PATH}${SERVER_IMG_DIR}"
fi


run-cmd () {
    if [[ "$MOUNTED" ]]; then
        eval "sudo $1"
    else
        echo "$1" | ssh "$SSH_USER"@"$SSH_HOST" bash
    fi
}

copy-file () {
    if [[ "$MOUNTED" ]]; then
        sudo cp "$@"
    else
        ./copy-to-rpi.sh "$@"
    fi
}

img-web-path () {
    echo "${IMG_DIR}/$(basename "$1" ".png")-web.png"
}

create-resized-img () {
    SRC="$1"
    DEST=$(img-web-path "$SRC")
    convert "$SRC" -resize "${SIZE}x${SIZE}" "$DEST"
}


if [[ ! -d "$ORG_IMG_DIR" || ! -d "$IMG_DIR" ]]; then
    echo "Directories ${ORG_IMG_DIR} and ${IMG_DIR} must exist!" >&2
    exit 2
fi

echo "Deleting all removed images from generated image directory ..."
find "$IMG_DIR" -name "*.png" | while read f; do
    name=$(basename "$f" "-web.png")
    if [[ ! -f "${ORG_IMG_DIR}/${name}.png" ]]; then
        echo "Deleting ${name} from generated image directory ..."
        rm "$f"
    fi
done


echo "Creating all non-existing resized images ..."
find "$ORG_IMG_DIR" -name "*.png" | while read f; do
    dest=$(img-web-path "$f")
    if [[ ! -f "$dest" ]]; then
        echo "Resizing ${f}, creating ${dest} ..."
        create-resized-img "$f"
    fi
done


echo "Copying all non-existing images to server ..."
# Don't run ssh-session for each file to check if it exists.
existing=$(run-cmd "find ${SERVER_IMG_DIR} -name '*.png'")


find "$IMG_DIR" -name "*.png" | while read f; do
    name=$(basename "$f")
    name_re=$(echo "$name" | sed -r 's/\./\\./g')
    if ! echo $existing | grep -q "${SERVER_IMG_DIR}/${name_re}"; then
        copy-file "$f" "${SERVER_IMG_DIR}/"
    fi
done


echo "Deleting all removed images from server ..."
if [[ "$existing" ]]; then
    echo "$existing" | while read f; do
        name=$(basename "$f")
        if [[ ! -f "${IMG_DIR}/${name}" ]]; then
            echo "Deleting ${name} from server ..."
            run-cmd "rm ${f}"
        fi
    done
fi


echo "Done!"
