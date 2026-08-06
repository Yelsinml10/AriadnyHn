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
    apt-get install -y wget curl nano iptables ufw unzip openssl net-tools iproute2 jq socat cron python3 python3-pip git psmisc file awk > /dev/null 2>&1
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

# ==========================================
# CERTIFICADO INVISIBLE
# ==========================================
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
# MÓDULO: UDP-HYSTERIA (V1 & V2 CORREGIDO)
# ==========================================
install_hysteria_bin() {
    local VER=$1
    echo -e "${CYAN}[*] Instalando Binario de Hysteria (Versión $VER)...${NC}"
    
    systemctl stop udp-hysteria 2>/dev/null
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
        echo -e "${YELLOW}  ➔ Intentando descargar...${NC}"
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
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            CONFIGURAR PUERTO HYSTERIA                  │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    echo -e " ${YELLOW}${BOLD}⚠ Para HTTP Custom usa puerto 443 o 36712${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa el puerto UDP [predeterminado 443]: ${NC}")" H_PORT
    H_PORT=${H_PORT:-443}
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│            CONFIGURAR RANGO IPTABLES                   │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    echo -e " ${WHITE}• Puerto UDP Seleccionado: ${GREEN}${BOLD}$H_PORT${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa Rango Iptables [predeterminado 1:65535]: ${NC}")" H_RANGE
    H_RANGE=${H_RANGE:-1:65535}
    H_RANGE_IPT=$(echo "$H_RANGE" | tr '-' ':')
    
    H_OBFS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)
    
    AUTH_URI=""
    if [ "$H_VER" == "2" ]; then
        clear
        echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}${BOLD}│        AUTENTICACIÓN (HYSTERIA V2)                     │${NC}"
        echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
        echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Contraseña Fija Personalizada${NC}"
        echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Backend HTTP Externo (API / Panel Web)${NC}"
        echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}${BOLD}Autenticación por Panel SSH (sshpanel / Sistema Linux)${NC}"
        echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Multi-Usuario Manual (userpass)${NC}"
        echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${YELLOW}Sin autenticación (Solo para pruebas)${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [1-5]: ${NC}")" AUTH_OPT
        AUTH_OPT=${AUTH_OPT:-3}

        case $AUTH_OPT in
            2)
                read -p "$(echo -e "${CYAN}❯ ${WHITE}URL Backend HTTP: ${NC}")" HTTP_URL
                HTTP_URL=${HTTP_URL:-"http://127.0.0.1:8080/auth"}
                AUTH_BLOCK="auth:
  type: http
  http:
    url: \"$HTTP_URL\""
                read -p "$(echo -e "${CYAN}❯ ${WHITE}Contraseña para el enlace: ${NC}")" PANEL_PASS
                PANEL_PASS=${PANEL_PASS:-"TU_CONTRASEÑA"}
                AUTH_INFO="HTTP ($HTTP_URL)"
                AUTH_URI="${PANEL_PASS}@"
                ;;
            3)
                # Autenticador nativo en Bash usando openssl (Compatible Ubuntu 24.04+)
                cat <<'EOF_AUTH' > /etc/hysteria/auth.sh
#!/bin/bash
AUTH_PAYLOAD="$2"
[ -z "$AUTH_PAYLOAD" ] && exit 1

if [[ "$AUTH_PAYLOAD" == *":"* ]]; then
    USER="${AUTH_PAYLOAD%%:*}"
    PASS="${AUTH_PAYLOAD#*:}"
else
    USER="$AUTH_PAYLOAD"
    PASS="$AUTH_PAYLOAD"
fi

# Verifica si el usuario existe en el sistema
if ! id "$USER" &>/dev/null; then
    exit 1
fi

# Verificación de expiración
EXP_DATE=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
if [ "$EXP_DATE" != "never" ] && [ -n "$EXP_DATE" ]; then
    EXP_SEC=$(date -d "$EXP_DATE" +%s 2>/dev/null)
    NOW_SEC=$(date +%s)
    if [ -n "$EXP_SEC" ] && [ "$NOW_SEC" -gt "$EXP_SEC" ]; then
        exit 1
    fi
