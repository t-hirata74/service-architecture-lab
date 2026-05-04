#!/usr/bin/env bash
# Playwright で各シナリオの動画を撮り、ffmpeg で gif に変換して
# `captures/<test-name>.gif` に置く。
#
# 使い方:
#   cd github/playwright && npm run capture
#   PLAYBACK_RATE=2.5 npm run capture
#
# 必要: ffmpeg + 全サービス起動 (mysql / Rails graphql / ai-worker / Next urql)

set -euo pipefail
cd "$(dirname "$0")/.."

CAPTURE_DIR="captures"
RESULTS_DIR="test-results"
PLAYBACK_RATE="${PLAYBACK_RATE:-1.8}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg required (brew install ffmpeg / apt install ffmpeg)" >&2
  exit 1
fi

capture_name_for() {
  case "$1" in
    *organization*repository*PR*) echo "01-browse-org-repo-pr" ;;
    *outside_collaborator*)        echo "02-visibility-private-hidden" ;;
    *createIssue*)                 echo "03-graphql-create-issue" ;;
    *ai-worker*check*run*)         echo "04-ai-worker-check-aggregation" ;;
    *) echo "$1" | tr -cs 'A-Za-z0-9-' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//' | cut -c1-60 ;;
  esac
}

rm -rf "$RESULTS_DIR"
PLAYWRIGHT_VIDEO=on npx playwright test --reporter=list

mkdir -p "$CAPTURE_DIR"
shopt -s nullglob
for dir in "$RESULTS_DIR"/*/; do
  name=$(basename "$dir")
  webm="$dir/video.webm"
  [[ -f "$webm" ]] || { echo "skip: no video in $dir"; continue; }
  out="$CAPTURE_DIR/$(capture_name_for "$name").gif"
  echo "→ $out"
  ffmpeg -y -i "$webm" \
    -vf "setpts=${PLAYBACK_RATE}*PTS,fps=10,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
    -loop 0 "$out" 2>/dev/null
done

echo
ls -lh "$CAPTURE_DIR"/*.gif 2>/dev/null || echo "(none)"
