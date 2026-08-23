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
    apt-get install -y wget curl nano iptables unzip openssl net-tools iproute2 jq socat cron python3 python3-pip git psmisc file gawk build-essential perl libcrypt-passwdmd5-perl > /dev/null 2>&1
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

create_auth_script() {
    mkdir -p /etc/hysteria
    cat <<'EOF_AUTH' > /etc/hysteria/auth.sh
#!/bin/bash
P="$2"
[ -z "$P" ] && P="$1"
[ -z "$P" ] && exit 1

if [[ "$P" == *":"* ]]; then
    U="${P%%:*}"
    PASS="${P#*:}"
else
    U="$P"
    PASS="$P"
fi

if ! id "$U" &>/dev/null; then
    exit 1
fi

EXP_DATE=$(LC_ALL=C chage -l "$U" 2>/dev/null | grep -i "Account expires" | cut -d: -f2 | xargs)
if [ "$EXP_DATE" != "never" ] && [ -n "$EXP_DATE" ]; then
    EXP_SEC=$(date -d "$EXP_DATE" +%s 2>/dev/null)
    NOW_SEC=$(date +%s)
    if [ -n "$EXP_SEC" ] && [ "$NOW_SEC" -gt "$EXP_SEC" ]; then
        exit 1
    fi
fi

H=$(awk -F: -v u="$U" '$1==u {print $2}' /etc/shadow)
[ -z "$H" ] && exit 1
[[ "$H" == "*" || "$H" == "!"* ]] && exit 1

perl -e 'exit(crypt($ARGV[0], $ARGV[1]) eq $ARGV[1] ? 0 : 1)' "$PASS" "$H" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "$U"
    exit 0
fi

exit 1
EOF_AUTH
    chmod +x /etc/hysteria/auth.sh
}

# ==========================================
# MÓDULO: UDP-HYSTERIA (V1 Y V2)
# ==========================================
install_hysteria_bin() {
    local VER=$1
    echo -e "${CYAN}[*] Instalando Binario de Hysteria (Versión $VER)...${NC}"
    
    systemctl stop udp-hysteria 2>/dev/null
    pkill -9 hysteria 2>/dev/null
    rm -f /usr/local/bin/hysteria /usr/bin/hysteria
    
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
        URL="https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-${HY_ARCH}"
        curl -sSL -o /usr/local/bin/hysteria "$URL" 2>/dev/null || wget -qO /usr/local/bin/hysteria "$URL" 2>/dev/null
    else
        rm -f /etc/hysteria/config.json
        curl -fsSL https://get.hy2.sh/ | bash > /dev/null 2>&1
        if [ -f "/usr/bin/hysteria" ]; then
            cp -f /usr/bin/hysteria /usr/local/bin/hysteria 2>/dev/null
        fi
    fi
    
    if [ -s "/usr/local/bin/hysteria" ]; then
        chmod +x /usr/local/bin/hysteria
        echo -e "${GREEN}✔ Binario de Hysteria instalado correctamente (${HY_ARCH}).${NC}"
        INSTALLED_VER=$(/usr/local/bin/hysteria version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "v${VER}.x")
        echo -e "${CYAN}  ➔ Versión detectada: ${GREEN}$INSTALLED_VER${NC}"
        return 0
    else
        echo -e "${RED}[!] Error al descargar el binario de Hysteria.${NC}"
        return 1
    fi
}