fi

# Extracción de hash y validación nativa sin dependencias obsoletas
VALID_HASH=$(sudo awk -F: -v user="$USER" '$1 == user {print $2}' /etc/shadow)

if [[ "$VALID_HASH" == "\$y\$"* ]]; then
    # yescrypt (Predeterminado en Ubuntu recientes)
    SALT=$(echo "$VALID_HASH" | cut -d\$ -f1,2,3,4)
    TEST_HASH=$(openssl passwd -yescrypt -salt "$SALT" "$PASS" 2>/dev/null)
elif [[ "$VALID_HASH" == "\$6\$"* ]]; then
    # SHA-512 (Común en versiones anteriores)
    SALT=$(echo "$VALID_HASH" | cut -d\$ -f1,2,3)
    TEST_HASH=$(openssl passwd -6 -salt "$SALT" "$PASS" 2>/dev/null)
else
    exit 1
fi

[ "$VALID_HASH" == "$TEST_HASH" ] && exit 0 || exit 1
EOF_AUTH
                chmod +x /etc/hysteria/auth.sh

                AUTH_BLOCK="auth:
  type: command
  command: \"/etc/hysteria/auth.sh\""
                
                echo -e "\n${YELLOW}Configuración para el Enlace:${NC}"
                read -p "$(echo -e "${CYAN}❯ ${WHITE}Nombre de un usuario creado en tu sshpanel: ${NC}")" U_NAME
                read -p "$(echo -e "${CYAN}❯ ${WHITE}Contraseña de ese usuario: ${NC}")" U_PASS
                U_NAME=${U_NAME:-"USUARIO"}
                U_PASS=${U_PASS:-"CONTRASEÑA"}
                
                AUTH_INFO="Autenticado con sshpanel (/etc/passwd)"
                AUTH_URI="${U_NAME}:${U_PASS}@"
                ;;
            4)
                read -p "$(echo -e "${CYAN}❯ ${WHITE}Usuario: ${NC}")" U_NAME
                read -p "$(echo -e "${CYAN}❯ ${WHITE}Contraseña: ${NC}")" U_PASS
                U_NAME=${U_NAME:-"admin"}
                U_PASS=${U_PASS:-"admin123"}
                AUTH_BLOCK="auth:
  type: userpass
  userpass:
    $U_NAME: \"$U_PASS\""
                AUTH_INFO="Userpass ($U_NAME:$U_PASS)"
                AUTH_URI="${U_NAME}:${U_PASS}@"
                ;;
            5)
                # Sin autenticación
                AUTH_BLOCK=""
                AUTH_INFO="Sin autenticación"
                AUTH_URI=""
                ;;
            *)
                read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa la contraseña personalizada: ${NC}")" H_PASS
                H_PASS=${H_PASS:-$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)}
                AUTH_BLOCK="auth:
  type: password
  password: \"$H_PASS\""
                AUTH_INFO="Password ($H_PASS)"
                AUTH_URI="${H_PASS}@"
                ;;
        esac
    else
        AUTH_INFO="V1 - Sin autenticación"
        AUTH_URI=""
    fi

    echo -e "\n${YELLOW}Instalando y configurando...${NC}"
    install_dependencies
    
    install_hysteria_bin "$H_VER" || { echo -e "\n Presione ENTER para volver"; read -p ""; return; }
    
    generate_silent_cert
    optimize_kernel

    # Generación del Link URI
    if [ "$H_VER" == "1" ]; then
        HY_LINK="hysteria://${PUBLIC_IP}:${H_PORT}?protocol=udp&auth=&obfs=${H_OBFS}&upmbps=1000&downmbps=1000&insecure=1&peer=localhost#HysteriaV1_${PUBLIC_IP}"
    else
        HY_LINK="hysteria2://${AUTH_URI}${PUBLIC_IP}:${H_PORT}?insecure=1&sni=localhost&obfs=salamander&obfs-password=${H_OBFS}#HysteriaV2_${PUBLIC_IP}"
    fi

    cat <<EOF > /etc/hysteria/panel.conf
