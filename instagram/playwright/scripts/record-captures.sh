#!/usr/bin/env bash
# Playwright で各シナリオの動画を撮り、ffmpeg で gif に変換して
# `captures/<test-name>.gif` に置く。
#
# 使い方:
#   cd instagram/playwright && npm run capture
#   PLAYBACK_RATE=2.5 npm run capture
#
# 必要: ffmpeg + 全サービス起動 (mysql / Django / Celery (eager 同期化済) / ai-worker / Next)

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
    *register*post*timeline*) echo "01-register-post-self-timeline" ;;
    *timeline*fan-out*)        echo "02-follow-fanout-on-write" ;;
    *like*)                    echo "03-like-toggle-counter" ;;
    *) echo "$1" | tr -cs 'A-Za-z0-9-' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//' | cut -c1-60 ;;
  esac
}

rm -rf "$RESULTS_DIR"
PLAYWRIGHT_VIDEO=on npx playwright test --reporter=list

mkdir -p "$CAPTURE_DIR"
shopt -s nullglob
for dir in "$RESULTS_DIR"/*/; do
  name=$(basename "$dir")
  out="$CAPTURE_DIR/$(capture_name_for "$name").gif"

  webms=()
  [[ -f "$dir/video.webm" ]] && webms+=("$dir/video.webm")
  for w in "$dir"page@*.webm; do [[ -f "$w" ]] && webms+=("$w"); done

  if (( ${#webms[@]} == 0 )); then
    echo "skip: no video in $dir"; continue
  elif (( ${#webms[@]} == 1 )); then
    echo "→ $out"
    ffmpeg -y -i "${webms[0]}" \
      -vf "setpts=${PLAYBACK_RATE}*PTS,fps=10,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
      -loop 0 "$out" 2>/dev/null
  else
    echo "→ $out (hstack ${#webms[@]} contexts)"
    ffmpeg -y -i "${webms[0]}" -i "${webms[1]}" \
      -filter_complex "[0:v]setpts=${PLAYBACK_RATE}*PTS,fps=10,scale=540:-1:flags=lanczos[a];[1:v]setpts=${PLAYBACK_RATE}*PTS,fps=10,scale=540:-1:flags=lanczos[b];[a][b]hstack=inputs=2,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
      -loop 0 "$out" 2>/dev/null
  fi
done

echo
ls -lh "$CAPTURE_DIR"/*.gif 2>/dev/null || echo "(none)"
