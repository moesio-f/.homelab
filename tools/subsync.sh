#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <folder1> [folder2] ..."
    exit 1
fi

IMAGE="mrorbitman/subsyncarr:latest"

VOLUMES=()
SCAN_PATHS=()

i=1
for DIR in "$@"; do
    ABS=$(realpath "$DIR")

    VOLUMES+=(-v "$ABS:/scan$i")
    SCAN_PATHS+=("/scan$i")

    i=$((i+1))
done

docker run -d --name subsync --rm \
    "${VOLUMES[@]}" \
    -p "5050:3000" \
    -e TZ="$(cat /etc/timezone 2>/dev/null || echo UTC)" \
    -e SCAN_PATHS="$(IFS=,; echo "${SCAN_PATHS[*]}")" \
    -e INCLUDE_ENGINES="alass,autosubsync" \
    -e CRON_SCHEDULE="disabled" \
    -e MAX_CONCURRENT_SYNC_TASKS=1 \
    -e PUID=1001 \
    -e PGID=1001 \
    "$IMAGE"
