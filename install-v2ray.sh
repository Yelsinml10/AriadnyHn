#!/bin/bash

# =============================================
# Autoinstalador V2Ray - Configuración Exacta
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

# Verificar root
[[ $EUID -ne 0 ]] && error "Ejecutar como root: sudo bash $0"

# =============================================
# 1. Instalar V2Ray
# =============================================
step "Instalando V2Ray..."

bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

if ! command -v v2ray &>/dev/null; then
    error "V2Ray no se instaló correctamente."
fi

info "V2Ray instalado: $(v2ray -version | head -1)"

# =============================================
# 2. Configurar V2Ray - TU CONFIGURACIÓN EXACTA
# =============================================
step "Configurando V2Ray..."

# Backup
mv /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.bak 2>/dev/null

# TU CONFIGURACIÓN COMPLETA - SIN CAMBIOS
cat > /usr/local/etc/v2ray/config.json << 'EOF'
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 9090,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "7985e3e4-1663-46ec-987f-c3afcfeaaf02",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

info "Configuración guardada exactamente como la proporcionaste."

# =============================================
# 3. Iniciar servicio
# =============================================
step "Iniciando V2Ray..."

systemctl daemon-reload
systemctl enable v2ray
systemctl restart v2ray

sleep 2

if systemctl is-active --quiet v2ray; then
    info "V2Ray está activo y corriendo."
else
    error "V2Ray falló al arrancar. Revisa: journalctl -u v2ray"
fi

# =============================================
# 4. Script de control
# =============================================
step "Creando script de control..."

cat > /usr/local/bin/v2ray-control << 'EOF'
#!/bin/bash
case "$1" in
    start)
        systemctl start v2ray
        echo "✅ V2Ray iniciado"
        ;;
    stop)
        systemctl stop v2ray
        echo "⏹️ V2Ray detenido"
        ;;
    restart)
        systemctl restart v2ray
        echo "🔄 V2Ray reiniciado"
        ;;
    status)
        systemctl status v2ray --no-pager
        ;;
    logs)
        journalctl -u v2ray -f
        ;;
    info)
        echo "=== V2Ray ==="
        echo "Configuración: /usr/local/etc/v2ray/config.json"
        echo "Logs: journalctl -u v2ray -f"
        ;;
    *)
        echo "Uso: v2ray-control {start|stop|restart|status|logs|info}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/v2ray-control
info "Script de control creado: v2ray-control"

# =============================================
# 5. Resumen final
# =============================================
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║           ✅ V2RAY INSTALADO! 🚀               ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}📌 Configuración:${NC}"
echo -e "   Puerto: ${GREEN}9090${NC}"
echo -e "   UUID: ${GREEN}7985e3e4-1663-46ec-987f-c3afcfeaaf02${NC}"
echo -e "   Path: ${GREEN}/${NC}"
echo -e "   Protocolo: ${GREEN}vmess + ws${NC}"
echo ""
echo -e "${BLUE}🛠️  Comandos:${NC}"
echo "   v2ray-control start      # Iniciar"
echo "   v2ray-control stop       # Detener"
echo "   v2ray-control status     # Estado"
echo "   v2ray-control logs       # Ver logs"
echo "   v2ray-control info       # Información"
echo ""
echo -e "${BLUE}📁 Archivos:${NC}"
echo "   Configuración: /usr/local/etc/v2ray/config.json"
echo "   Logs: /var/log/v2ray/"
echo ""

info "Instalación completada!"
