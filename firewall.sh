#!/bin/bash

# ==========================================
# PALETA DE COLORES ANSI Y ESTILOS
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ==========================================
# ACCESO DIRECTO GLOBAL 'firewall'
# ==========================================
setup_shortcut() {
    local TARGET="/usr/local/bin/firewall.sh"
    local LINK="/usr/bin/firewall"
    local SRC="${BASH_SOURCE[0]:-$0}"

    if [ -f "$SRC" ]; then
        SRC=$(readlink -f "$SRC" 2>/dev/null || echo "$SRC")
    fi

    if [[ "$SRC" != "$TARGET" && -f "$SRC" ]]; then
        cp "$SRC" "$TARGET" 2>/dev/null
        chmod +x "$TARGET" 2>/dev/null
    fi

    chmod +x "$TARGET" 2>/dev/null
    ln -sf "$TARGET" "$LINK" 2>/dev/null
    grep -q "alias firewall=" /root/.bashrc 2>/dev/null || echo "alias firewall='/usr/local/bin/firewall.sh'" >> /root/.bashrc
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n${RED}${BOLD}[ERROR] Este script debe ejecutarse como root:${NC} ${YELLOW}sudo bash $0${NC}\n"
        exit 1
    fi
}

instalar_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo -e "${CYAN}[*] UFW no está instalado. Instalando...${NC}"
        apt-get update -qq >/dev/null 2>&1 || yum update -y >/dev/null 2>&1
        apt-get install -y ufw -qq >/dev/null 2>&1 || yum install -y ufw -qq >/dev/null 2>&1
        echo -e "${GREEN}✔ UFW instalado correctamente.${NC}"
    fi
}

# ==========================================
# FUNCIONES PRINCIPALES
# ==========================================

abrir_tcp() {
    echo -e "\n${YELLOW}${BOLD}=== ABRIR TODOS LOS PUERTOS TCP (1-65535) ===${NC}"
    instalar_ufw

    echo -e "${CYAN}Habilitando UFW y permitiendo tráfico TCP...${NC}"
    sudo ufw default allow outgoing >/dev/null 2>&1
    sudo ufw allow 1:65535/tcp >/dev/null 2>&1
    
    sudo iptables -A INPUT -p tcp --dport 1:65535 -j ACCEPT 2>/dev/null
    
    sudo ufw --force enable >/dev/null 2>&1
    sudo ufw reload >/dev/null 2>&1

    echo -e "${GREEN}${BOLD}✔ TODOS los puertos TCP (1-65535) han sido ABIERTOS con éxito.${NC}\n"
    read -p "Presiona ENTER para continuar..."
}

abrir_udp() {
    echo -e "\n${YELLOW}${BOLD}=== ABRIR TODOS LOS PUERTOS UDP (1-65535) ===${NC}"
    instalar_ufw

    echo -e "${CYAN}Habilitando UFW y permitiendo tráfico UDP...${NC}"
    sudo ufw default allow outgoing >/dev/null 2>&1
    sudo ufw allow 1:65535/udp >/dev/null 2>&1
    
    sudo iptables -A INPUT -p udp --dport 1:65535 -j ACCEPT 2>/dev/null
    
    sudo ufw --force enable >/dev/null 2>&1
    sudo ufw reload >/dev/null 2>&1

    echo -e "${GREEN}${BOLD}✔ TODOS los puertos UDP (1-65535) han sido ABIERTOS con éxito.${NC}\n"
    read -p "Presiona ENTER para continuar..."
}

reiniciar_servicio() {
    echo -e "\n${YELLOW}${BOLD}=== REINICIAR SERVICIO DE FIREWALL ===${NC}"
    
    if command -v ufw &> /dev/null; then
        echo -e "${CYAN}Reiniciando UFW...${NC}"
        sudo systemctl restart ufw >/dev/null 2>&1
        sudo ufw reload >/dev/null 2>&1
        echo -e "${GREEN}${BOLD}✔ Servicio UFW reiniciado correctamente.${NC}\n"
    else
        echo -e "${RED}✘ UFW no está instalado en el sistema.${NC}\n"
    fi
    read -p "Presiona ENTER para continuar..."
}

desinstalar_firewall() {
    echo -e "\n${RED}${BOLD}=== DESINSTALAR FIREWALL COMPLETAMENTE ===${NC}"
    read -p "¿Está seguro de eliminar UFW y limpiar todas las reglas del firewall? (s/N): " confirm

    if [[ "$confirm" =~ ^[sS]$ ]]; then
        echo -e "${YELLOW}Deteniendo y deshabilitando UFW...${NC}"
        sudo ufw --force reset >/dev/null 2>&1
        sudo ufw --force disable >/dev/null 2>&1
        sudo systemctl stop ufw >/dev/null 2>&1
        sudo systemctl disable ufw >/dev/null 2>&1

        echo -e "${YELLOW}Desinstalando paquete UFW...${NC}"
        sudo apt-get purge -y ufw >/dev/null 2>&1 || sudo yum remove -y ufw >/dev/null 2>&1

        echo -e "${YELLOW}Limpiando reglas de iptables y nftables...${NC}"
        sudo iptables -P INPUT ACCEPT
        sudo iptables -P OUTPUT ACCEPT
        sudo iptables -P FORWARD ACCEPT
        sudo iptables -F
        sudo iptables -X
        sudo iptables -t nat -F
        sudo iptables -t mangle -F
        sudo nft flush ruleset 2>/dev/null || true

        echo -e "\n${GREEN}${BOLD}✔ Firewall desinstalado y reglas eliminadas. Todos los puertos están abiertos.${NC}\n"
        read -p "Presiona ENTER para salir..."
        exit 0
    else
        echo -e "${GREEN}Desinstalación cancelada.${NC}\n"
        sleep 1
    fi
}

header() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│       ADMINISTRADOR DE FIREWALL UFW / IPTABLES         │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    
    if command -v ufw &>/dev/null && systemctl is-active --quiet ufw 2>/dev/null; then
        echo -e " ${PURPLE}${BOLD}Estado Firewall :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Firewall :${NC} ${RED}[INACTIVO / STOPPED]${NC}"
    fi
    echo -e " ${PURPLE}${BOLD}Comando Directo :${NC} ${GREEN}${BOLD}firewall${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
}

# ==========================================
# BUCLE DEL MENÚ
# ==========================================
check_root
setup_shortcut

while true; do
    header
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Abrir TODOS los Puertos TCP (1-65535)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Abrir TODOS los Puertos UDP (1-65535)${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}Reiniciar Servicio de Firewall${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${RED}Desinstalar Firewall Completamente${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una opción [0-4]: ${NC}")" op

    case $op in
        1) abrir_tcp ;;
        2) abrir_udp ;;
        3) reiniciar_servicio ;;
        4) desinstalar_firewall ;;
        0) echo -e "\n${GREEN}Saliendo del panel de Firewall...${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
done
