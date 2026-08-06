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
# FUNCIONES PRINCIPALES
# ==========================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n${RED}${BOLD}[ERROR] Ejecutar como root (sudo)${NC}\n"
        exit 1
    fi
}

# ==========================================
# INSTALAR HERRAMIENTAS DE RED
# ==========================================

install_network_tools() {
    echo -e "${CYAN}[*] Instalando herramientas de red...${NC}"
    apt-get update -y > /dev/null 2>&1
    apt-get install -y iputils-ping dnsutils curl wget > /dev/null 2>&1
    echo -e "${GREEN}✔ Herramientas instaladas${NC}"
}

# ==========================================
# ARREGLAR DNS
# ==========================================

fix_dns() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│     ARREGLAR DNS                                       │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e "${YELLOW}[*] Arreglando DNS...${NC}"
    
    # Instalar herramientas primero
    install_network_tools
    
    # 1. Configurar /etc/systemd/resolved.conf
    echo -e "${CYAN}[*] Configurando systemd-resolved...${NC}"
    cat <<EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 94.140.14.14 94.140.15.15
FallbackDNS=9.9.9.9 149.112.112.112
DNSSEC=no
DNSOverTLS=no
DNSStubListener=yes
ReadEtcHosts=yes
EOF
    
    # 2. Reiniciar servicio DNS
    echo -e "${CYAN}[*] Reiniciando systemd-resolved...${NC}"
    systemctl restart systemd-resolved 2>/dev/null
    systemctl enable systemd-resolved 2>/dev/null
    
    # 3. Forzar DNS en /etc/resolv.conf
    echo -e "${CYAN}[*] Configurando /etc/resolv.conf...${NC}"
    cat <<EOF > /etc/resolv.conf
# DNS Principales
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1

# DNS AdGuard (Con bloqueo de anuncios)
nameserver 94.140.14.14
nameserver 94.140.15.15

# DNS Quad9 (Seguridad)
nameserver 9.9.9.9
nameserver 149.112.112.112
EOF
    
    # 4. Proteger resolv.conf
    echo -e "${CYAN}[*] Protegiendo /etc/resolv.conf...${NC}"
    chattr +i /etc/resolv.conf 2>/dev/null
    
    # 5. Agregar hosts para GitHub
    echo -e "${CYAN}[*] Configurando /etc/hosts para GitHub...${NC}"
    grep -q "github.com" /etc/hosts || cat <<EOF >> /etc/hosts
140.82.121.3 github.com
140.82.121.3 api.github.com
185.199.108.133 raw.githubusercontent.com
185.199.109.133 raw.githubusercontent.com
185.199.110.133 raw.githubusercontent.com
185.199.111.133 raw.githubusercontent.com
EOF
    
    # 6. Probar DNS
    echo -e "${CYAN}[*] Probando DNS...${NC}"
    sleep 1
    
    # Probar google.com
    if ping -c 1 google.com > /dev/null 2>&1; then
        echo -e "${GREEN}✔ google.com → resuelto${NC}"
    else
        echo -e "${YELLOW}⚠ google.com → NO resuelve${NC}"
    fi
    
    # Probar api.github.com
    if ping -c 1 api.github.com > /dev/null 2>&1; then
        echo -e "${GREEN}✔ api.github.com → resuelto${NC}"
    else
        echo -e "${YELLOW}⚠ api.github.com → NO resuelve (usando hosts)${NC}"
    fi
    
    # Probar raw.githubusercontent.com
    if ping -c 1 raw.githubusercontent.com > /dev/null 2>&1; then
        echo -e "${GREEN}✔ raw.githubusercontent.com → resuelto${NC}"
    else
        echo -e "${YELLOW}⚠ raw.githubusercontent.com → NO resuelve (usando hosts)${NC}"
    fi
    
    # Probar AdGuard DNS
    echo -e "${CYAN}[*] Probando DNS de AdGuard...${NC}"
    if nslookup google.com 94.140.14.14 > /dev/null 2>&1; then
        echo -e "${GREEN}✔ AdGuard DNS (94.140.14.14) → funcionando${NC}"
    else
        echo -e "${YELLOW}⚠ AdGuard DNS → no responde${NC}"
    fi
    
    echo -e "\n${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}     ✅ DNS ARREGLADO                                     ${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BOLD}${WHITE}📋 DNS CONFIGURADOS:${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}🔵 Google DNS:${NC}"
    echo -e " ${GREEN}• 8.8.8.8${NC}   (Primary)"
    echo -e " ${GREEN}• 8.8.4.4${NC}   (Secondary)"
    echo ""
    echo -e "${BOLD}${CYAN}🔵 Cloudflare DNS:${NC}"
    echo -e " ${GREEN}• 1.1.1.1${NC}   (Primary)"
    echo -e " ${GREEN}• 1.0.0.1${NC}   (Secondary)"
    echo ""
    echo -e "${BOLD}${CYAN}🛡️ AdGuard DNS (Con bloqueo de anuncios):${NC}"
    echo -e " ${GREEN}• 94.140.14.14${NC}  (Primary - Con filtros)"
    echo -e " ${GREEN}• 94.140.15.15${NC}  (Secondary - Con filtros)"
    echo ""
    echo -e "${BOLD}${CYAN}🔵 Quad9 DNS (Seguridad):${NC}"
    echo -e " ${GREEN}• 9.9.9.9${NC}      (Primary)"
    echo -e " ${GREEN}• 149.112.112.112${NC} (Secondary)"
    echo ""
    
    echo -e "${BOLD}${CYAN}🧪 PRUEBA RÁPIDA:${NC}"
    echo -e " ${WHITE}nslookup google.com${NC}"
    echo -e " ${WHITE}nslookup api.github.com${NC}"
    echo -e " ${WHITE}curl -I https://api.github.com${NC}"
    echo -e " ${WHITE}nslookup google.com 94.140.14.14${NC}  → Probar AdGuard"
    echo ""
    
    read -p "Presione ENTER para continuar..."
}

