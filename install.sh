#!/bin/bash
# =============================================
# INSTALADOR VPN - Menú Principal
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Verificar root
[[ $EUID -ne 0 ]] && error "Ejecutar como root: sudo bash $0"

# URL base de los scripts
BASE_URL="https://raw.githubusercontent.com/Yelsinm110/AriadnyHn/main"

clear
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         INSTALADOR VPN COMPLETO 🚀            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Selecciona qué instalar:${NC}"
echo "  1) Caddy Server"
echo "  2) V2Ray"
echo "  3) SSH-Go Proxy"
echo "  4) TODOS (Instalación completa)"
echo "  5) Salir"
echo ""
read -p "➜ Opción: " OPCION

case $OPCION in
    1)
        bash <(curl -sL $BASE_URL/install-caddy.sh)
        ;;
    2)
        bash <(curl -sL $BASE_URL/install-v2ray.sh)
        ;;
    3)
        bash <(curl -sL $BASE_URL/install-sshgo.sh)
        ;;
    4)
        echo -e "${BLUE}Instalando TODOS los servicios...${NC}"
        bash <(curl -sL $BASE_URL/install-caddy.sh)
        bash <(curl -sL $BASE_URL/install-v2ray.sh)
        bash <(curl -sL $BASE_URL/install-sshgo.sh)
        echo -e "${GREEN}✅ Instalación completa finalizada!${NC}"
        ;;
    5)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        error "Opción inválida"
        ;;
esac
