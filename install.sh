#!/bin/bash

# =============================================
# INSTALADOR VPN - MENÚ PRINCIPAL
# =============================================

set -o errexit
set -o pipefail
set -o nounset

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

TITLE="INSTALADOR VPN COMPLETO 🚀"
TOKEN="${TOKEN:-}" # Allow TOKEN to be set as an environment variable
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

# Functions
info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

# Check if running as root
require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "Este script debe ejecutarse como root. Usa 'sudo bash $0'."
  fi
}

# Display header
display_header() {
  clear
  echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
  printf "${BLUE}║%-50s║${NC}\n" "$TITLE"
  echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
}

# Check for required dependencies
check_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    error "curl no está instalado. Por favor, instálalo antes de continuar."
  fi
}

# Download and execute a script with optional authentication
download_and_execute() {
  local script_name="$1"

  if [[ -n "$TOKEN" ]]; then
    echo "Descargando $script_name..."
    if curl -fsSL -H "Authorization: token $TOKEN" "$BASE_URL/$script_name" > "$script_name"; then
      chmod +x "$script_name"
      echo "Ejecutando $script_name..."
      "./$script_name"
      rm "$script_name"
    else
      error "Error al descargar $script_name."
    fi
  else
    echo "Descargando $script_name..."
    if curl -fsSL "$BASE_URL/$script_name" > "$script_name"; then
      chmod +x "$script_name"
      echo "Ejecutando $script_name..."
      "./$script_name"
      rm "$script_name"
    else
      error "Error al descargar $script_name."
    fi
  fi
}

# Main menu
main_menu() {
  display_header

  echo -e "${YELLOW}Selecciona una opción:${NC}"
  echo "  1) Caddy Server"
  echo "  2) V2Ray"
  echo "  3) SSH-Go Proxy"
  echo "  4) Instalar todo"
  echo "  5) Firewall (firewalld)"
  echo "  6) SSH Panel (Gestión de usuarios)"
  echo "  7) Salir"
  echo ""

  read -r -p "➜ Opción: " option

  case "$option" in
    1) download_and_execute "install-caddy.sh" ;;
    2) download_and_execute "install-v2ray.sh" ;;
    3) download_and_execute "install-sshgo.sh" ;;
    4)
      echo -e "${BLUE}Instalando todos los servicios...${NC}"
      download_and_execute "install-caddy.sh"
      download_and_execute "install-v2ray.sh"
      download_and_execute "install-sshgo.sh"
      echo -e "${GREEN}✅ Instalación completa finalizada!${NC}"
      ;;
    5) download_and_execute "firewall.sh" ;;
    6) download_and_execute "install-sshpanel.sh" ;;
    7) echo "Saliendo..." ; exit 0 ;;
    *) error "Opción inválida. Por favor, selecciona una opción válida." ;;
  esac
}

# Script execution
require_root
check_dependencies
main_menu