# ==========================================
# PROBAR DNS
# ==========================================

test_dns() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│     PROBAR DNS                                        │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    # Instalar herramientas si no están
    if ! command -v ping &> /dev/null; then
        install_network_tools
    fi
    
    echo -e "${BOLD}${CYAN}🧪 Probando DNS...${NC}\n"
    
    # Google
    echo -e "${WHITE}google.com:${NC}"
    if ping -c 2 google.com > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Resuelve correctamente${NC}"
        ping -c 2 google.com | head -2
    else
        echo -e "  ${RED}❌ No resuelve${NC}"
    fi
    
    echo ""
    
    # api.github.com
    echo -e "${WHITE}api.github.com:${NC}"
    if ping -c 2 api.github.com > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Resuelve correctamente${NC}"
        ping -c 2 api.github.com | head -2
    else
        echo -e "  ${YELLOW}⚠ No resuelve (usando /etc/hosts)${NC}"
    fi
    
    echo ""
    
    # raw.githubusercontent.com
    echo -e "${WHITE}raw.githubusercontent.com:${NC}"
    if ping -c 2 raw.githubusercontent.com > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Resuelve correctamente${NC}"
        ping -c 2 raw.githubusercontent.com | head -2
    else
        echo -e "  ${YELLOW}⚠ No resuelve (usando /etc/hosts)${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}${CYAN}📋 Resolución con nslookup:${NC}"
    echo -e "${WHITE}google.com:${NC}"
    nslookup google.com 2>&1 | grep -E "Address|Server" | head -3
    
    echo -e "\n${WHITE}api.github.com:${NC}"
    nslookup api.github.com 2>&1 | grep -E "Address|Server" | head -3
    
    echo ""
    echo -e "${BOLD}${CYAN}🛡️ Probando AdGuard DNS (94.140.14.14):${NC}"
    if nslookup google.com 94.140.14.14 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ AdGuard DNS funcionando${NC}"
        nslookup google.com 94.140.14.14 2>&1 | grep -E "Address|Server" | head -3
    else
        echo -e "  ${RED}❌ AdGuard DNS no responde${NC}"
    fi
    
    echo ""
    read -p "Presione ENTER para volver..."
}

# ==========================================
# VER CONFIGURACIÓN
# ==========================================

show_config() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│     CONFIGURACIÓN ACTUAL                               │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e "${BOLD}${WHITE}📋 /etc/resolv.conf:${NC}"
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${NC}"
    cat /etc/resolv.conf
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${NC}\n"
    
    echo -e "${BOLD}${WHITE}📋 /etc/systemd/resolved.conf:${NC}"
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${NC}"
    cat /etc/systemd/resolved.conf | grep -v "^#" | grep -v "^$"
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${NC}\n"
    
    echo -e "${BOLD}${WHITE}📋 /etc/hosts (entradas GitHub):${NC}"
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${NC}"
    grep -E "github|raw.githubusercontent" /etc/hosts 2>/dev/null || echo "No hay entradas"
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${NC}\n"
    
    echo -e "${BOLD}${WHITE}📋 Servicio systemd-resolved:${NC}"
    systemctl status systemd-resolved --no-pager | grep -E "Active|Main PID"
    
    echo ""
    read -p "Presione ENTER para volver..."
}

# ==========================================
# MENÚ PRINCIPAL
# ==========================================

menu() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│     ARREGLAR DNS                                       │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}Arreglar DNS y probar${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Ver configuración actual${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Probar resolución de nombres${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Probar AdGuard DNS${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${RED}Salir${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Opción: ${NC}")" opt
    
    case $opt in
        1) fix_dns; menu ;;
        2) show_config; menu ;;
        3) test_dns; menu ;;
        4)
            echo -e "\n${BOLD}${CYAN}🛡️ Probando AdGuard DNS...${NC}\n"
            if nslookup google.com 94.140.14.14 > /dev/null 2>&1; then
                echo -e "${GREEN}✅ AdGuard DNS (94.140.14.14) funcionando${NC}"
                echo -e "\n${WHITE}Resolviendo google.com con AdGuard:${NC}"
                nslookup google.com 94.140.14.14 2>&1 | grep -E "Address|Server" | head -3
            else
                echo -e "${RED}❌ AdGuard DNS no responde${NC}"
            fi
            echo ""
            read -p "ENTER para volver..."
            menu
            ;;
        0) clear; echo -e "${GREEN}Saliendo...${NC}"; exit 0 ;;
        *) menu ;;
    esac
}

# ==========================================
# INICIO
# ==========================================

check_root
menu
