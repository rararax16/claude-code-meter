#!/usr/bin/env bash
# .app バンドルを生成するスクリプト。
# 使い方:
#   ./scripts/bundle.sh           # release ビルド -> ./dist/Claude Code Meter.app
#   ./scripts/bundle.sh debug     # debug ビルド
set -euo pipefail

MODE="${1:-release}"
BIN_NAME="ClaudeCodeMeter"           # Swift target 名 (内部)
BUNDLE_NAME="Claude Code Meter"      # ユーザーが見る .app 名

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. ビルド
if [ "$MODE" = "release" ]; then
  swift build -c release --arch arm64 --arch x86_64
else
  swift build
fi

# universal バイナリ (release) or arch 固有 (debug) の場所を解決
if [ "$MODE" = "release" ]; then
  BIN="$ROOT/.build/apple/Products/Release/$BIN_NAME"
else
  ARCH="$(uname -m)"
  if [ "$ARCH" = "arm64" ]; then
    BIN="$ROOT/.build/arm64-apple-macosx/debug/$BIN_NAME"
  else
    BIN="$ROOT/.build/x86_64-apple-macosx/debug/$BIN_NAME"
  fi
fi

if [ ! -f "$BIN" ]; then
  echo "❌ build artifact not found at $BIN" >&2
  exit 1
fi

# 2. .app 構造を作成 (バンドルディレクトリはスペース入り、中の実行ファイルは BIN_NAME のまま)
DIST="$ROOT/dist"
APP="$DIST/$BUNDLE_NAME.app"
# 旧バンドル (スペースなし) があれば一緒に消す
rm -rf "$APP" "$DIST/$BIN_NAME.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# アイコン (Resources/AppIcon.icns があれば取り込む)
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# 3. Hardened Runtime + ad-hoc 署名。
#    --deep は macOS 13 以降 deprecated。ネストバンドルが無いので、バイナリと .app を個別に署名する。
#    --options runtime で Hardened Runtime を有効化。
codesign --force --options runtime --sign - "$APP/Contents/MacOS/$BIN_NAME"
codesign --force --options runtime --sign - "$APP"

echo "✅ Bundled: $APP"
echo ""
echo "Run with:"
echo "  open \"$APP\""
echo ""
echo "Distribute by zipping:"
echo "  (cd \"$DIST\" && zip -r \"$BUNDLE_NAME-\$(date +%Y%m%d).zip\" \"$BUNDLE_NAME.app\")"