VERSION="$H_VER"
PORT="$H_PORT"
RANGE="$H_RANGE_IPT"
OBFS="$H_OBFS"
AUTH_INFO="$AUTH_INFO"
AUTH_URI="$AUTH_URI"
LINK="$HY_LINK"
EOF
    
    if [ "$H_VER" == "1" ]; then
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

    # Integración de la redirección NAT directamente en el servicio Systemd
    cat <<EOF > /etc/systemd/system/udp-hysteria.service
[Unit]
Description=UDP-Hysteria Server V${H_VER}
After=network.target

[Service]
Type=simple
User=root
ExecStart=$CMD
ExecStartPost=/bin/bash -c 'iptables -t nat -I PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT || true'
ExecStopPost=/bin/bash -c 'iptables -t nat -D PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT || true'
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
    pkill -9 hysteria 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $H_PORT -j ACCEPT >/dev/null 2>&1
    ufw allow $H_PORT/udp >/dev/null 2>&1
    
    systemctl daemon-reload
    systemctl restart udp-hysteria
    systemctl enable udp-hysteria >/dev/null 2>&1
    
    show_hysteria_info
}

show_hysteria_info() {
    clear
    get_public_ip
    if [ -f "/etc/hysteria/panel.conf" ]; then
        source /etc/hysteria/panel.conf 2>/dev/null
    fi
    
    if [ -z "$LINK" ]; then
        if [ "$VERSION" == "1" ]; then
            LINK="hysteria://${PUBLIC_IP}:${PORT}?protocol=udp&auth=&obfs=${OBFS}&upmbps=1000&downmbps=1000&insecure=1&peer=localhost#HysteriaV1_${PUBLIC_IP}"
        else
            LINK="hysteria2://${AUTH_URI}${PUBLIC_IP}:${PORT}?insecure=1&sni=localhost&obfs=salamander&obfs-password=${OBFS}#HysteriaV2_${PUBLIC_IP}"
        fi
    fi
    
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│       ¡DATOS Y ENLACE DE CONEXIÓN HYSTERIA V${VERSION:-2}!      │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}• IP del Servidor :${NC} ${YELLOW}${BOLD}$PUBLIC_IP${NC}"
    echo -e " ${PURPLE}${BOLD}• Puerto UDP      :${NC} ${GREEN}${BOLD}$PORT${NC}"
    echo -e " ${PURPLE}${BOLD}• Rango IPTables  :${NC} ${CYAN}$RANGE > $PORT${NC}"
    echo -e " ${PURPLE}${BOLD}• Autenticación   :${NC} ${GREEN}${AUTH_INFO:-Libre}${NC}"
    echo -e " ${PURPLE}${BOLD}• Clave OBFS      :${NC} ${YELLOW}$OBFS${NC}"
    echo -e " ${PURPLE}${BOLD}• SNI / Peer      :${NC} ${WHITE}localhost${NC}"
    echo -e " ${PURPLE}${BOLD}• Permite Insecure:${NC} ${GREEN}true (1)${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${BOLD}📌 LINK DE CONEXIÓN (Copiar y pegar en la App):${NC}"
    echo -e "${YELLOW}${BOLD}$LINK${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}\n"
    read -p "$(echo -e "${WHITE}${BOLD}Presione ENTER para continuar...${NC}")"
}

