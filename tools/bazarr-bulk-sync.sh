#!/usr/bin/env bash
# Bulk-sync existing subtitles through Bazarr's manual sync API (PATCH /api/subtitles
# with action=sync), which is the same engine as the "Sync" action in the UI.
# Runs as background jobs inside Bazarr, keeps history/metadata intact.
#
# Usage:
#   bazarr-bulk-sync.sh [limit] [language]
#     limit     max number of subtitles to sync (default: all)
#     language  only sync this code2 language: en, pt, pb (default: all)
#
# Environment:
#   BAZARR_URL      Bazarr base URL       (default: read from LAN_IP in .env, port 6767)
#   BAZARR_APIKEY   Bazarr API key        (default: read from config/bazarr/config/config.yaml)
#   JOBS            parallel syncs        (default: 2 — each sync analyzes the full audio track, CPU heavy)
#   DRY_RUN         1 = list targets and exit (default: 0)
#   EXCLUDE_RE      regex of paths to skip (default: skips *.alass/autosubsync/ffsubsync variants
#                   already produced by tools/subsync.sh)
#
# Notes:
# - Forced subs are skipped (ffsubsync cannot sync them).
# - Non-forced variants of the same movie/episode all get synced unless EXCLUDE_RE filters them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BAZARR_CONFIG="$REPO_ROOT/config/bazarr/config/config.yaml"

# API key comes from the local (gitignored) Bazarr config unless overridden.
APIKEY="${BAZARR_APIKEY:-$(awk '/^auth:/{f=1;next} /^[^ ]/{f=0} f && /apikey:/{print $2; exit}' "$BAZARR_CONFIG")}"

# LAN IP comes from the local (gitignored) .env unless overridden.
if [ -z "${BAZARR_URL:-}" ]; then
    LAN_IP="${LAN_IP:-$(sed -n 's/^LAN_IP=//p' "$REPO_ROOT/.env" | head -1)}"
    BAZARR_URL="http://${LAN_IP:?LAN IP not found in .env - see env.example (or set BAZARR_URL)}:6767"
fi

LIMIT="${1:--1}"
LANG_FILTER="${2:-}"
JOBS="${JOBS:-2}"
DRY_RUN="${DRY_RUN:-0}"
EXCLUDE_RE="${EXCLUDE_RE:-\\.(alass|autosubsync|ffsubsync)\\.srt$}"

B="$BAZARR_URL/api"

if [ -z "$APIKEY" ]; then
    echo "Error: could not read auth.apikey from $BAZARR_CONFIG (or set BAZARR_APIKEY)" >&2
    exit 1
fi

# Collect "type|media_id|lang|path" for every external, non-forced subtitle on file.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

jq_filter=".subtitles[]? |
  select(.embedded_track_id == null and .forced == false and (.path | test(\"\\.srt$\")))
  | [.code2, .path] | @tsv"

# Movies: subtitles come embedded in the movie list.
curl -s --get "$B/movies" --data-urlencode "apikey=$APIKEY" | jq -r --arg lang "$LANG_FILTER" \
  '.data[] as $m | $m.subtitles[]? |
   select(.embedded_track_id == null and .forced == false and (.path | test("\\.srt$"))) |
   if $lang != "" then select(.code2 == $lang) else . end |
   ["movie", $m.radarrId, .code2, .hi, .path] | @tsv' >> "$TMP"

# Series: subtitles live per-episode, so fetch episodes of each series.
while IFS=$'\t' read -r sid title; do
    curl -s --get "$B/episodes" --data-urlencode "apikey=$APIKEY" \
        --data-urlencode "seriesid[]=$sid" | jq -r --arg lang "$LANG_FILTER" \
        '.data[] as $e | $e.subtitles[]? |
         select(.embedded_track_id == null and .forced == false and (.path | test("\\.srt$"))) |
         if $lang != "" then select(.code2 == $lang) else . end |
         ["episode", $e.sonarrEpisodeId, .code2, .hi, .path] | @tsv' >> "$TMP"
done < <(curl -s --get "$B/series" --data-urlencode "apikey=$APIKEY" |
    jq -r '.data[] | [.sonarrSeriesId, .title] | @tsv')

TARGETS=""
while IFS=$'\t' read -r type id code hi subpath; do
    if [[ $subpath =~ $EXCLUDE_RE ]]; then
        continue
    fi
    printf -v row '%s\t%s\t%s\t%s\t%s\n' "$type" "$id" "$code" "$hi" "$subpath"
    TARGETS+="$row"
done < "$TMP"
mapfile -t LINES <<< "$TARGETS"
if [ "$LIMIT" -ge 0 ]; then
    LINES=("${LINES[@]:0:$LIMIT}")
fi

total=${#LINES[@]}
echo "Found $total subtitle file(s) to sync."
if [ "$total" -eq 0 ] || [ "$DRY_RUN" = "1" ]; then
    printf '  %s\n' "${LINES[@]}" | cut -f2-
    [ "$DRY_RUN" = "1" ] && echo "(dry run, nothing done)"
    exit 0
fi

failures=0

sync_one() {
    local type=$1 id=$2 code=$3 hi=$4 subpath=$5
    local enc resp
    enc=$(jq -rn --arg p "$subpath" '$p|@uri')
    resp=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
        "$B/subtitles?apikey=$APIKEY&action=sync&type=$type&id=$id&language=$code&path=$enc&forced=False&hi=$hi&gss=True&no_fix_framerate=True")
    if [ "$resp" != "204" ]; then
        echo "  ✗ [HTTP $resp] $subpath" >&2
        return 1
    fi
    echo "  ✓ queued $subpath"
}

count=0
for line in "${LINES[@]}"; do
    IFS=$'\t' read -r type id code hi subpath <<< "$line"
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do sleep 1; done
    sync_one "$type" "$id" "$code" "$hi" "$subpath" & pids+=($!)
    count=$((count + 1))
done

for pid in "${pids[@]}"; do
    wait "$pid" || failures=$((failures + 1))
done

if [ "$failures" -gt 0 ]; then
    echo "Note: some syncs failed — see ✗ lines above."
fi

echo "Done: $total subtitle syncs queued ($JOBS parallel). Bazarr processes each in the background —"
echo "check its System > Activity or the file timestamps to see progress."