show_hysteria_info() {
    clear
    get_public_ip
    if [ -f "/etc/hysteria/panel.conf" ]; then
        source /etc/hysteria/panel.conf 2>/dev/null
        echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}${BOLD}│       DATOS DE CONEXIÓN - UDP-HYSTERIA V${VERSION}              │${NC}"
        echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
        echo -e " ${PURPLE}${BOLD}• Protocolo           :${NC} ${YELLOW}${BOLD}Hysteria V${VERSION}${NC}"
        echo -e " ${PURPLE}${BOLD}• Host / IP Servidor  :${NC} ${GREEN}${BOLD}${PUBLIC_IP}${NC}"
        echo -e " ${PURPLE}${BOLD}• Puerto Principal UDP:${NC} ${WHITE}${BOLD}${PORT}${NC}"
        echo -e " ${PURPLE}${BOLD}• Rango IPTables      :${NC} ${CYAN}${BOLD}${RANGE} -> ${PORT}${NC}"
        echo -e " ${PURPLE}${BOLD}• SNI / Server Name   :${NC} ${WHITE}${BOLD}${SNI:-localhost}${NC}"
        echo -e " ${PURPLE}${BOLD}• Clave Ofuscación    :${NC} ${YELLOW}${BOLD}${OBFS}${NC}"
        if [ "$VERSION" == "1" ]; then
            echo -e " ${PURPLE}${BOLD}• Tipo de Ofuscación  :${NC} ${WHITE}Standard UDP Obfs${NC}"
            echo -e " ${PURPLE}${BOLD}• Velocidad Up / Down :${NC} ${GREEN}1000 Mbps / 1000 Mbps${NC}"
        else
            echo -e " ${PURPLE}${BOLD}• Tipo de Ofuscación  :${NC} ${WHITE}Salamander${NC}"
        fi
        echo -e " ${PURPLE}${BOLD}• Autenticación (Auth):${NC} ${CYAN}Usuario y Contraseña SSH del Servidor${NC}"
        echo -e " ${PURPLE}${BOLD}• Allow Insecure (TLS):${NC} ${GREEN}true (1)${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        echo -e "${CYAN}${BOLD}                     ENLACE DIRECTO (URI)                 ${NC}"
        echo -e "${YELLOW}${BOLD}${LINK:-Sin enlace disponible}${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}${BOLD}Nota:${NC} ${CYAN}Cambia ${WHITE}${BOLD}USUARIO:PASSWORD${NC} ${CYAN}por tus credenciales SSH del VPS en tu cliente (NekoBox, Matsuri, v2rayN, Clash Meta).${NC}\n"
    else
        echo -e "${RED}[!] No hay una configuración activa de Hysteria.${NC}"
    fi
    read -p "Presione ENTER para continuar..."
}

config_udp_hysteria() {
    clear
    get_public_ip
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            INSTALADOR UDP-HYSTERIA                    │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Hysteria Versión 1 (Standard UDP Obfs)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Hysteria Versión 2 (Salamander - RECOMENDADO)${NC}"
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

    H_OBFS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)

    echo -e "\n${YELLOW}Instalando dependencias y binarios...${NC}"
    install_dependencies
    install_hysteria_bin "$H_VER" || { read -p "Presione ENTER para volver"; return; }
    
    generate_silent_cert
    create_auth_script
    optimize_kernel

    if [ "$H_VER" == "1" ]; then
        HY_LINK="hysteria://${PUBLIC_IP}:${H_PORT}/?protocol=udp&auth=USUARIO:PASSWORD&obfs=${H_OBFS}&obfsParam=${H_OBFS}&upmbps=1000&downmbps=1000&insecure=1&peer=${H_SNI}#HysteriaV1_${PUBLIC_IP}"
        cat <<EOF > /etc/hysteria/config.json
{
  "listen": ":$H_PORT",
  "cert": "/etc/hysteria/server.crt",
  "key": "/etc/hysteria/server.key",
  "auth": {
    "mode": "external",
    "config": {
      "cmd": "/etc/hysteria/auth.sh"
    }
  },
  "obfs": "$H_OBFS",
  "up_mbps": 1000,
  "down_mbps": 1000
}
EOF
        CMD="/usr/local/bin/hysteria -c /etc/hysteria/config.json server"
    else
        HY_LINK="hysteria2://USUARIO:PASSWORD@${PUBLIC_IP}:${H_PORT}?insecure=1&sni=${H_SNI}&obfs=salamander&obfs-password=${H_OBFS}#HysteriaV2_${PUBLIC_IP}"
        cat <<EOF > /etc/hysteria/config.yaml
listen: :$H_PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: command
  command: /etc/hysteria/auth.sh

obfs:
  type: salamander
  salamander:
    password: "$H_OBFS"
EOF
        CMD="/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml"
    fi

    cat <<EOF > /etc/hysteria/panel.conf
VERSION="$H_VER"
PORT="$H_PORT"
RANGE="$H_RANGE_IPT"
OBFS="$H_OBFS"
SNI="$H_SNI"
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
    
    iptables -t nat -D PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT 2>/dev/null
    iptables -t nat -I PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT 2>/dev/null
    
    systemctl daemon-reload
    systemctl restart udp-hysteria
    systemctl enable udp-hysteria >/dev/null 2>&1
    
    show_hysteria_info
}