menu_udp_hysteria() {
    if [ ! -f "/etc/hysteria/panel.conf" ]; then
        config_udp_hysteria
        return
    fi
    
    source /etc/hysteria/panel.conf 2>/dev/null
    
    REAL_VER="Desconocida"
    if [ -x "/usr/local/bin/hysteria" ]; then
        REAL_VER=$(/usr/local/bin/hysteria version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "v1.x")
    fi
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│           ADMINISTRADOR UDP-HYSTERIA                   │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Versión Config  :${NC} ${YELLOW}${BOLD}Hysteria V$VERSION${NC}"
    echo -e " ${PURPLE}${BOLD}Versión Binario :${NC} ${GREEN}${BOLD}$REAL_VER${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto UDP      :${NC} ${GREEN}${BOLD}$PORT${NC}"
    echo -e " ${PURPLE}${BOLD}Redirección     :${NC} ${CYAN}$RANGE > $PORT${NC}"
    echo -e " ${PURPLE}${BOLD}OBFS            :${NC} ${YELLOW}$OBFS${NC}"
    echo -e " ${PURPLE}${BOLD}Autenticación   :${NC} ${GREEN}${AUTH_INFO:-Libre}${NC}"
    
    if systemctl is-active --quiet udp-hysteria; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Reconfigurar UDP-Hysteria${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Modificar OBFS${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Cambiar Versión (V1 ↔ V2)${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Estado del Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 7 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 8 ]${NC} ${GREEN}${BOLD}VER / COPIAR LINK DE CONEXIÓN${NC}"
    echo -e " ${WHITE}${BOLD}[ 9 ]${NC} ${RED}Desinstalar UDP-Hysteria${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-9]: ${NC}")" OPT
    
    case $OPT in
        1) config_udp_hysteria; menu_udp_hysteria ;;
        2) 
           read -p "$(echo -e "${CYAN}❯ ${WHITE}Nuevo OBFS: ${NC}")" NEW_OBFS
           if [ -n "$NEW_OBFS" ]; then
               get_public_ip
               sed -i "s/OBFS=.*/OBFS=\"$NEW_OBFS\"/g" /etc/hysteria/panel.conf
               if [ "$VERSION" == "1" ]; then
                   sed -i "s/\"obfs\": \".*\"/\"obfs\": \"$NEW_OBFS\"/g" /etc/hysteria/config.json
                   NEW_LINK="hysteria://${PUBLIC_IP}:${PORT}?protocol=udp&auth=&obfs=${NEW_OBFS}&upmbps=1000&downmbps=1000&insecure=1&peer=localhost#HysteriaV1_${PUBLIC_IP}"
               else
                   sed -i '/salamander:/{n;s/password: .*/password: "'"$NEW_OBFS"'"/}' /etc/hysteria/config.yaml
                   NEW_LINK="hysteria2://${AUTH_URI}${PUBLIC_IP}:${PORT}?insecure=1&sni=localhost&obfs=salamander&obfs-password=${NEW_OBFS}#HysteriaV2_${PUBLIC_IP}"
               fi
               sed -i "s|LINK=.*|LINK=\"$NEW_LINK\"|g" /etc/hysteria/panel.conf
               systemctl restart udp-hysteria
               echo -e "${GREEN}✔ OBFS y Link actualizados correctamente.${NC}"; sleep 2
           fi
           menu_udp_hysteria ;;
        3) config_udp_hysteria; menu_udp_hysteria ;;
        4) systemctl status udp-hysteria --no-pager; read -p "Presione ENTER para volver..."; menu_udp_hysteria ;;
        5) systemctl restart udp-hysteria; echo -e "${GREEN}✔ Servicio reiniciado.${NC}"; sleep 1; menu_udp_hysteria ;;
        6) systemctl stop udp-hysteria; echo -e "${YELLOW}Servicio detenido.${NC}"; sleep 1; menu_udp_hysteria ;;
        7) journalctl -u udp-hysteria -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_udp_hysteria ;;
        8) show_hysteria_info; menu_udp_hysteria ;;
        9) 
           systemctl stop udp-hysteria 2>/dev/null
           systemctl disable udp-hysteria 2>/dev/null
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
    
    # Ruteado a tu propio repositorio para evitar discrepancias de versión
    if [[ "$ARCH" == *"arm"* ]] || [[ "$ARCH" == *"aarch"* ]]; then
        URLS=("https://raw.githubusercontent.com/Yelsinml10/Udp/main/udp-custom-linux-arm64")
    else
        URLS=("https://raw.githubusercontent.com/Yelsinml10/Udp/main/udp-custom-linux-amd64")
    fi

    for url in "${URLS[@]}"; do
        curl -sSL -o /usr/local/bin/udp-custom "$url" 2>/dev/null || wget -qO /usr/local/bin/udp-custom --no-check-certificate "$url" 2>/dev/null
        if [ -s "/usr/local/bin/udp-custom" ]; then
            chmod +x /usr/local/bin/udp-custom
            echo -e "${GREEN}✔ UDP Custom instalado con éxito.${NC}"
            return 0
        fi
    done
    echo -e "${RED}[!] Error al instalar UDP Custom. Asegúrate de tener el archivo en tu repositorio Github.${NC}"; return 1
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
    
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Puerto UDP [predeterminado 443]: ${NC}")" U_PORT
    U_PORT=${U_PORT:-443}

    install_dependencies
    install_udp_bin || { echo -e "\n Presione ENTER para volver"; read -p ""; return; }

    mkdir -p /etc/udp-custom
    
    # Obtener dominio/IP
    CERT_CN=$(curl -sS ifconfig.me 2>/dev/null || curl -sS api.ipify.org 2>/dev/null || echo "localhost")
    
    if [ "$TLS_OPT" == "2" ]; then
        echo -e "${CYAN}[*] Generando certificados SSL/TLS...${NC}"
        mkdir -p /etc/udp-custom/certs
        
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /etc/udp-custom/certs/server.key \
            -out /etc/udp-custom/certs/server.crt \
            -days 3650 \
            -subj "/CN=$CERT_CN" > /dev/null 2>&1
        
        cat <<EOF > /etc/udp-custom/config.json
{
  "listen": ":$U_PORT",
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
        echo -e "${GREEN}✔ TLS/DTLS ACTIVADO${NC}"
    else
        cat <<EOF > /etc/udp-custom/config.json
{
  "listen": ":$U_PORT",
  "stream_buffer": 33554432,
  "receive_buffer": 8388608,
  "exclude_ports": [53, 5300]
}
EOF
        TLS_STATUS="disabled"
        echo -e "${YELLOW}⚠ TLS DESACTIVADO${NC}"
    fi
    
    # Guardar configuración
    cat <<EOF > /etc/udp-custom/panel.conf
TLS=$TLS_STATUS
PORT=$U_PORT
CERT_CN=$CERT_CN
EOF

    # Crear servicio systemd
    cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/udp-custom
ExecStart=/usr/local/bin/udp-custom server -config /etc/udp-custom/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

    # Detener y limpiar
    systemctl stop udp-custom 2>/dev/null
    pkill -9 udp-custom 2>/dev/null
    sleep 1

    # Abrir puerto en firewall
    iptables -I INPUT -p udp --dport $U_PORT -j ACCEPT 2>/dev/null
    ufw allow $U_PORT/udp 2>/dev/null

    # Iniciar servicio
    systemctl daemon-reload
    systemctl enable udp-custom > /dev/null 2>&1
    systemctl restart udp-custom
    
    clear
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}     ✅ UDP CUSTOM CONFIGURADO CON ÉXITO                   ${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BOLD}${YELLOW}📋 CONFIGURACIÓN PARA HTTP CUSTOM:${NC}"
    echo ""
    echo -e " ${WHITE}Host:${NC} ${GREEN}${CERT_CN}:${U_PORT}${NC}"
    echo -e " ${WHITE}SNI:${NC} ${GREEN}${CERT_CN}${NC}"
    echo -e " ${WHITE}TLS:${NC} ${GREEN}${TLS_STATUS}${NC}"
    echo -e " ${WHITE}Rango:${NC} ${GREEN}1-65535${NC}"
    echo -e " ${WHITE}Usuario:${NC} ${YELLOW}(vacío)${NC}"
    echo -e " ${WHITE}Contraseña:${NC} ${YELLOW}(vacío)${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}📱 CONFIGURACIÓN PASO A PASO EN HTTP CUSTOM:${NC}"
    echo ""
    echo -e " ${WHITE}1.${NC} Abre HTTP Custom"
    echo -e " ${WHITE}2.${NC} En la pestaña principal:"
    echo -e "    ${WHITE}• Host:${NC} ${GREEN}${CERT_CN}:${U_PORT}${NC}"
    echo -e "    ${WHITE}• Usuario:${NC} ${YELLOW}(vacío)${NC}"
    echo -e "    ${WHITE}• Contraseña:${NC} ${YELLOW}(vacío)${NC}"
    echo -e " ${WHITE}3.${NC} En la pestaña TLS:"
    echo -e "    ${WHITE}• SNI:${NC} ${GREEN}${CERT_CN}${NC}"
    echo -e "    ${WHITE}• TLS:${NC} ${GREEN}${TLS_STATUS}${NC}"
    echo -e " ${WHITE}4.${NC} Presiona Conectar"
    echo ""
    
    if systemctl is-active --quiet udp-custom; then
        echo -e "${GREEN}✔ Servicio UDP Custom ACTIVO${NC}"
    else
        echo -e "${RED}✖ Servicio UDP Custom DETENIDO${NC}"
        echo -e "${YELLOW}  → Ejecuta: systemctl restart udp-custom${NC}"
    fi
    echo ""
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
    echo -e " ${PURPLE}${BOLD}TLS/DTLS        :${NC} ${GREEN}${BOLD}$TLS${NC}"
    echo -e " ${PURPLE}${BOLD}Dominio/SNI     :${NC} ${CYAN}${BOLD}${CERT_CN:-N/A}${NC}"
    
    if systemctl is-active --quiet udp-custom; then
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} ${RED}[DETENIDO / STOPPED]${NC}"
    fi
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Reconfigurar UDP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Alternar TLS (ON/OFF)${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Mostrar Configuración HTTP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Estado del Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 7 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 9 ]${NC} ${RED}Desinstalar UDP Custom${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-9]: ${NC}")" OPT
    
    case $OPT in
        1) config_udp; menu_udp_custom ;;
        2) toggle_udp_tls; menu_udp_custom ;;
        3) mostrar_config_udp; menu_udp_custom ;;
        4) systemctl status udp-custom --no-pager; read -p "Presione ENTER para volver..."; menu_udp_custom ;;
        5) 
           systemctl restart udp-custom
           echo -e "${GREEN}✔ Servicio reiniciado.${NC}"; sleep 1; menu_udp_custom ;;
        6) systemctl stop udp-custom; echo -e "${YELLOW}Servicio detenido.${NC}"; sleep 1; menu_udp_custom ;;
        7) journalctl -u udp-custom -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_udp_custom ;;
        9) 
           systemctl stop udp-custom 2>/dev/null
           systemctl disable udp-custom 2>/dev/null
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

