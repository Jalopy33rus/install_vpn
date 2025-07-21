#!/bin/bash

set -e

# === ПЕРЕМЕННЫЕ ===
VLESS_DIR="/opt/vless-reality"
XRAY_IMAGE="teddysun/xray"
XRAY_CONTAINER="xray-vless"
CONFIG_FILE="${VLESS_DIR}/config.json"
DOMAIN=""
PRIVATE_KEY=""
PUBLIC_KEY=""
SHORT_ID=""
UUID=""
SERVER_NAME=""

# === ПРОВЕРКА: Установлен ли VLESS (по папке и config.json) ===
if [ -f "${CONFIG_FILE}" ]; then
    echo "✅ VLESS с Reality уже установлен. Пропускаем установку."
    exit 0
fi

# === ВВОД ДАННЫХ ОТ ПОЛЬЗОВАТЕЛЯ ===
read -rp "🌐 Введите ваш домен или IP-адрес (для SNI/ServerName): " DOMAIN

# === ГЕНЕРАЦИЯ Reality ключей ===
echo "🔐 Генерация Reality ключей (X25519)..."
KEYS=$(docker run --rm "${XRAY_IMAGE}" xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep 'Private key:' | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Public key:' | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)
UUID=$(cat /proc/sys/kernel/random/uuid)
SERVER_NAME="${DOMAIN}"

# === СОЗДАНИЕ ПАПКИ И CONFIG.JSON ===
mkdir -p "${VLESS_DIR}"

cat > "${CONFIG_FILE}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "${UUID}",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.cloudflare.com:443",
        "xver": 0,
        "serverNames": ["${SERVER_NAME}"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}"]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

# === ЗАПУСК XRAY-КОНТЕЙНЕРА С КОНФИГОМ ===
echo "🚀 Запуск VLESS + Reality с кастомной конфигурацией..."
docker run -d \
  --name ${XRAY_CONTAINER} \
  --restart unless-stopped \
  -p 443:443 \
  -v ${VLESS_DIR}/config.json:/etc/xray/config.json \
  ${XRAY_IMAGE}

# === ВЫВОД ДАННЫХ ДЛЯ КЛИЕНТА ===
echo ""
echo "✅ VLESS + Reality успешно установлен!"
echo "📌 UUID: ${UUID}"
echo "🔐 PublicKey: ${PUBLIC_KEY}"
echo "🧩 ShortID: ${SHORT_ID}"
echo "🌐 ServerName (SNI): ${SERVER_NAME}"
echo ""
echo "📎 Пример ссылки для клиента (например, v2rayN):"
echo ""
echo "vless://${UUID}@${DOMAIN}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#VLESS-Reality"
echo ""