menu_udp_hysteria() {
    if [ ! -f "/etc/hysteria/panel.conf" ]; then
        config_udp_hysteria
        return
    fi
    
    source /etc/hysteria/panel.conf 2>/dev/null
    
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
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}${BOLD}Ver Datos Completos y Enlace (URI)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Reconfigurar UDP-Hysteria${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${RED}Desinstalar UDP-Hysteria${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-6]: ${NC}")" OPT
    
    case $OPT in
        1) show_hysteria_info; menu_udp_hysteria ;;
        2) config_udp_hysteria; menu_udp_hysteria ;;
        3) fuser -k $PORT/udp 2>/dev/null; pkill -9 hysteria 2>/dev/null; systemctl restart udp-hysteria; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1; menu_udp_hysteria ;;
        4) systemctl stop udp-hysteria; echo -e "${YELLOW}✔ Detenido.${NC}"; sleep 1; menu_udp_hysteria ;;
        5) journalctl -u udp-hysteria -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_udp_hysteria ;;
        6) 
           systemctl stop udp-hysteria 2>/dev/null
           systemctl disable udp-hysteria 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 hysteria 2>/dev/null
           iptables -t nat -D PREROUTING -p udp -m udp --dport $RANGE -j REDIRECT --to-ports $PORT 2>/dev/null
           rm -rf /etc/hysteria /etc/systemd/system/udp-hysteria.service
           rm -f /usr/local/bin/hysteria /usr/bin/hysteria
           systemctl daemon-reload
           echo -e "${GREEN}✔ Desinstalado completamente.${NC}"
           sleep 2
           menu_main ;;
        0) menu_main ;;
        *) menu_udp_hysteria ;;
    esac
}

# ==========================================
# MÓDULO: UDP CUSTOM (HTTP CUSTOM)
# ==========================================
install_udp_bin() {
    echo -e "${CYAN}[*] Verificando e instalando binario UDP Custom...${NC}"
    
    ARCH=$(uname -m)
    mkdir -p /etc/udp-custom
    
    if [[ "$ARCH" == *"arm"* ]] || [[ "$ARCH" == *"aarch"* ]]; then
        echo -e "${YELLOW}  ➔ Arquitectura ARM detectada (${ARCH})${NC}"
        URLS=(
            "https://raw.githubusercontent.com/prjkt-nv404/UDP-Custom-Installer-arm64/main/udpc-arm64"
        )
    else
        echo -e "${YELLOW}  ➔ Arquitectura AMD64 detectada (${ARCH})${NC}"
        URLS=(
            "https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64"
            "https://github.com/prasath-official/UDP-Custom-Installer/raw/main/udp-custom-linux-amd64"
            "https://github.com/Haris131/UDP-Custom/raw/main/udp-custom-linux-amd64"
        )
    fi

    SUCCESS=0
    for url in "${URLS[@]}"; do
        echo -e "${CYAN}  ➔ Descargando binario...${NC}"
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
        echo -e "${RED}[!] Error al instalar el binario de UDP Custom.${NC}"
        return 1
    fi
    return 0
}

show_udpcustom_info() {
    clear
    get_public_ip
    if [ -f "/etc/udp-custom/panel.conf" ]; then
        source /etc/udp-custom/panel.conf 2>/dev/null
        echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}${BOLD}│       DATOS DE CONEXIÓN - UDP CUSTOM (HTTP CUSTOM)     │${NC}"
        echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
        echo -e " ${PURPLE}${BOLD}• Protocolo           :${NC} ${YELLOW}${BOLD}UDP Custom Engine (ePro Dev. Team)${NC}"
        echo -e " ${PURPLE}${BOLD}• Host / IP Servidor  :${NC} ${GREEN}${BOLD}${PUBLIC_IP}${NC}"
        echo -e " ${PURPLE}${BOLD}• Puerto Principal UDP:${NC} ${WHITE}${BOLD}${PORT}${NC}"
        echo -e " ${PURPLE}${BOLD}• Rango IPTables      :${NC} ${CYAN}${BOLD}${RANGE} -> ${PORT}${NC}"
        echo -e " ${PURPLE}${BOLD}• Autenticación (Auth):${NC} ${CYAN}Cuentas SSH del Servidor (Shadow/PAM)${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        echo -e "${CYAN}${BOLD}         GUÍA DE CONFIGURACIÓN EN HTTP CUSTOM APP         ${NC}"
        echo -e " ${WHITE}1.${NC} Abre la app ${BOLD}HTTP Custom (Android/iOS)${NC}."
        echo -e " ${WHITE}2.${NC} Marca la casilla ${GREEN}${BOLD}UDP / UDP Custom${NC}."
        echo -e " ${WHITE}3.${NC} Formato de Conexión en la casilla principal de la App:"
        echo -e "    ${YELLOW}${BOLD}${PUBLIC_IP}:${PORT}@USUARIO:PASSWORD${NC}"
        echo -e "    ${CYAN}(o usa cualquier puerto dentro del rango ${RANGE})${NC}"
        echo -e " ${WHITE}4.${NC} Presiona ${GREEN}${BOLD}CONNECT${NC}."
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}\n"
    else
        echo -e "${RED}[!] No hay una configuración activa de UDP Custom.${NC}"
    fi
    read -p "Presione ENTER para continuar..."
}

