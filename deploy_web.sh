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

# Генерируем version.json с unix-timestamp деплоя
echo "{\"v\":\"$(date +%s)\"}" > "$BUILD_DIR/version.json"

rsync -az --delete \
  -e "ssh ${SSH_OPTS[*]}" \
  "$BUILD_DIR/" \
  "$SERVER:$REMOTE_DIR/"

# Nginx работает от www-data — даём право на чтение после каждого rsync.
ssh "${SSH_OPTS[@]}" "$SERVER" \
  "chmod o+x /root /root/space_game /root/space_game/front /root/space_game/front/build /root/space_game/front/build/web && chmod -R o+r $REMOTE_DIR"

echo ""
echo "✓ Done — https://stage.sonnegames.xyz/"
