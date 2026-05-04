#!/usr/bin/env bash
# Playwright で各シナリオの動画を撮り、ffmpeg で gif に変換して
# `captures/<test-name>.gif` に置く。README に埋め込む用。
#
# 使い方:
#   cd reddit/playwright
#   ./scripts/record-captures.sh
# または:
#   npm run capture
#
# 必要: ffmpeg (brew install ffmpeg)

set -euo pipefail

cd "$(dirname "$0")/.."

CAPTURE_DIR="captures"
RESULTS_DIR="test-results"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg が見つかりません。brew install ffmpeg してください。" >&2
  exit 1
fi

# 既存 results を削除して新規録画
rm -rf "$RESULTS_DIR"

# 常時録画モードで test 実行
PLAYWRIGHT_VIDEO=on npx playwright test --reporter=list

mkdir -p "$CAPTURE_DIR"

# test-results/ 直下のディレクトリ名は test 名から派生する。
# 各ディレクトリの video.webm を gif に変換する。
shopt -s nullglob
for dir in "$RESULTS_DIR"/*/; do
  name=$(basename "$dir")
  webm="$dir/video.webm"
  if [[ ! -f "$webm" ]]; then
    echo "skip: no video in $dir"
    continue
  fi
  # ディレクトリ名は test 名から派生し UTF-8 を含むので、README 用に
  # 内容ベースで ASCII 名にマッピングする (test を増やすたびにここを更新)。
  case "$name" in
    *anonymous*)   out_name="01-anonymous-feed" ;;
    *認証フロー*)   out_name="02-auth-flow" ;;
    *ai-worker*)   out_name="03-ai-summarize" ;;
    *) out_name=$(echo "$name" | sed -E 's/-retry[0-9]+$//; s/-chromium$//') ;;
  esac
  out="$CAPTURE_DIR/${out_name}.gif"
  echo "→ $out"
  # fps=10, 幅 720px, lanczos リサンプリング、palette 生成で品質を保つ
  ffmpeg -y -i "$webm" \
    -vf "fps=10,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
    -loop 0 "$out" 2>/dev/null
done

echo
echo "captures generated:"
ls -lh "$CAPTURE_DIR"/*.gif 2>/dev/null || echo "(none)"