config_udp() {
    clear
    get_public_ip
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            INSTALADOR UDP CUSTOM                       │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Puerto principal UDP [predeterminado 36712]: ${NC}")" U_PORT
    U_PORT=${U_PORT:-36712}
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa el rango Iptables [predeterminado 1:65535]: ${NC}")" U_RANGE
    U_RANGE=${U_RANGE:-1:65535}
    U_RANGE_IPT=$(echo "$U_RANGE" | tr '-' ':')

    echo -e "\n${YELLOW}Instalando binario y dependencias de UDP Custom...${NC}"
    install_dependencies
    optimize_kernel
    install_udp_bin || { read -p "Presione ENTER para volver"; return; }

    mkdir -p /etc/udp-custom
    
    cat <<EOF > /etc/udp-custom/config.json
{
  "listen": ":$U_PORT",
  "stream_buffer": 209715200,
  "receive_buffer": 209715200,
  "auth": {
    "mode": "passwords"
  }
}
EOF
    
    cat <<EOF > /etc/udp-custom/panel.conf
PORT="$U_PORT"
RANGE="$U_RANGE_IPT"
EOF

    cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom Server (ePro Dev. Team)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/udp-custom
ExecStart=/usr/local/bin/udp-custom server
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

    iptables -t nat -D PREROUTING -p udp -m udp --dport $U_RANGE_IPT -j REDIRECT --to-ports $U_PORT 2>/dev/null
    iptables -t nat -I PREROUTING -p udp -m udp --dport $U_RANGE_IPT -j REDIRECT --to-ports $U_PORT 2>/dev/null

    systemctl daemon-reload
    systemctl enable udp-custom > /dev/null 2>&1
    systemctl restart udp-custom
    
    show_udpcustom_info
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
    
    if systemctl is-active --quiet udp-custom; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}${BOLD}Ver Datos de Conexión y Guía${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Reconfigurar UDP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${RED}Desinstalar UDP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-6]: ${NC}")" OPT
    
    case $OPT in
        1) show_udpcustom_info; menu_udp_custom ;;
        2) config_udp; menu_udp_custom ;;
        3) fuser -k $PORT/udp 2>/dev/null; pkill -9 udp-custom 2>/dev/null; systemctl restart udp-custom; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1; menu_udp_custom ;;
        4) systemctl stop udp-custom; echo -e "${YELLOW}✔ Detenido.${NC}"; sleep 1; menu_udp_custom ;;
        5) journalctl -u udp-custom -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_udp_custom ;;
        6) 
           systemctl stop udp-custom 2>/dev/null
           systemctl disable udp-custom 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 udp-custom 2>/dev/null
           iptables -t nat -D PREROUTING -p udp -m udp --dport $RANGE -j REDIRECT --to-ports $PORT 2>/dev/null
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

show_zivpn_info() {
    clear
    get_public_ip
    if [ -f "/etc/zivpn/panel.conf" ]; then
        source /etc/zivpn/panel.conf 2>/dev/null
        echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}${BOLD}│         DATOS DE CONEXIÓN - ZIVPN TUNNEL UDP           │${NC}"
        echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
        echo -e " ${PURPLE}${BOLD}• Protocolo            :${NC} ${YELLOW}${BOLD}ZI VPN Engine${NC}"
        echo -e " ${PURPLE}${BOLD}• Host / IP Servidor   :${NC} ${GREEN}${BOLD}${PUBLIC_IP}${NC}"
        echo -e " ${PURPLE}${BOLD}• Puerto Principal UDP :${NC} ${WHITE}${BOLD}${PORT}${NC}"
        echo -e " ${PURPLE}${BOLD}• Rango IPTables       :${NC} ${CYAN}${BOLD}${RANGE} -> ${PORT}${NC}"
        echo -e " ${PURPLE}${BOLD}• Contraseña (Password):${NC} ${YELLOW}${BOLD}${PASS}${NC}"
        echo -e " ${PURPLE}${BOLD}• Protocolo OBFS       :${NC} ${WHITE}zivpn (Interno / No requiere escribirlo)${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        echo -e "${CYAN}${BOLD}          GUÍA DE CONFIGURACIÓN EN ZIVPN TUNNEL           ${NC}"
        echo -e " ${WHITE}1.${NC} Abre la app ${BOLD}ZIVPN Tunnel (Android/iOS)${NC}."
        echo -e " ${WHITE}2.${NC} Selecciona el modo o protocolo ${GREEN}${BOLD}UDP (Custom Server)${NC}."
        echo -e " ${WHITE}3.${NC} En Servidor/Host ingresa: ${YELLOW}${BOLD}${PUBLIC_IP}${NC}"
        echo -e " ${WHITE}4.${NC} En Puerto ingresa: ${WHITE}${BOLD}${PORT}${NC} ${CYAN}(o cualquiera del rango ${RANGE})${NC}"
        echo -e " ${WHITE}5.${NC} En Password/Auth ingresa: ${YELLOW}${BOLD}${PASS}${NC}"
        echo -e " ${WHITE}6.${NC} Presiona ${GREEN}${BOLD}Connect / Iniciar${NC}."
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}\n"
    else
        echo -e "${RED}[!] No hay una configuración activa de ZIVPN.${NC}"
    fi
    read -p "Presione ENTER para continuar..."
}

