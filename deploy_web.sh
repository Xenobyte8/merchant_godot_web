#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="root@138.124.24.149"
REMOTE_DIR="/root/space_game/front/build/web"
BUILD_DIR="$SCRIPT_DIR/build/web"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=12
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
)

log() { printf '==> [%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

log "Сборка Godot Web..."
bash "$SCRIPT_DIR/build_web.sh"

log "Деплой на $SERVER:$REMOTE_DIR..."
ssh "${SSH_OPTS[@]}" "$SERVER" "mkdir -p $REMOTE_DIR"
rsync -az --delete \
  -e "ssh ${SSH_OPTS[*]}" \
  "$BUILD_DIR/" \
  "$SERVER:$REMOTE_DIR/"
# FastAPI StaticFiles читает файлы с диска на каждый запрос — рестарт бэкенда не нужен.

echo ""
echo "✓ Done — https://api.sonneprojecxt.xyz/"
