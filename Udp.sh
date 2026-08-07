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
# CREACIÓN AUTOMÁTICA DEL COMANDO 'menuUDP'
# ==========================================
setup_shortcut() {
    local TARGET="/usr/bin/menuUDP"
    local L1="/usr/local/bin/menuUdp"
    local L2="/usr/local/bin/menuUDP"
    local L3="/usr/bin/menuUdp"
    local RAW_URL="https://raw.githubusercontent.com/Yelsinml10/Udp/main/install.sh"

    local SRC="${BASH_SOURCE[0]:-$0}"
    if [ -f "$SRC" ]; then
        SRC=$(readlink -f "$SRC" 2>/dev/null || echo "$SRC")
    fi

    if [[ "$SRC" == "$TARGET" ]] || [[ "$SRC" == "$L1" ]] || [[ "$SRC" == "$L2" ]] || [[ "$SRC" == "$L3" ]]; then
        return 0
    fi

    rm -f "$TARGET" 2>/dev/null

    case "$SRC" in
        */bash|*/sh|*/dash|/dev/fd/*|/dev/stdin|"")
            curl -sSL "$RAW_URL" -o "$TARGET" 2>/dev/null || wget -qO "$TARGET" "$RAW_URL" 2>/dev/null
            ;;
        *)
            if [ -f "$SRC" ]; then
                cp "$SRC" "$TARGET" 2>/dev/null
            else
                curl -sSL "$RAW_URL" -o "$TARGET" 2>/dev/null || wget -qO "$TARGET" "$RAW_URL" 2>/dev/null
            fi
            ;;
    esac

    if [ -f "$TARGET" ]; then
        chmod +x "$TARGET" 2>/dev/null
        ln -sf "$TARGET" "$L1" 2>/dev/null
        ln -sf "$TARGET" "$L2" 2>/dev/null
        ln -sf "$TARGET" "$L3" 2>/dev/null
        hash -r 2>/dev/null
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n${RED}${BOLD}[ERROR] Este script debe ejecutarse como root (sudo).${NC}\n"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${CYAN}[*] Actualizando e instalando dependencias base...${NC}"
    apt-get update -y > /dev/null 2>&1
    apt-get install -y wget curl nano iptables ufw unzip openssl net-tools iproute2 jq socat cron python3 python3-pip git psmisc file awk build-essential > /dev/null 2>&1
}

get_public_ip() {
    PUBLIC_IP=$(curl -sS --max-time 5 ifconfig.me || curl -sS --max-time 5 api.ipify.org || echo "TU_IP_PUBLICA")
}

optimize_kernel() {
    echo -e "${CYAN}[*] Optimizando Stack de Red del Kernel (BBR + UDP Buffers)...${NC}"
    cat <<EOF > /etc/sysctl.d/99-hysteria.conf
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=8388608
net.core.wmem_default=8388608
net.core.netdev_max_backlog=10000
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system > /dev/null 2>&1
    echo -e "${GREEN}✔ Optimizaciones del Kernel aplicadas con éxito.${NC}"
}

generate_silent_cert() {
    mkdir -p /etc/hysteria
    if [ ! -f "/etc/hysteria/server.crt" ] || [ ! -f "/etc/hysteria/server.key" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /etc/hysteria/server.key \
            -out /etc/hysteria/server.crt \
            -days 3650 \
            -subj "/CN=localhost" > /dev/null 2>&1
    fi
}

# ==========================================
# MÓDULO: UDP-HYSTERIA (INSTALADOR FUNCIONAL)
# ==========================================
install_hysteria_bin() {
    local VER=$1
    echo -e "${CYAN}[*] Instalando Binario de Hysteria (Versión $VER)...${NC}"
    
    systemctl stop udp-hysteria 2>/dev/null
    fuser -k 36712/udp 2>/dev/null
    pkill -9 hysteria 2>/dev/null
    rm -f /usr/local/bin/hysteria
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) HY_ARCH="amd64" ;;
        aarch64|arm64|armv8*) HY_ARCH="arm64" ;;
        arm*|aarch32|armv7l|armv6l) HY_ARCH="arm" ;;
        i386|i686) HY_ARCH="386" ;;
        *) HY_ARCH="amd64" ;; 
    esac
    
    mkdir -p /etc/hysteria
    
    if [ "$VER" == "1" ]; then
        rm -f /etc/hysteria/config.yaml
        URLS=(
            "https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-${HY_ARCH}"
            "https://github.com/apernet/hysteria/releases/download/v1.3.4/hysteria-linux-${HY_ARCH}"
            "https://github.com/apernet/hysteria/releases/download/v1.3.3/hysteria-linux-${HY_ARCH}"
        )
    else
        rm -f /etc/hysteria/config.json
        LATEST=$(curl -sS https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v2.6.0")
        URLS=(
            "https://github.com/apernet/hysteria/releases/download/${LATEST}/hysteria-linux-${HY_ARCH}"
            "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_ARCH}"
        )
    fi
    
    SUCCESS=0
    for url in "${URLS[@]}"; do
        echo -e "${YELLOW}  ➔ Descargando binario...${NC}"
        curl -sSL -o /usr/local/bin/hysteria "$url" 2>/dev/null
        
        if [ ! -s "/usr/local/bin/hysteria" ]; then
            wget -qO /usr/local/bin/hysteria --no-check-certificate "$url" 2>/dev/null
        fi
        
        if [ -s "/usr/local/bin/hysteria" ]; then
            chmod +x /usr/local/bin/hysteria
            SUCCESS=1
            echo -e "${GREEN}✔ Binario de Hysteria V${VER} instalado correctamente (${HY_ARCH}).${NC}"
            INSTALLED_VER=$(/usr/local/bin/hysteria version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "v1.x")
            echo -e "${CYAN}  ➔ Versión instalada: ${GREEN}$INSTALLED_VER${NC}"
            break
        fi
        rm -f /usr/local/bin/hysteria
    done
    
    if [ "$SUCCESS" -eq 0 ]; then
        echo -e "${RED}[!] Error al descargar el binario de Hysteria. Verifique conexión.${NC}"
        return 1
    fi
    return 0
}

config_udp_hysteria() {
    clear
    get_public_ip
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            INSTALADOR UDP-HYSTERIA                    │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Hysteria Versión 1${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Hysteria Versión 2 (RECOMENDADO)${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [1-2]: ${NC}")" HY_OPT
    HY_OPT=${HY_OPT:-2}
    
    if [ "$HY_OPT" == "1" ]; then
        H_VER="1"
    else
        H_VER="2"
    fi
    
    clear
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa el puerto UDP [predeterminado 36712]: ${NC}")" H_PORT
    H_PORT=${H_PORT:-36712}
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa Rango Iptables [predeterminado 1:65535]: ${NC}")" H_RANGE
    H_RANGE=${H_RANGE:-1:65535}
    H_RANGE_IPT=$(echo "$H_RANGE" | tr '-' ':')
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa tu Dominio / SNI [predeterminado localhost]: ${NC}")" H_SNI
    H_SNI=${H_SNI:-localhost}

    H_OBFS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)
    
    AUTH_URI=""
    if [ "$H_VER" == "2" ]; then
        read -p "$(echo -e "${CYAN}❯ ${WHITE}Contraseña Hysteria V2 [Enter para aleatoria]: ${NC}")" H_PASS
        H_PASS=${H_PASS:-$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)}
        AUTH_BLOCK="auth:
  type: password
  password: \"$H_PASS\""
        AUTH_INFO="Password ($H_PASS)"
        AUTH_URI="${H_PASS}@"
    else
        AUTH_INFO="V1 - Sin autenticación"
        AUTH_URI=""
    fi

    echo -e "\n${YELLOW}Instalando y configurando...${NC}"
    install_dependencies
    install_hysteria_bin "$H_VER" || { read -p "Presione ENTER para volver"; return; }
    
    generate_silent_cert
    optimize_kernel

    if [ "$H_VER" == "1" ]; then
        HY_LINK="hysteria://${PUBLIC_IP}:${H_PORT}?protocol=udp&auth=&obfs=${H_OBFS}&upmbps=1000&downmbps=1000&insecure=1&peer=${H_SNI}#HysteriaV1_${PUBLIC_IP}"
        cat <<EOF > /etc/hysteria/config.json
{
  "listen": ":$H_PORT",
  "cert": "/etc/hysteria/server.crt",
  "key": "/etc/hysteria/server.key",
  "obfs": "$H_OBFS",
  "up": "1 Gbps",
  "down": "1 Gbps"
}
EOF
        CMD="/usr/local/bin/hysteria -c /etc/hysteria/config.json server"
    else
        HY_LINK="hysteria2://${AUTH_URI}${PUBLIC_IP}:${H_PORT}?insecure=1&sni=${H_SNI}&obfs=salamander&obfs-password=${H_OBFS}#HysteriaV2_${PUBLIC_IP}"
        cat <<EOF > /etc/hysteria/config.yaml
listen: :$H_PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

$AUTH_BLOCK

obfs:
  type: salamander
  salamander:
    password: "$H_OBFS"

bandwidth:
  up: 100 mbps
  down: 100 mbps
EOF
        CMD="/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml"
    fi

    cat <<EOF > /etc/hysteria/panel.conf
VERSION="$H_VER"
PORT="$H_PORT"
RANGE="$H_RANGE_IPT"
OBFS="$H_OBFS"
SNI="$H_SNI"
AUTH_INFO="$AUTH_INFO"
AUTH_URI="$AUTH_URI"
LINK="$HY_LINK"
EOF

    cat <<EOF > /etc/systemd/system/udp-hysteria.service
[Unit]
Description=UDP-Hysteria Server V${H_VER}
After=network.target

[Service]
Type=simple
User=root
ExecStart=$CMD
WorkingDirectory=/etc/hysteria
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hysteria-v${H_VER}

[Install]
WantedBy=multi-user.target
EOF

    systemctl stop udp-hysteria 2>/dev/null
    fuser -k $H_PORT/udp 2>/dev/null
    pkill -9 hysteria 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $H_PORT -j ACCEPT >/dev/null 2>&1
    ufw allow $H_PORT/udp >/dev/null 2>&1
    
    iptables -t nat -D PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT 2>/dev/null
    iptables -t nat -I PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT 2>/dev/null
    
    systemctl daemon-reload
    systemctl restart udp-hysteria
    systemctl enable udp-hysteria >/dev/null 2>&1
    
    clear
    echo -e "${GREEN}${BOLD}✔ Hysteria V${H_VER} configurado e iniciado con éxito.${NC}\n"
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│               ENLACE DE CONEXIÓN CLIENTE (URI)         │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "${YELLOW}${BOLD}$HY_LINK${NC}\n"
    read -p "Presione ENTER para continuar al menú..."
}

show_hysteria_link() {
    clear
    if [ -f "/etc/hysteria/panel.conf" ]; then
        source /etc/hysteria/panel.conf 2>/dev/null
        echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}${BOLD}│             ENLACE DE CONEXIÓN HYSTERIA (URI)          │${NC}"
        echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
        echo -e " ${PURPLE}${BOLD}Versión Hysteria :${NC} ${YELLOW}V$VERSION${NC}"
        echo -e " ${PURPLE}${BOLD}Puerto / SNI     :${NC} ${GREEN}$PORT / ${SNI:-localhost}${NC}"
        echo -e " ${PURPLE}${BOLD}Obfuscation (OBFS):${NC} ${CYAN}$OBFS${NC}"
        echo -e " ${PURPLE}${BOLD}Autenticación    :${NC} ${WHITE}$AUTH_INFO${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}${BOLD}${LINK:-Sin enlace disponible}${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}\n"
    else
        echo -e "${RED}[!] No hay una configuración activa de Hysteria.${NC}"
    fi
    read -p "Presione ENTER para volver..."
}

menu_udp_hysteria() {
    if [ ! -f "/etc/hysteria/panel.conf" ]; then
        config_udp_hysteria
        return
    fi
    
    source /etc/hysteria/panel.conf 2>/dev/null
    SNI=${SNI:-localhost}
    
    REAL_VER="Desconocida"
    if [ -x "/usr/local/bin/hysteria" ]; then
        REAL_VER=$(/usr/local/bin/hysteria version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "v1.x")
    fi
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│           ADMINISTRADOR UDP-HYSTERIA                   │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Versión Config  :${NC} ${YELLOW}${BOLD}Hysteria V$VERSION${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto UDP      :${NC} ${GREEN}${BOLD}$PORT${NC}"
    
    if systemctl is-active --quiet udp-hysteria; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}${BOLD}Ver Enlace / Link de Conexión (URI)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Reconfigurar UDP-Hysteria${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${RED}Desinstalar UDP-Hysteria${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-6]: ${NC}")" OPT
    
    case $OPT in
        1) show_hysteria_link; menu_udp_hysteria ;;
        2) config_udp_hysteria; menu_udp_hysteria ;;
        3) fuser -k $PORT/udp 2>/dev/null; pkill -9 hysteria 2>/dev/null; systemctl restart udp-hysteria; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1; menu_udp_hysteria ;;
        4) systemctl stop udp-hysteria; echo -e "${YELLOW}✔ Detenido.${NC}"; sleep 1; menu_udp_hysteria ;;
        5) journalctl -u udp-hysteria -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_udp_hysteria ;;
        6) 
           systemctl stop udp-hysteria 2>/dev/null
           systemctl disable udp-hysteria 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 hysteria 2>/dev/null
           rm -rf /etc/hysteria /etc/systemd/system/udp-hysteria.service
           rm -f /usr/local/bin/hysteria
           systemctl daemon-reload
           echo -e "${GREEN}✔ Desinstalado completamente.${NC}"
           sleep 2
           menu_main ;;
        0) menu_main ;;
        *) menu_udp_hysteria ;;
    esac
}

# ==========================================
# MÓDULO: UDP CUSTOM
# ==========================================
install_udp_bin() {
    echo -e "${CYAN}[*] Verificando e instalando binario UDP Custom...${NC}"
    
    ARCH=$(uname -m)
    mkdir -p /etc/udp-custom
    
    if [[ "$ARCH" == *"arm"* ]] || [[ "$ARCH" == *"aarch"* ]]; then
        echo -e "${YELLOW}  ➔ Arquitectura ARM detectada (${ARCH})${NC}"
        URLS=("https://raw.githubusercontent.com/prjkt-nv404/UDP-Custom-Installer-arm64/main/udpc-arm64")
    else
        echo -e "${YELLOW}  ➔ Arquitectura AMD64 detectada (${ARCH})${NC}"
        URLS=("https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64")
    fi

    SUCCESS=0
    for url in "${URLS[@]}"; do
        echo -e "${CYAN}  ➔ Descargando desde: $url${NC}"
        rm -f /usr/local/bin/udp-custom
        curl -sSL -o /usr/local/bin/udp-custom "$url" 2>/dev/null || wget -qO /usr/local/bin/udp-custom --no-check-certificate "$url" 2>/dev/null
        
        if [ -s "/usr/local/bin/udp-custom" ]; then
            chmod +x /usr/local/bin/udp-custom
            SUCCESS=1
            echo -e "${GREEN}✔ UDP Custom instalado con éxito.${NC}"
            break
        fi
    done
    
    if [ "$SUCCESS" -eq 0 ]; then
        echo -e "${RED}[!] Error al instalar UDP Custom.${NC}"
        return 1
    fi
    return 0
}

config_udp() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            INSTALADOR UDP CUSTOM                       │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}UDP Custom SIN TLS (UDP plano)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}UDP Custom CON TLS/DTLS (Recomendado)${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [1-2]: ${NC}")" TLS_OPT
    TLS_OPT=${TLS_OPT:-2}
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Puerto UDP [predeterminado 36712]: ${NC}")" U_PORT
    U_PORT=${U_PORT:-36712}
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa el rango de puertos [predeterminado 1-65535]: ${NC}")" U_RANGE
    U_RANGE=${U_RANGE:-1-65535}
    U_RANGE_IPT=$(echo "$U_RANGE" | tr '-' ':')

    install_dependencies
    install_udp_bin || { read -p "Presione ENTER para volver"; return; }

    mkdir -p /etc/udp-custom
    CERT_CN=$(curl -sS ifconfig.me 2>/dev/null || echo "localhost")
    
    if [ "$TLS_OPT" == "2" ]; then
        mkdir -p /etc/udp-custom/certs
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /etc/udp-custom/certs/server.key \
            -out /etc/udp-custom/certs/server.crt \
            -days 3650 \
            -subj "/CN=$CERT_CN" > /dev/null 2>&1
        
        cat <<EOF > /etc/udp-custom/config.json
{
  "listen": ":$U_PORT",
  "auth": {
    "mode": "passwords"
  },
  "tls": {
    "cert": "/etc/udp-custom/certs/server.crt",
    "key": "/etc/udp-custom/certs/server.key"
  },
  "stream_buffer": 33554432,
  "receive_buffer": 8388608,
  "exclude_ports": [53, 5300]
}
EOF
        TLS_STATUS="enabled"
    else
        cat <<EOF > /etc/udp-custom/config.json
{
  "listen": ":$U_PORT",
  "auth": {
    "mode": "passwords"
  },
  "stream_buffer": 33554432,
  "receive_buffer": 8388608,
  "exclude_ports": [53, 5300]
}
EOF
        TLS_STATUS="disabled"
    fi
    
    cat <<EOF > /etc/udp-custom/panel.conf
TLS=$TLS_STATUS
PORT=$U_PORT
RANGE=$U_RANGE_IPT
CERT_CN=$CERT_CN
EOF

    cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/udp-custom
ExecStart=/usr/local/bin/udp-custom server -config /etc/udp-custom/config.json
ExecStartPost=/bin/bash -c 'iptables -t nat -I PREROUTING -p udp -m udp --dport $U_RANGE_IPT -j REDIRECT --to-ports $U_PORT || true'
ExecStopPost=/bin/bash -c 'iptables -t nat -D PREROUTING -p udp -m udp --dport $U_RANGE_IPT -j REDIRECT --to-ports $U_PORT || true'
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

    systemctl stop udp-custom 2>/dev/null
    fuser -k $U_PORT/udp 2>/dev/null
    pkill -9 udp-custom 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $U_PORT -j ACCEPT 2>/dev/null
    ufw allow $U_PORT/udp 2>/dev/null

    systemctl daemon-reload
    systemctl enable udp-custom > /dev/null 2>&1
    systemctl restart udp-custom
    
    echo -e "\n${GREEN}✔ UDP Custom configurado con éxito en el puerto $U_PORT.${NC}"
    read -p "Presione ENTER para continuar..."
}

menu_udp_custom() {
    if [ ! -f "/etc/udp-custom/panel.conf" ]; then
        config_udp
        return
    fi
    
    source /etc/udp-custom/panel.conf 2>/dev/null
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│           ADMINISTRADOR UDP CUSTOM                     │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto UDP      :${NC} ${GREEN}${BOLD}$PORT${NC}"
    echo -e " ${PURPLE}${BOLD}Rango IPTables  :${NC} ${CYAN}${BOLD}$RANGE > $PORT${NC}"
    echo -e " ${PURPLE}${BOLD}TLS/DTLS        :${NC} ${GREEN}${BOLD}$TLS${NC}"
    
    if systemctl is-active --quiet udp-custom; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Reconfigurar UDP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${RED}Desinstalar UDP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-5]: ${NC}")" OPT
    
    case $OPT in
        1) config_udp; menu_udp_custom ;;
        2) fuser -k $PORT/udp 2>/dev/null; pkill -9 udp-custom 2>/dev/null; systemctl restart udp-custom; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1; menu_udp_custom ;;
        3) systemctl stop udp-custom; echo -e "${YELLOW}✔ Detenido.${NC}"; sleep 1; menu_udp_custom ;;
        4) journalctl -u udp-custom -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_udp_custom ;;
        5) 
           systemctl stop udp-custom 2>/dev/null
           systemctl disable udp-custom 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 udp-custom 2>/dev/null
           rm -rf /etc/udp-custom /etc/systemd/system/udp-custom.service
           rm -f /usr/local/bin/udp-custom
           systemctl daemon-reload
           echo -e "${GREEN}✔ Desinstalado completamente.${NC}"
           sleep 2
           menu_main ;;
        0) menu_main ;;
        *) menu_udp_custom ;;
    esac
}

# ==========================================
# MÓDULO: ZI VPN
# ==========================================
install_zivpn_bin() {
    echo -e "${CYAN}[*] Verificando e instalando binario de ZI VPN...${NC}"
    
    systemctl stop zivpn 2>/dev/null
    fuser -k 5667/udp 2>/dev/null
    pkill -9 zivpn 2>/dev/null
    rm -f /usr/local/bin/zivpn
    
    ARCH=$(uname -m)
    mkdir -p /etc/zivpn
    
    case "$ARCH" in
        x86_64|amd64) ZI_ARCH="amd64" ;;
        aarch64|arm64|armv8*) ZI_ARCH="arm64" ;;
        arm*|aarch32|armv7l|armv6l) ZI_ARCH="arm" ;;
        *) ZI_ARCH="amd64" ;; 
    esac

    URLS=(
        "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-${ZI_ARCH}"
        "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/udp-zivpn-linux-${ZI_ARCH}"
    )

    SUCCESS=0
    for url in "${URLS[@]}"; do
        echo -e "${YELLOW}  ➔ Descargando binario ZI VPN para ${ZI_ARCH}...${NC}"
        curl -sSL -o /usr/local/bin/zivpn "$url" 2>/dev/null || wget -qO /usr/local/bin/zivpn --no-check-certificate "$url" 2>/dev/null

        if [ -s "/usr/local/bin/zivpn" ]; then
            chmod +x /usr/local/bin/zivpn
            SUCCESS=1
            echo -e "${GREEN}✔ Binario ZI VPN instalado con éxito (${ZI_ARCH}).${NC}"
            break
        fi
        rm -f /usr/local/bin/zivpn
    done

    if [ "$SUCCESS" -eq 0 ]; then
        echo -e "${RED}[!] Error al instalar ZI VPN.${NC}"
        return 1
    fi
    return 0
}

config_zivpn() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            INSTALADOR ZI VPN                           │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Puerto ZI VPN [predeterminado 5667]: ${NC}")" Z_PORT
    Z_PORT=${Z_PORT:-5667}

    read -p "$(echo -e "${CYAN}❯ ${WHITE}OBFS de ZI VPN [predeterminado zivpn]: ${NC}")" Z_OBFS
    Z_OBFS=${Z_OBFS:-zivpn}

    read -p "$(echo -e "${CYAN}❯ ${WHITE}Contraseña de ZI VPN [predeterminado zi]: ${NC}")" Z_PASS
    Z_PASS=${Z_PASS:-zi}

    install_dependencies
    install_zivpn_bin || { read -p "Presione ENTER para volver"; return; }

    if [ ! -f "/etc/zivpn/zivpn.crt" ] || [ ! -f "/etc/zivpn/zivpn.key" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /etc/zivpn/zivpn.key \
            -out /etc/zivpn/zivpn.crt \
            -days 3650 \
            -subj "/CN=zivpn" > /dev/null 2>&1
    fi

    cat <<EOF > /etc/zivpn/config.json
{
  "listen": ":$Z_PORT",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "$Z_OBFS",
  "auth": {
    "mode": "passwords",
    "config": [
      "$Z_PASS"
    ]
  }
}
EOF

    cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZI VPN Server UDP
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zivpn

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF > /etc/zivpn/panel.conf
PORT="$Z_PORT"
OBFS="$Z_OBFS"
PASS="$Z_PASS"
EOF

    systemctl stop zivpn 2>/dev/null
    fuser -k $Z_PORT/udp 2>/dev/null
    pkill -9 zivpn 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $Z_PORT -j ACCEPT > /dev/null 2>&1
    ufw allow $Z_PORT/udp > /dev/null 2>&1

    systemctl daemon-reload
    systemctl enable zivpn > /dev/null 2>&1
    systemctl restart zivpn

    echo -e "\n${GREEN}✔ ZI VPN configurado en el puerto $Z_PORT (OBFS: $Z_OBFS | PASS: $Z_PASS)${NC}"
    read -p "Presione ENTER para continuar..."
}

menu_zivpn() {
    if [ ! -f "/etc/zivpn/panel.conf" ]; then
        config_zivpn
        return
    fi
    
    source /etc/zivpn/panel.conf 2>/dev/null
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│           ADMINISTRADOR ZI VPN                         │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto UDP      :${NC} ${GREEN}${BOLD}$PORT${NC}"
    echo -e " ${PURPLE}${BOLD}OBFS            :${NC} ${YELLOW}${BOLD}$OBFS${NC}"
    echo -e " ${PURPLE}${BOLD}Contraseña PASS :${NC} ${GREEN}${BOLD}$PASS${NC}"
    
    if systemctl is-active --quiet zivpn; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Reconfigurar ZI VPN${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${RED}Desinstalar ZI VPN${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-5]: ${NC}")" OPT
    
    case $OPT in
        1) config_zivpn; menu_zivpn ;;
        2) fuser -k $PORT/udp 2>/dev/null; pkill -9 zivpn 2>/dev/null; systemctl restart zivpn; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1; menu_zivpn ;;
        3) systemctl stop zivpn; echo -e "${YELLOW}✔ Detenido.${NC}"; sleep 1; menu_zivpn ;;
        4) journalctl -u zivpn -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_zivpn ;;
        5) 
           systemctl stop zivpn 2>/dev/null
           systemctl disable zivpn 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 zivpn 2>/dev/null
           rm -rf /etc/zivpn /etc/systemd/system/zivpn.service
           rm -f /usr/local/bin/zivpn
           systemctl daemon-reload
           echo -e "${GREEN}✔ Desinstalado completamente.${NC}"
           sleep 2
           menu_main ;;
        0) menu_main ;;
        *) menu_zivpn ;;
    esac
}

# ==========================================
# MENÚ PRINCIPAL
# ==========================================
menu_main() {
    clear
    setup_shortcut
    get_public_ip
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│       ADMINISTRADOR DE SERVICIOS UDP VIP               │${NC}"
    echo -e "${CYAN}${BOLD}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${WHITE}${BOLD}• Sistema   :${NC} ${CYAN}${BOLD}$(uname -s) $(uname -m)${NC}"
    echo -e "  ${WHITE}${BOLD}• IP Pública:${NC} ${YELLOW}${BOLD}$PUBLIC_IP${NC}"
    echo -e "  ${WHITE}${BOLD}• Comando   :${NC} ${GREEN}${BOLD}menuUDP${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Administrador UDP-Hysteria (V1/V2)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Administrador UDP Custom (Con Rango y TLS)${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Administrador ZI VPN Engine${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${RED}${BOLD}Salir del Panel UDP${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}\n"
    
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una opción [0-3]: ${NC}")" opt
    case $opt in
        1) menu_udp_hysteria ;;
        2) menu_udp_custom ;;
        3) menu_zivpn ;;
        0) clear; echo -e "${GREEN}Saliendo de menuUDP...${NC}"; exit 0 ;;
        *) menu_main ;;
    esac
}

# ==========================================
# INICIO DEL SCRIPT
# ==========================================
check_root
setup_shortcut
menu_main