config_zivpn() {
    clear
    get_public_ip
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            INSTALADOR ZI VPN TUNNEL                    │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Puerto principal UDP [predeterminado 5667]: ${NC}")" Z_PORT
    Z_PORT=${Z_PORT:-5667}

    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa Rango IPTables [predeterminado 6000:19999]: ${NC}")" Z_RANGE
    Z_RANGE=${Z_RANGE:-6000:19999}
    Z_RANGE_IPT=$(echo "$Z_RANGE" | tr '-' ':')

    read -p "$(echo -e "${CYAN}❯ ${WHITE}Contraseña de Conexión [predeterminado zi]: ${NC}")" Z_PASS
    Z_PASS=${Z_PASS:-zi}

    echo -e "\n${YELLOW}Instalando binario y dependencias de ZIVPN...${NC}"
    install_dependencies
    optimize_kernel
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
  "obfs": "zivpn",
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
RANGE="$Z_RANGE_IPT"
PASS="$Z_PASS"
EOF

    systemctl stop zivpn 2>/dev/null
    fuser -k $Z_PORT/udp 2>/dev/null
    pkill -9 zivpn 2>/dev/null
    sleep 1

    iptables -t nat -D PREROUTING -p udp -m udp --dport $Z_RANGE_IPT -j REDIRECT --to-ports $Z_PORT 2>/dev/null
    iptables -t nat -I PREROUTING -p udp -m udp --dport $Z_RANGE_IPT -j REDIRECT --to-ports $Z_PORT 2>/dev/null

    systemctl daemon-reload
    systemctl enable zivpn > /dev/null 2>&1
    systemctl restart zivpn

    show_zivpn_info
}

menu_zivpn() {
    if [ ! -f "/etc/zivpn/panel.conf" ]; then
        config_zivpn
        return
    fi
    
    source /etc/zivpn/panel.conf 2>/dev/null
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│           ADMINISTRADOR ZI VPN TUNNEL                  │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto UDP      :${NC} ${GREEN}${BOLD}$PORT${NC}"
    echo -e " ${PURPLE}${BOLD}Rango IPTables  :${NC} ${CYAN}${BOLD}$RANGE > $PORT${NC}"
    echo -e " ${PURPLE}${BOLD}Contraseña PASS :${NC} ${YELLOW}${BOLD}$PASS${NC}"
    
    if systemctl is-active --quiet zivpn; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}${BOLD}Ver Datos de Conexión y Guía${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Reconfigurar ZI VPN${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${RED}Desinstalar ZI VPN${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-6]: ${NC}")" OPT
    
    case $OPT in
        1) show_zivpn_info; menu_zivpn ;;
        2) config_zivpn; menu_zivpn ;;
        3) fuser -k $PORT/udp 2>/dev/null; pkill -9 zivpn 2>/dev/null; systemctl restart zivpn; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1; menu_zivpn ;;
        4) systemctl stop zivpn; echo -e "${YELLOW}✔ Detenido.${NC}"; sleep 1; menu_zivpn ;;
        5) journalctl -u zivpn -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_zivpn ;;
        6) 
           systemctl stop zivpn 2>/dev/null
           systemctl disable zivpn 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 zivpn 2>/dev/null
           iptables -t nat -D PREROUTING -p udp -m udp --dport $RANGE -j REDIRECT --to-ports $PORT 2>/dev/null
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
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Administrador UDP Custom (HTTP Custom)${NC}"
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
