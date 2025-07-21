#!/bin/bash

set -e
INSTALL_DIR="$HOME/vpn_install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

### === Проверка и установка Docker === ###
echo "🔧 Проверка Docker..."
if ! command -v docker &> /dev/null; then
  echo "📦 Устанавливаю Docker..."
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
fi

### === Проверка docker compose === ###
echo "🔧 Проверка Docker Compose..."
if docker compose version &>/dev/null; then
  COMPOSE_CMD="docker compose"
elif docker-compose version &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  echo "📦 Устанавливаю docker-compose..."
  apt install -y docker-compose
  COMPOSE_CMD="docker-compose"
fi

### === Ввод логинов и паролей === ###
read -p "Введите пароль для Shadowsocks: " SS_PASSWORD
read -p "Введите логин для IKEv2/WireGuard: " VPN_USER
read -p "Введите пароль для IKEv2/WireGuard: " VPN_PASS

### === Shadowsocks (xchacha20-ietf-poly1305) === ###
mkdir -p shadowsocks
cat > shadowsocks/docker-compose.yml <<EOF
version: '3'
services:
  ssserver:
    image: ghcr.io/shadowsocks/ssserver-rust
    container_name: ss-server
    ports:
      - "8388:8388/tcp"
      - "8388:8388/udp"
    environment:
      - PASSWORD=$SS_PASSWORD
      - METHOD=xchacha20-ietf-poly1305
    restart: unless-stopped
EOF

### === WireGuard (Docker + логин/пароль) === ###
mkdir -p wireguard
cat > wireguard/docker-compose.yml <<EOF
version: '3'
services:
  wireguard:
    image: weejewel/wg-easy
    container_name: wg-easy
    environment:
      - WG_HOST=your_vpn_ip_or_domain
      - PASSWORD=$VPN_PASS
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
    volumes:
      - ./config:/etc/wireguard
    restart: unless-stopped
EOF

### === IKEv2 VPN (strongSwan в Docker) === ###
mkdir -p ikev2
cat > ikev2/docker-compose.yml <<EOF
version: '3'
services:
  ikev2:
    image: mobtitude/docker-strongswan
    container_name: ikev2
    environment:
      - VPN_USER=$VPN_USER
      - VPN_PASSWORD=$VPN_PASS
    ports:
      - "500:500/udp"
      - "4500:4500/udp"
    restart: unless-stopped
EOF

### === VLESS (Xray Reality) === ###
echo "📦 Установка VLESS..."
mkdir -p vless && cd vless
if [ ! -d "vless-source" ]; then
  git clone https://github.com/myelectronix/xtls-reality-docker vless-source
fi
cd vless-source
chmod +x install.sh
./install.sh || echo "⚠️ Не удалось установить VLESS автоматически. Проверь вручную."
cd "$INSTALL_DIR"

### === Открытие портов через UFW === ###
echo "🛡️ Настройка UFW..."
apt install -y ufw
ufw allow OpenSSH
ufw allow 8388/tcp
ufw allow 8388/udp
ufw allow 51820/udp
ufw allow 51821/tcp
ufw allow 500/udp
ufw allow 4500/udp
ufw --force enable

### === Установка Fail2Ban === ###
echo "🛡️ Установка Fail2Ban..."
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban

### === Запуск контейнеров === ###
echo "🚀 Запуск всех VPN контейнеров..."
$COMPOSE_CMD -f shadowsocks/docker-compose.yml up -d
$COMPOSE_CMD -f wireguard/docker-compose.yml up -d
$COMPOSE_CMD -f ikev2/docker-compose.yml up -d

echo "✅ Установка завершена!"
