#!/usr/bin/env bash
# 2 BrowserContext (Device A | B) のテストを録画し、ffmpeg hstack で 1 枚の gif にする
# (slack / figma と同じ見せ方)。
#
#   cd linear/playwright && npm run capture
# 必要: ffmpeg + mysql :3330 (webServer が backend/frontend を起動する)。
set -euo pipefail
cd "$(dirname "$0")/.."

CAPTURE_DIR="captures"
RESULTS_DIR="test-results"
RATE="${PLAYBACK_RATE:-1.2}"

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg required (brew install ffmpeg)" >&2; exit 1; }
mkdir -p "$CAPTURE_DIR"

record() { # $1=grep pattern, $2=output name
  rm -rf "$RESULTS_DIR"
  PLAYWRIGHT_VIDEO=on npx playwright test -g "$1" --reporter=list || true

  local vids=()
  while IFS= read -r f; do vids+=("$f"); done < <(find "$RESULTS_DIR" -name '*.webm' | sort)
  if [ "${#vids[@]}" -lt 2 ]; then echo "expected 2 videos for '$1', got ${#vids[@]}" >&2; exit 1; fi

  local out="$CAPTURE_DIR/$2"
  ffmpeg -y -i "${vids[0]}" -i "${vids[1]}" \
    -filter_complex "[0:v]setpts=${RATE}*PTS[l];[1:v]setpts=${RATE}*PTS[r];[l][r]hstack=inputs=2,fps=10,scale=1100:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
    -loop 0 "$out" 2>/dev/null
  echo "→ $out"
  ls -lh "$out"
}

record "作成と移動が別デバイス" "01-realtime-fanout.gif"
record "オフライン編集" "02-offline-replay.gif"
record "招待した別ユーザ" "03-collaboration.gif"