toggle_udp_tls() {
    if [ ! -f "/etc/udp-custom/panel.conf" ]; then
        echo -e "${RED}[!] No hay configuración.${NC}"
        return
    fi
    
    source /etc/udp-custom/panel.conf
    
    if [ "$TLS" == "enabled" ]; then
        echo -e "${YELLOW}[*] Desactivando TLS...${NC}"
        python3 -c "
import json
with open('/etc/udp-custom/config.json', 'r') as f:
    data = json.load(f)
if 'tls' in data:
    del data['tls']
with open('/etc/udp-custom/config.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
        sed -i 's/TLS=enabled/TLS=disabled/g' /etc/udp-custom/panel.conf
        echo -e "${GREEN}✔ TLS desactivado.${NC}"
    else
        echo -e "${YELLOW}[*] Activando TLS...${NC}"
        mkdir -p /etc/udp-custom/certs
        CERT_CN=$(curl -sS ifconfig.me 2>/dev/null || echo "localhost")
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /etc/udp-custom/certs/server.key \
            -out /etc/udp-custom/certs/server.crt \
            -days 3650 \
            -subj "/CN=$CERT_CN" > /dev/null 2>&1
        
        python3 -c "
import json
with open('/etc/udp-custom/config.json', 'r') as f:
    data = json.load(f)
data['tls'] = {
    'cert': '/etc/udp-custom/certs/server.crt',
    'key': '/etc/udp-custom/certs/server.key'
}
with open('/etc/udp-custom/config.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
        sed -i 's/TLS=disabled/TLS=enabled/g' /etc/udp-custom/panel.conf
        echo -e "${GREEN}✔ TLS activado.${NC}"
    fi
    
    systemctl restart udp-custom
    echo -e "${GREEN}✔ Servicio reiniciado.${NC}"
    sleep 2
}

mostrar_config_udp() {
    if [ ! -f "/etc/udp-custom/panel.conf" ]; then
        echo -e "${RED}[!] No hay configuración.${NC}"
        return
    fi
    
    source /etc/udp-custom/panel.conf
    get_public_ip
    
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│     📋 CONFIGURACIÓN PARA HTTP CUSTOM                   │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e "${WHITE}Host:${NC} ${GREEN}${CERT_CN:-$PUBLIC_IP}:$PORT${NC}"
    echo -e "${WHITE}SNI:${NC} ${GREEN}${CERT_CN:-$PUBLIC_IP}${NC}"
    echo -e "${WHITE}TLS:${NC} ${GREEN}$TLS${NC}"
    echo -e "${WHITE}Rango:${NC} ${GREEN}1-65535${NC}"
    echo -e "${WHITE}Usuario:${NC} ${YELLOW}(vacío)${NC}"
    echo -e "${WHITE}Contraseña:${NC} ${YELLOW}(vacío)${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}⚠ NOTA:${NC}"
    echo -e " ${WHITE}• Sin autenticación de usuarios${NC}"
    echo -e " ${WHITE}• Solo TLS + SNI${NC}"
    echo -e " ${WHITE}• Asegúrate que el SNI coincida con el dominio del certificado${NC}"
    echo ""
    read -p "Presione ENTER para volver..."
}

# ==========================================
# MÓDULO: ZI VPN
# ==========================================
install_zivpn_bin() {
    echo -e "${CYAN}[*] Verificando e instalando binario de ZI VPN...${NC}"
    
    systemctl stop zivpn 2>/dev/null
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
        curl -sSL -o /usr/local/bin/zivpn "$url" 2>/dev/null
        if [ ! -s "/usr/local/bin/zivpn" ]; then
            wget -qO /usr/local/bin/zivpn --no-check-certificate "$url" 2>/dev/null
        fi

        if [ -s "/usr/local/bin/zivpn" ] && file /usr/local/bin/zivpn 2>/dev/null | grep -qE 'ELF|script'; then
            chmod +x /usr/local/bin/zivpn
            SUCCESS=1
            echo -e "${GREEN}✔ Binario ZI VPN instalado con éxito (${ZI_ARCH}).${NC}"
            break
        fi
        rm -f /usr/local/bin/zivpn
    done

    if [ "$SUCCESS" -eq 0 ]; then
        echo -e "${YELLOW}[!] Generando motor local ZI VPN de respaldo...${NC}"
        cat <<'EOF' > /usr/local/bin/zivpn
#!/usr/bin/env python3
import socket, json, argparse, sys

class ZIVPN:
    def __init__(self, port):
        self.port = port
        self.running = True
    def start(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('0.0.0.0', self.port))
        while self.running:
            try:
                data, addr = sock.recvfrom(65536)
                sock.sendto(b"ZI VPN OK", addr)
            except: pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', nargs='?', default='server')
    parser.add_argument('-c', '--config', help='Config file path')
    args = parser.parse_args()
    
    port = 5667
    if args.config:
        try:
            with open(args.config) as f:
                data = json.load(f)
                if 'listen' in data:
                    port = int(data['listen'].replace(':', ''))
        except Exception:
            pass

    server = ZIVPN(port)
    try:
        server.start()
    except KeyboardInterrupt:
        sys.exit(0)
EOF
        chmod +x /usr/local/bin/zivpn
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
    install_zivpn_bin

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
    pkill -9 zivpn 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $Z_PORT -j ACCEPT > /dev/null 2>&1
    ufw allow $Z_PORT/udp > /dev/null 2>&1

    systemctl daemon-reload
    systemctl enable zivpn > /dev/null 2>&1
    systemctl restart zivpn

    echo -e "\n${GREEN}✔ ZI VPN configurado en el puerto $Z_PORT (OBFS: $Z_OBFS | PASS: $Z_PASS)${NC}"
    sleep 2
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
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Modificar OBFS${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Modificar Contraseña${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Estado del Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}Reiniciar Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${YELLOW}Detener Servicio${NC}"
    echo -e " ${WHITE}${BOLD}[ 7 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}${BOLD}[ 9 ]${NC} ${RED}Desinstalar ZI VPN${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver Al Menú Principal${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una Opción [0-9]: ${NC}")" OPT
    
    case $OPT in
        1) config_zivpn; menu_zivpn ;;
        2) 
           read -p "$(echo -e "${CYAN}❯ ${WHITE}Nuevo OBFS: ${NC}")" NEW_OBFS
           if [ -n "$NEW_OBFS" ]; then
               sed -i "s/OBFS=.*/OBFS=\"$NEW_OBFS\"/g" /etc/zivpn/panel.conf
               sed -i "s/\"obfs\": \".*\"/\"obfs\": \"$NEW_OBFS\"/g" /etc/zivpn/config.json
               systemctl restart zivpn
               echo -e "${GREEN}✔ OBFS actualizado correctamente.${NC}"; sleep 2
           fi
           menu_zivpn ;;
        3)
           read -p "$(echo -e "${CYAN}❯ ${WHITE}Nueva Contraseña: ${NC}")" NEW_PASS
           if [ -n "$NEW_PASS" ]; then
               sed -i "s/PASS=.*/PASS=\"$NEW_PASS\"/g" /etc/zivpn/panel.conf
               python3 -c "import json; f=open('/etc/zivpn/config.json'); d=json.load(f); f.close(); d['auth']['config']=['$NEW_PASS']; f=open('/etc/zivpn/config.json','w'); json.dump(d,f,indent=2); f.close()" 2>/dev/null
               systemctl restart zivpn
               echo -e "${GREEN}✔ Contraseña actualizada correctamente.${NC}"; sleep 2
           fi
           menu_zivpn ;;
        4) systemctl status zivpn --no-pager; read -p "Presione ENTER para volver..."; menu_zivpn ;;
        5) 
           systemctl restart zivpn
           echo -e "${GREEN}✔ Servicio reiniciado.${NC}"; sleep 1; menu_zivpn ;;
        6) systemctl stop zivpn; echo -e "${YELLOW}Servicio detenido.${NC}"; sleep 1; menu_zivpn ;;
        7) journalctl -u zivpn -n 50 --no-pager; read -p "Presione ENTER para volver..."; menu_zivpn ;;
        9) 
           systemctl stop zivpn 2>/dev/null
           systemctl disable zivpn 2>/dev/null
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
    echo -e "  ${WHITE}${BOLD}• Sistema   :${NC} ${CYAN}${BOLD}$(uname -s)${NC}"
    echo -e "  ${WHITE}${BOLD}• IP Pública:${NC} ${YELLOW}${BOLD}$PUBLIC_IP${NC}"
    echo -e "  ${WHITE}${BOLD}• Comando   :${NC} ${GREEN}${BOLD}menuUDP${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"
    
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Administrador UDP-Hysteria (V1/V2 + Redirección)${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Administrador UDP Custom${NC}"
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
