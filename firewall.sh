#!/bin/bash
# ============================================================
# 🔥 FIREWALL ULTIMATE PARA UBUNTU (UFW + IPTABLES)
# ============================================================
# 🚀 Script profesional para gestionar el firewall en Ubuntu
# 📦 Compatible con: Ubuntu 20.04, 22.04, 24.04
# 🌐 Funciona en: OCI, AWS, DigitalOcean, VPS, etc.
# 👤 Autor: TuNombre
# 📌 Versión: 1.0.0
# ============================================================

set -e

# ============================================================
# COLORES
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # Sin color

# ============================================================
# FUNCIONES DE MENSAJES
# ============================================================
info() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
step() { echo -e "${BLUE}[→]${NC} $1"; }
title() { echo -e "${CYAN}════════════════════════════════════════════════════${NC}"; }
header() { echo -e "${MAGENTA}$1${NC}"; }

# ============================================================
# VERIFICAR ROOT
# ============================================================
if [[ $EUID -ne 0 ]]; then
    error "Este script debe ejecutarse como root: sudo bash $0"
fi

# ============================================================
# DETECTAR SISTEMA OPERATIVO
# ============================================================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "No se pudo detectar el sistema operativo"
    fi

    if [[ "$OS" != "ubuntu" ]]; then
        warn "Este script está optimizado para Ubuntu, pero puede funcionar en Debian"
    fi

    info "Sistema detectado: $OS $VERSION"
}

# ============================================================
# MENÚ PRINCIPAL
# ============================================================
show_menu() {
    clear
    title
    header "   🔥 CONFIGURACIÓN DE FIREWALL PARA UBUNTU 🔥"
    title
    echo ""
    echo -e "${BLUE}Selecciona una opción:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC}  Instalar UFW"
    echo -e "  ${GREEN}2)${NC}  Abrir TODOS los puertos TCP (1-65535)"
    echo -e "  ${GREEN}3)${NC}  Abrir TODOS los puertos UDP (1-65535)"
    echo -e "  ${GREEN}4)${NC}  Abrir TODOS los puertos TCP y UDP (1-65535)"
    echo -e "  ${GREEN}5)${NC}  🔒 Configuración SEGURA (SSH, HTTP, HTTPS)"
    echo -e "  ${GREEN}6)${NC}  🔓 Desactivar firewall COMPLETAMENTE"
    echo -e "  ${GREEN}7)${NC}  Cerrar TODO y dejar solo SSH"
    echo -e "  ${GREEN}8)${NC}  Ver estado del firewall"
    echo -e "  ${GREEN}9)${NC}  Ver puertos abiertos"
    echo -e "  ${GREEN}10)${NC} Reiniciar firewall"
    echo -e "  ${GREEN}11)${NC} Salir"
    echo ""
    read -p "➜ Opción [1-11]: " OPCION
}

# ============================================================
# FUNCIONES PRINCIPALES
# ============================================================

instalar_ufw() {
    step "Instalando UFW..."
    apt-get update -qq
    apt-get install -y -qq ufw
    info "✅ UFW instalado correctamente"
}

abrir_tcp() {
    step "Abriendo TODOS los puertos TCP (1-65535)..."
    ufw allow 1:65535/tcp
    ufw reload
    info "✅ Puertos TCP abiertos"
}

abrir_udp() {
    step "Abriendo TODOS los puertos UDP (1-65535)..."
    ufw allow 1:65535/udp
    ufw reload
    info "✅ Puertos UDP abiertos"
}

abrir_tcp_udp() {
    step "Abriendo TODOS los puertos TCP y UDP (1-65535)..."
    ufw allow 1:65535/tcp
    ufw allow 1:65535/udp
    ufw reload
    info "✅ Puertos TCP y UDP abiertos"
}

configuracion_segura() {
    step "Configurando firewall SEGURO..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp      # SSH
    ufw allow 80/tcp      # HTTP
    ufw allow 443/tcp     # HTTPS
    ufw --force enable
    ufw reload
    info "✅ Configuración segura activada: SSH(22), HTTP(80), HTTPS(443)"
}

desactivar_completo() {
    warn "⚠️  DESACTIVANDO FIREWALL COMPLETAMENTE"
    step "Deteniendo UFW..."
    systemctl stop ufw
    systemctl disable ufw
    ufw --force disable
    
    step "Limpiando iptables..."
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t mangle -F
    
    step "Limpiando nftables..."
    nft flush ruleset 2>/dev/null || true
    
    info "✅ Firewall DESACTIVADO. TODOS los puertos están abiertos."
}

cerrar_solo_ssh() {
    step "Cerrando TODOS los puertos y dejando solo SSH..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw --force enable
    ufw reload
    info "✅ Solo puerto SSH (22) abierto"
}

ver_estado() {
    echo ""
    title
    header "   📋 ESTADO DEL FIREWALL"
    title
    echo ""
    echo -e "${BLUE}📌 Estado de UFW:${NC}"
    ufw status verbose
    echo ""
    echo -e "${BLUE}📌 Reglas de iptables (resumen):${NC}"
    iptables -L -n --line-numbers | head -25
    echo ""
}

ver_puertos() {
    echo ""
    title
    header "   📋 PUERTOS ABIERTOS"
    title
    echo ""
    echo -e "${BLUE}📌 Puertos permitidos en UFW:${NC}"
    ufw status | grep "ALLOW" || echo "  No hay puertos abiertos"
    echo ""
    echo -e "${BLUE}📌 Puertos en escucha (servicios activos):${NC}"
    ss -tulpn | grep LISTEN | column -t
    echo ""
}

reiniciar_firewall() {
    step "Reiniciando firewall..."
    ufw --force disable
    ufw --force enable
    ufw reload
    info "✅ Firewall reiniciado correctamente"
}

# ============================================================
# DETECTAR SISTEMA
# ============================================================
detect_os

# ============================================================
# BUCLE PRINCIPAL
# ============================================================
while true; do
    show_menu
    case $OPCION in
        1)
            instalar_ufw
            ;;
        2)
            abrir_tcp
            ver_puertos
            ;;
        3)
            abrir_udp
            ver_puertos
            ;;
        4)
            abrir_tcp_udp
            ver_puertos
            ;;
        5)
            configuracion_segura
            ver_puertos
            ;;
        6)
            desactivar_completo
            ver_puertos
            ;;
        7)
            cerrar_solo_ssh
            ver_puertos
            ;;
        8)
            ver_estado
            ;;
        9)
            ver_puertos
            ;;
        10)
            reiniciar_firewall
            ver_puertos
            ;;
        11)
            echo ""
            info "Saliendo del script..."
            exit 0
            ;;
        *)
            error "Opción inválida. Selecciona 1-11"
            ;;
    esac
    echo ""
    read -p "Presiona ENTER para continuar..."
done
