#!/bin/bash
set -e

INSTALL_DIR="$HOME/vpn_setup"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

### === Установка Docker и Docker Compose === ###
echo "🔧 Установка Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
fi

echo "🔧 Проверка docker compose..."
if docker compose version &>/dev/null; then
  COMPOSE_CMD="docker compose"
elif docker-compose version &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  apt install -y docker-compose
  COMPOSE_CMD="docker-compose"
fi

### === Ввод логинов/паролей === ###
read -p "🧠 Введите пароль для Shadowsocks: " SS_PASSWORD
read -p "🧠 Введите логин для IKEv2/WireGuard: " VPN_USER
read -p "🧠 Введите пароль для IKEv2/WireGuard: " VPN_PASS
read -p "🌐 Введите ваш домен или IP-адрес для VLESS/WG: " SERVER_DOMAIN

### === SHADOWSOCKS (Rust) === ###
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

### === WIREGUARD (wg-easy) === ###
mkdir -p wireguard
cat > wireguard/docker-compose.yml <<EOF
version: '3'
services:
  wireguard:
    image: weejewel/wg-easy
    container_name: wg-easy
    environment:
      - WG_HOST=$SERVER_DOMAIN
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

### === IKEv2 (strongSwan) === ###
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

### === VLESS (Xray-Reality) === ###
mkdir -p vless/config && cd vless
echo "🔐 Генерация ключей X25519..."
KEYS=$(docker run --rm teddysun/xray xray x25519)
PRIV_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $NF}')
PUB_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $NF}')
UUID=$(cat /proc/sys/kernel/random/uuid)

cat > config/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.cloudflare.com:443",
          "xver": 0,
          "serverNames": ["www.cloudflare.com"],
          "privateKey": "$PRIV_KEY",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

cat > docker-compose.yml <<EOF
version: '3'
services:
  vless:
    image: teddysun/xray
    container_name: vless
    volumes:
      - ./config:/etc/xray
    ports:
      - "443:443"
    restart: unless-stopped
EOF
cd "$INSTALL_DIR"

### === UFW Firewall === ###
apt install -y ufw
ufw allow OpenSSH
ufw allow 8388/tcp
ufw allow 8388/udp
ufw allow 51820/udp
ufw allow 51821/tcp
ufw allow 500/udp
ufw allow 4500/udp
ufw allow 443/tcp
ufw --force enable

### === Fail2Ban === ###
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban

### === Запуск всех сервисов === ###
$COMPOSE_CMD -f shadowsocks/docker-compose.yml up -d
$COMPOSE_CMD -f wireguard/docker-compose.yml up -d
$COMPOSE_CMD -f ikev2/docker-compose.yml up -d
$COMPOSE_CMD -f vless/docker-compose.yml up -d

### === Вывод настроек === ###
SS_URI="ss://$(echo -n "xchacha20-ietf-poly1305:$SS_PASSWORD" | base64 -w0)@$SERVER_DOMAIN:8388#Shadowsocks"

echo ""
echo "🎉 VPN УСТАНОВЛЕН! Вот ваши данные:"
echo ""
echo "📦 Shadowsocks:"
echo "   🔑 Метод: xchacha20-ietf-poly1305"
echo "   🔐 Пароль: $SS_PASSWORD"
echo "   🌍 Хост: $SERVER_DOMAIN"
echo "   📱 URI: $SS_URI"
echo ""

echo "📦 WireGuard & IKEv2:"
echo "   👤 Логин: $VPN_USER"
echo "   🔐 Пароль: $VPN_PASS"
echo "   📡 Хост: $SERVER_DOMAIN"
echo ""

echo "📦 VLESS (Reality):"
echo "   🔑 UUID: $UUID"
echo "   🔐 Public Key: $PUB_KEY"
echo "   🧩 shortId: 0123456789abcdef"
echo "   🎯 SNI: www.cloudflare.com"
echo ""

echo "🔗 Shadowsocks QR: https://qrcode.show?text=$(echo -n "$SS_URI" | jq -sRr @uri)"
echo ""
