#!/bin/bash

# =============================================
# INSTALADOR VPN - MENÚ PRINCIPAL
# =============================================

set -o errexit
set -o pipefail
set -o nounset

# Paleta de colores para la nueva interfaz
RED='\033[0;31m'
L_RED='\033[1;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

TITLE="INSTALADOR VPN COMPLETO 🚀"
TOKEN="${TOKEN:-}"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

# Funciones de sistema
info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "Ejecuta como root: sudo bash $0"
  fi
}

# Esta función instala el script como el comando 'menu' globalmente
setup_menu_command() {
  local script_path
  script_path=$(readlink -f "$0")
  # Si el script no se está ejecutando ya desde el destino
  if [[ "$script_path" != "/usr/local/bin/menu" ]]; then
    cp "$script_path" /usr/local/bin/menu
    chmod +x /usr/local/bin/menu
  fi
}

# Diseño del Header visual
display_header() {
  clear
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo -e "           ${WHITE}${TITLE}${NC}"
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}BASE_URL:${NC} ${GREEN}$BASE_URL${NC}"
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo -e " ${GREEN}● SERVICIO: ACTIVO${NC}"
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo ""
}

check_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    error "curl no está instalado."
  fi
}

download_and_execute() {
  local script_name="$1"

  echo -e "\n${CYAN}Descargando $script_name...${NC}"
  if curl -fsSL "$BASE_URL/$script_name" > "$script_name"; then
    chmod +x "$script_name"
    echo -e "${GREEN}Ejecutando $script_name...${NC}"
    "./$script_name"
    rm "$script_name"
    echo -e "\n${GREEN}Operación finalizada. Presiona ENTER para continuar...${NC}"
    read -r
  else
    error "Error al descargar $script_name."
  fi
}

# MAIN MENU - DISEÑO ACTUALIZADO
main_menu() {
  while true; do
    display_header

    echo -e "${CYAN}[1] > ${GREEN}Caddy Server${NC}"
    echo -e "${CYAN}[2] > ${GREEN}V2Ray (VMess)${NC}"
    echo -e "${CYAN}[3] > ${GREEN}SSH-Go Proxy${NC}"
    echo -e "${CYAN}[4] > ${GREEN}Instalar todo${NC}"
    echo -e "${CYAN}[5] > ${GREEN}Firewall (firewalld)${NC}"
    echo -e "${CYAN}[6] > ${GREEN}SSH Panel (Gestión de usuarios)${NC}"
    echo -e "\n${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}[0] VOLVER${NC}               ${RED}[9] DESINSTALAR${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo ""

    echo -en "${GREEN}Ingresa una Opcion: ${NC}"
    read -r option

    case "$option" in
      1) download_and_execute "install-caddy.sh" ;;
      2) download_and_execute "install-v2ray.sh" ;;
      3) download_and_execute "install-sshgo.sh" ;;
      4)
        echo -e "\n${BLUE}Instalando todos los servicios...${NC}"
        download_and_execute "install-caddy.sh"
        download_and_execute "install-v2ray.sh"
        download_and_execute "install-sshgo.sh"
        echo -e "${GREEN}✅ Instalación completa finalizada!${NC}"
        sleep 2
        ;;
      5) download_and_execute "firewall.sh" ;;
      6) 
        echo -e "\n${YELLOW}📥 Instalando SSH Panel...${NC}"
        mkdir -p /usr/local/bin
        curl -fsSL "https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main/sshpanel.sh" -o /usr/local/bin/sshpanel.sh
        chmod +x /usr/local/bin/sshpanel.sh
        
        # Evita duplicar el alias en el .bashrc si ya fue instalado
        if ! grep -q "alias sshpanel=" ~/.bashrc; then
            echo "alias sshpanel='sudo /usr/local/bin/sshpanel.sh'" >> ~/.bashrc
        fi
        
        echo -e "${GREEN}✅ SSH Panel instalado. Ejecuta: sshpanel${NC}"
        echo -e "\n${GREEN}Presiona ENTER para continuar...${NC}"
        read -r
        ;;
      0) 
        echo -e "${YELLOW}Saliendo del panel...${NC}" 
        clear
        exit 0 
        ;;
      9) 
        echo -e "${RED}Módulo de desinstalación no configurado aún.${NC}"
        sleep 2 
        ;;
      *) 
        echo -e "${RED}Opción inválida.${NC}"
        sleep 1 
        ;;
    esac
  done
}

# Ejecución del Script
require_root
check_dependencies
setup_menu_command
main_menu

