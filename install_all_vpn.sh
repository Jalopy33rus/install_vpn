#!/bin/bash

set -e

# === ЦВЕТА ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# === ФУНКЦИИ ===
function print_info() { echo -e "${BLUE}$1${NC}"; }
function print_success() { echo -e "${GREEN}$1${NC}"; }
function print_warn() { echo -e "${YELLOW}$1${NC}"; }
function print_error() { echo -e "${RED}$1${NC}"; exit 1; }

# === ПРОВЕРКА ДОКЕРА ===
if ! command -v docker &> /dev/null; then
  print_info "🔧 Установка Docker..."
  curl -fsSL https://get.docker.com | bash
else
  print_success "✅ Docker уже установлен"
fi

# === ПРОВЕРКА docker-compose ===
if ! docker compose version &> /dev/null; then
  if command -v docker-compose &> /dev/null; then
    print_success "✅ Используется docker-compose (v1)"
  else
    print_error "❌ Docker Compose не найден. Установите его вручную."
  fi
else
  print_success "✅ Docker Compose доступен"
fi

# === УСТАНОВКА SHADOWSOCKS ===
SS_DIR="/opt/shadowsocks"
if [ ! -d "$SS_DIR" ]; then
  print_info "📦 Установка Shadowsocks..."
  read -rp "🧠 Введите пароль для Shadowsocks: " SS_PASS
  mkdir -p $SS_DIR
  cat > $SS_DIR/docker-compose.yml <<EOF
version: '3'
services:
  ssserver:
    image: ghcr.io/shadowsocks/ssserver-rust
    container_name: ss-server
    restart: unless-stopped
    ports:
      - 8388:8388/udp
      - 8388:8388/tcp
    environment:
      - SERVER_PORT=8388
      - PASSWORD=$SS_PASS
      - METHOD=chacha20-ietf-poly1305
EOF
  docker compose -f $SS_DIR/docker-compose.yml up -d
  print_success "✅ Shadowsocks установлен"
else
  print_success "✅ Shadowsocks уже установлен"
fi

# === УСТАНОВКА WIREGUARD ===
WG_DIR="/opt/wireguard"
if [ ! -d "$WG_DIR" ]; then
  print_info "📦 Установка WireGuard..."
  read -rp "🧠 Введите логин для WireGuard: " WG_USER
  read -rp "🧠 Введите пароль для WireGuard: " WG_PASS
  mkdir -p $WG_DIR
  cat > $WG_DIR/docker-compose.yml <<EOF
version: '3'
services:
  wg-easy:
    container_name: wg-easy
    image: weejewel/wg-easy
    restart: unless-stopped
    environment:
      - WG_HOST=\$(curl -s ifconfig.me)
      - PASSWORD=$WG_PASS
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    volumes:
      - ./config:/etc/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
EOF
  docker compose -f $WG_DIR/docker-compose.yml up -d
  print_success "✅ WireGuard установлен"
else
  print_success "✅ WireGuard уже установлен"
fi

# === УСТАНОВКА VLESS+REALITY ===
VLESS_DIR="/opt/vless-reality"
if [ ! -f "$VLESS_DIR/config.json" ]; then
  print_info "📦 Установка VLESS + Reality..."
  read -rp "🌐 Введите ваш домен или IP для VLESS: " DOMAIN
  KEYS=$(docker run --rm teddysun/xray xray x25519)
  PRIVATE_KEY=$(echo "$KEYS" | grep 'Private key:' | awk '{print $3}')
  PUBLIC_KEY=$(echo "$KEYS" | grep 'Public key:' | awk '{print $3}')
  SHORT_ID=$(openssl rand -hex 8)
  UUID=$(cat /proc/sys/kernel/random/uuid)
  mkdir -p "$VLESS_DIR"
  cat > "$VLESS_DIR/config.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.cloudflare.com:443",
        "xver": 0,
        "serverNames": ["$DOMAIN"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
  docker run -d --name xray-vless --restart unless-stopped -p 443:443 \
    -v "$VLESS_DIR/config.json:/etc/xray/config.json" teddysun/xray
  print_success "✅ VLESS установлен"
else
  print_success "✅ VLESS уже установлен"
fi

# === ВЫВОД ДАННЫХ ===
echo -e "\n${GREEN}🎉 Установка завершена. Данные для подключения:${NC}"
echo -e "\n${BLUE}--- Shadowsocks ---${NC}"
echo "ss://$(echo -n "xchacha20-ietf-poly1305:$SS_PASS@$(curl -s ifconfig.me):8388" | base64 -w0)#SS"

echo -e "\n${BLUE}--- WireGuard ---${NC}"
echo "Панель: http://$(curl -s ifconfig.me):51821"
echo "Логин: admin"
echo "Пароль: $WG_PASS"

echo -e "\n${BLUE}--- VLESS + Reality ---${NC}"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo "Сервер: $DOMAIN"
echo "vless://$UUID@$DOMAIN:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#VLESS-Reality"
