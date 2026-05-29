#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT_PATH:-/Users/mikhailberezovskiy/Desktop/Godot.app/Contents/MacOS/Godot}"
BUILD_DIR="$SCRIPT_DIR/build/web"

log() { printf '==> [%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

if [[ ! -x "$GODOT" ]]; then
  echo "Godot не найден по пути: $GODOT" >&2
  echo "Укажи путь через переменную GODOT_PATH=... bash build_web.sh" >&2
  exit 1
fi

log "Очистка $BUILD_DIR..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Экспорт Web-сборки ($GODOT)..."
cd "$SCRIPT_DIR"
"$GODOT" --headless --export-release "Web" "$BUILD_DIR/index.html"

log "Копирование статических файлов..."
cp "$SCRIPT_DIR/../merchant_web/bridge.js"  "$BUILD_DIR/bridge.js"
cp "$SCRIPT_DIR/../merchant_web/loader.gif" "$BUILD_DIR/loader.gif"

log "Размер сборки:"
du -sh "$BUILD_DIR"
echo ""
log "Файлы:"
ls -lh "$BUILD_DIR"
