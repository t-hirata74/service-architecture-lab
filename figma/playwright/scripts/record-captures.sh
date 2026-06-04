#!/usr/bin/env bash
# 収束 E2E (op fan-out) を 2 BrowserContext で録画し、ffmpeg で alice|bob を hstack した
# gif を captures/ に置く (slack / discord / uber と同じ仕組み)。
#
# 使い方:
#   cd figma/playwright && npm run capture
#   PLAYBACK_RATE=1.0 npm run capture
#
# 必要: ffmpeg + 全サービス (mysql / Rails / ai-worker / Next) — webServer が自動起動する。
set -euo pipefail
cd "$(dirname "$0")/.."

CAPTURE_DIR="captures"
VID_DIR="test-results/videos"
RATE="${PLAYBACK_RATE:-1.3}"

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg required (brew install ffmpeg)" >&2; exit 1; }

rm -rf "$VID_DIR"
PLAYWRIGHT_VIDEO=on npx playwright test -g "op fan-out" --reporter=list || true

mkdir -p "$CAPTURE_DIR"
shopt -s nullglob
vids=()
while IFS= read -r f; do vids+=("$f"); done < <(ls -t "$VID_DIR"/*.webm 2>/dev/null || true)

if (( ${#vids[@]} < 2 )); then
  echo "need 2 videos, got ${#vids[@]} (PLAYWRIGHT_VIDEO=on で録画されたか確認)" >&2
  exit 1
fi

# ls -t は新しい順。alice context を先に close するので alice=古い (vids[1]) / bob=新しい (vids[0])。
left="${vids[1]}"   # alice
right="${vids[0]}"  # bob
out="$CAPTURE_DIR/01-op-fanout-converge.gif"

ffmpeg -y -i "$left" -i "$right" \
  -filter_complex "[0:v]setpts=${RATE}*PTS,fps=10,scale=480:-1:flags=lanczos[a];[1:v]setpts=${RATE}*PTS,fps=10,scale=480:-1:flags=lanczos[b];[a][b]hstack=inputs=2,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 "$out" 2>/dev/null

echo "→ $out"
ls -lh "$out"
