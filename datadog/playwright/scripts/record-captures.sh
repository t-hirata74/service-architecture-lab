#!/usr/bin/env bash
# dashboard の観測ループ (ingest → rollup → チャート表示) を録画し ffmpeg で gif 化する。
# 単一 context なので hstack はしない (datadog dashboard は単一ユーザ視点)。
#
#   cd datadog/playwright && npm run capture
# 必要: ffmpeg + 全サービス (mysql / Go backend / Next) — webServer が起動する。
set -euo pipefail
cd "$(dirname "$0")/.."

CAPTURE_DIR="captures"
RESULTS_DIR="test-results"
RATE="${PLAYBACK_RATE:-1.3}"

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg required (brew install ffmpeg)" >&2; exit 1; }

rm -rf "$RESULTS_DIR"
PLAYWRIGHT_VIDEO=on npx playwright test -g "dashboard のチャート" --reporter=list || true

mkdir -p "$CAPTURE_DIR"
shopt -s nullglob
vid=""
for f in "$RESULTS_DIR"/*/video.webm; do vid="$f"; break; done
[ -n "$vid" ] || { echo "no video recorded" >&2; exit 1; }

out="$CAPTURE_DIR/01-dashboard.gif"
ffmpeg -y -i "$vid" \
  -vf "setpts=${RATE}*PTS,fps=10,scale=820:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 "$out" 2>/dev/null

echo "→ $out"
ls -lh "$out"
