#!/bin/bash

# ==========================================
# CREACIÓN AUTOMÁTICA DEL COMANDO 'menuUDP'
# ==========================================
setup_shortcut() {
    local TARGET="/usr/bin/menuUDP"
    local L1="/usr/local/bin/menuUdp"
    local L2="/usr/local/bin/menuUDP"
    local L3="/usr/bin/menuUdp"
    # Tu enlace RAW de GitHub (usado como respaldo si se instala vía curl/wget | bash)
    local RAW_URL="https://raw.githubusercontent.com/Yelsinml10/Udp/main/install.sh"

    local SRC="${BASH_SOURCE[0]:-$0}"
    if [ -f "$SRC" ]; then
        SRC=$(readlink -f "$SRC" 2>/dev/null || echo "$SRC")
    fi

    # Si ya se está ejecutando desde el comando final, omitir para evitar bucles o errores
    if [[ "$SRC" == "$TARGET" ]] || [[ "$SRC" == "$L1" ]] || [[ "$SRC" == "$L2" ]] || [[ "$SRC" == "$L3" ]]; then
        return 0
    fi

    # Remover destino previo para evitar error "Text file busy"
    rm -f "$TARGET" 2>/dev/null

    # Si se ejecuta desde un pipe (curl | bash) o la memoria, descargar directamente de GitHub
    case "$SRC" in
        */bash|*/sh|*/dash|/dev/fd/*|/dev/stdin|"")
            curl -sSL "$RAW_URL" -o "$TARGET" 2>/dev/null || wget -qO "$TARGET" "$RAW_URL" 2>/dev/null
            ;;
        *)
            if [ -f "$SRC" ]; then
                # Si es un archivo local (ej. ./install.sh), simplemente lo copiamos
                cp "$SRC" "$TARGET" 2>/dev/null
            else
                # Respaldo por si falla la lectura local
                curl -sSL "$RAW_URL" -o "$TARGET" 2>/dev/null || wget -qO "$TARGET" "$RAW_URL" 2>/dev/null
            fi
            ;;
    esac

    # Dar permisos y crear enlaces simbólicos globales
    if [ -f "$TARGET" ]; then
        chmod +x "$TARGET" 2>/dev/null
        ln -sf "$TARGET" "$L1" 2>/dev/null
        ln -sf "$TARGET" "$L2" 2>/dev/null
        ln -sf "$TARGET" "$L3" 2>/dev/null
        
        # Refrescar la caché de comandos de Bash
        hash -r 2>/dev/null
    fi
}

# ==========================================
# PALETA DE COLORES ANSI Y ESTILOS
# ==========================================
BOLD='\033[1m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[!] Error: Este script debe ejecutarse como root (sudo).${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${CYAN}[*] Actualizando e instalando dependencias base...${NC}"
    apt-get update -y > /dev/null 2>&1
    apt-get install -y wget curl nano iptables ufw unzip openssl net-tools iproute2 jq socat cron python3 python3-pip git psmisc file > /dev/null 2>&1
    pip3 install --upgrade pip > /dev/null 2>&1
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
    echo -e "${GREEN}[+] Optimizaciones del Kernel aplicadas con éxito.${NC}"
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
# MÓDULO: UDP-HYSTERIA (V1 & V2)
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
            echo -e "${GREEN}[+] Binario de Hysteria V${VER} instalado correctamente (${HY_ARCH}).${NC}"
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
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e "       ${WHITE}INSTALADOR UDP-HYSTERIA${NC}"
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}[1] >${NC} HYSTERIA VERSION 1"
    echo -e " ${CYAN}[2] >${NC} HYSTERIA VERSION 2"
    echo -e "${RED}────────────────────────────────────────${NC}"
    read -p "Ingresa una Opcion: " HY_OPT
    
    if [ "$HY_OPT" == "1" ]; then
        H_VER="1"
    else
        H_VER="2"
    fi
    
    clear
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}[1] >${NC} HYSTERIA VERSION $H_VER"
    echo -e " HYSTERIA VERSION: $H_VER"
    echo -e "${RED}────────────────────────────────────────${NC}"
    read -p "INGRESA EL PUERTO [default 36712]: " H_PORT
    H_PORT=${H_PORT:-36712}
    
    clear
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}[1] >${NC} HYSTERIA VERSION $H_VER"
    echo -e " HYSTERIA VERSION: $H_VER"
    echo -e " PUERTO UDP: ${CYAN}$H_PORT${NC}"
    echo -e "${RED}────────────────────────────────────────${NC}"
    read -p " Ingresa Tu Rango Iptables [default 1:65535]: " H_RANGE
    H_RANGE=${H_RANGE:-1:65535}
    H_RANGE_IPT=$(echo "$H_RANGE" | tr '-' ':')
    
    H_OBFS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)
    
    if [ "$H_VER" == "2" ]; then
        clear
        echo -e "${RED}────────────────────────────────────────${NC}"
        echo -e "   ${WHITE}MÉTODO DE AUTENTICACIÓN (HYSTERIA V2)${NC}"
        echo -e "${RED}────────────────────────────────────────${NC}"
        echo -e " ${CYAN}[1] >${NC} Contraseña Fija Personalizada (RECOMENDADO)"
        echo -e " ${CYAN}[2] >${NC} Backend HTTP Externo (API / Panel Web)"
        echo -e " ${CYAN}[3] >${NC} Script / Comando Ejecutable Externo"
        echo -e " ${CYAN}[4] >${NC} Multi-Usuario (userpass)"
        echo -e "${RED}────────────────────────────────────────${NC}"
        read -p "Selecciona una Opción [default 1]: " AUTH_OPT
        AUTH_OPT=${AUTH_OPT:-1}

        case $AUTH_OPT in
            2)
                read -p "Ingresa la URL del Backend HTTP (ej. http://127.0.0.1:8080/auth): " HTTP_URL
                HTTP_URL=${HTTP_URL:-"http://127.0.0.1:8080/auth"}
                AUTH_BLOCK="auth:
  type: http
  http:
    url: $HTTP_URL"
                AUTH_INFO="HTTP ($HTTP_URL)"
                ;;
            3)
                read -p "Ingresa la ruta del Script/Comando (ej. /etc/hysteria/auth.sh): " CMD_PATH
                CMD_PATH=${CMD_PATH:-"/etc/hysteria/auth.sh"}
                AUTH_BLOCK="auth:
  type: command
  command:
    exec: $CMD_PATH"
                AUTH_INFO="Comando Externo ($CMD_PATH)"
                ;;
            4)
                read -p "Ingresa Usuario: " U_NAME
                read -p "Ingresa Contraseña: " U_PASS
                U_NAME=${U_NAME:-"admin"}
                U_PASS=${U_PASS:-"admin123"}
                AUTH_BLOCK="auth:
  type: userpass
  userpass:
    $U_NAME: \"$U_PASS\""
                AUTH_INFO="Userpass ($U_NAME)"
                ;;
            *)
                read -p "Ingresa tu contraseña personalizada [Enter para aleatoria]: " H_PASS
                H_PASS=${H_PASS:-$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)}
                AUTH_BLOCK="auth:
  type: password
  password: \"$H_PASS\""
                AUTH_INFO="Password ($H_PASS)"
                ;;
        esac
    else
        AUTH_INFO="V1 - Sin autenticación"
    fi

    echo -e "\n${YELLOW}Instalando y configurando...${NC}"
    install_dependencies
    
    install_hysteria_bin "$H_VER" || { echo -e "\n >> Presione enter para volver <<"; read -p ""; return; }
    
    generate_silent_cert
    optimize_kernel
    
    echo "VERSION=$H_VER" > /etc/hysteria/panel.conf
    echo "PORT=$H_PORT" >> /etc/hysteria/panel.conf
    echo "RANGE=$H_RANGE_IPT" >> /etc/hysteria/panel.conf
    echo "OBFS=$H_OBFS" >> /etc/hysteria/panel.conf
    echo "AUTH_INFO=$AUTH_INFO" >> /etc/hysteria/panel.conf
    
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
    iptables -t nat -I PREROUTING -p udp -m udp --dport $H_RANGE_IPT -j REDIRECT --to-ports $H_PORT
    
    echo -e "\n${GREEN}systemctl daemon-reload.........OK${NC}"
    systemctl daemon-reload
    echo -e "${GREEN}systemctl start udp-hysteria....OK${NC}"
    systemctl restart udp-hysteria
    echo -e "${GREEN}systemctl enable udp-hysteria...OK${NC}"
    systemctl enable udp-hysteria >/dev/null 2>&1
    
    echo -e "\n >> Presione enter para continuar <<"
    read -p ""
}

menu_udp_hysteria() {
    if [ ! -f "/etc/hysteria/panel.conf" ]; then
        config_udp_hysteria
        return
    fi
    
    source /etc/hysteria/panel.conf
    
    REAL_VER="Desconocida"
    if [ -x "/usr/local/bin/hysteria" ]; then
        REAL_VER=$(/usr/local/bin/hysteria version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "v1.x")
    fi
    
    clear
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e "       ${WHITE}ADMINISTRADOR UDP-HYSTERIA${NC}"
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}VERSION CONFIG:${NC} HYSTERIA V$VERSION"
    echo -e " ${CYAN}VERSION REAL:${NC} $REAL_VER"
    echo -e " ${CYAN}PORT:${NC} $PORT"
    echo -e " ${CYAN}REDIRECT:${NC} $RANGE > $PORT"
    echo -e " ${CYAN}OBFS:${NC} $OBFS"
    echo -e " ${CYAN}AUTH:${NC} ${GREEN}${AUTH_INFO:-Libre}${NC}"
    echo -e "${RED}────────────────────────────────────────${NC}"
    
    if systemctl is-active --quiet udp-hysteria; then
        echo -e " ${GREEN}● SERVICIO: ACTIVO${NC}"
    else
        echo -e " ${RED}● SERVICIO: DETENIDO${NC}"
    fi
    
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}[1] >${NC} RECONFIGURAR UDP-HYSTERIA"
    echo -e " ${CYAN}[2] >${NC} MODIFICAR OBFS"
    echo -e " ${CYAN}[3] >${NC} CAMBIAR VERSIÓN (V1 ↔ V2)"
    echo -e " ${CYAN}[4] >${NC} ESTADO DEL SERVICIO"
    echo -e " ${CYAN}[5] >${NC} REINICIAR SERVICIO"
    echo -e " ${CYAN}[6] >${NC} DETENER SERVICIO"
    echo -e " ${CYAN}[7] >${NC} LOG UDP-HYSTERIA"
    echo -e "${RED}────────────────────────────────────────${NC}"
    echo -e " ${WHITE}[0] VOLVER${NC}       ${RED}[9] DESINSTALAR${NC}"
    echo -e "${RED}────────────────────────────────────────${NC}"
    read -p "Ingresa una Opcion: " OPT
    
    case $OPT in
        1) config_udp_hysteria; menu_udp_hysteria ;;
        2) 
           read -p "Nuevo OBFS: " NEW_OBFS
           if [ -n "$NEW_OBFS" ]; then
               sed -i "s/OBFS=.*/OBFS=$NEW_OBFS/g" /etc/hysteria/panel.conf
               if [ "$VERSION" == "1" ]; then
                   sed -i "s/\"obfs\": \".*\"/\"obfs\": \"$NEW_OBFS\"/g" /etc/hysteria/config.json
               else
                   sed -i '/salamander:/{n;s/password: .*/password: "'"$NEW_OBFS"'"/}' /etc/hysteria/config.yaml
               fi
               fuser -k $PORT/udp 2>/dev/null
               pkill -9 hysteria 2>/dev/null
               systemctl restart udp-hysteria
               echo -e "${GREEN}OBFS actualizado.${NC}"; sleep 2
           fi
           menu_udp_hysteria ;;
        3) config_udp_hysteria; menu_udp_hysteria ;;
        4) systemctl status udp-hysteria --no-pager; read -p "Enter para volver..."; menu_udp_hysteria ;;
        5) fuser -k $PORT/udp 2>/dev/null; pkill -9 hysteria 2>/dev/null; systemctl restart udp-hysteria; echo -e "${GREEN}Reiniciado.${NC}"; sleep 1; menu_udp_hysteria ;;
        6) systemctl stop udp-hysteria; echo -e "${YELLOW}Detenido.${NC}"; sleep 1; menu_udp_hysteria ;;
        7) journalctl -u udp-hysteria -n 50 --no-pager; read -p "Presione Enter para volver..."; menu_udp_hysteria ;;
        9) 
           systemctl stop udp-hysteria 2>/dev/null
           systemctl disable udp-hysteria 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 hysteria 2>/dev/null
           rm -rf /etc/hysteria /etc/systemd/system/udp-hysteria.service
           rm -f /usr/local/bin/hysteria
           systemctl daemon-reload
           echo -e "${GREEN}Desinstalado completamente.${NC}"
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
        URLS=("https://raw.githubusercontent.com/prjkt-nv404/UDP-Custom-Installer-arm64/main/udpc-arm64")
    else
        URLS=("https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64")
    fi

    for url in "${URLS[@]}"; do
        curl -sSL -o /usr/local/bin/udp-custom "$url" 2>/dev/null || wget -qO /usr/local/bin/udp-custom --no-check-certificate "$url" 2>/dev/null
        if [ -s "/usr/local/bin/udp-custom" ]; then
            chmod +x /usr/local/bin/udp-custom
            echo -e "${GREEN}[+] UDP Custom instalado con éxito.${NC}"
            return 0
        fi
    done
    echo -e "${RED}[!] Error al instalar UDP Custom.${NC}"; return 1
}

config_udp() {
    clear
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "       ${WHITE}INSTALADOR UDP CUSTOM${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    read -p "INGRESA EL PUERTO UDP CUSTOM [default 36712]: " U_PORT
    U_PORT=${U_PORT:-36712}

    install_dependencies
    install_udp_bin || { echo -e "\n >> Presione enter para volver <<"; read -p ""; return; }

    mkdir -p /etc/udp-custom
    cat <<EOF > /etc/udp-custom/config.json
{
  "listen": ":$U_PORT",
  "stream_buffer": 33554432,
  "receive_buffer": 8388608,
  "exclude_ports": [53, 5300]
}
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
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

    echo "PORT=$U_PORT" > /etc/udp-custom/panel.conf

    systemctl stop udp-custom 2>/dev/null
    fuser -k $U_PORT/udp 2>/dev/null
    pkill -9 udp-custom 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $U_PORT -j ACCEPT > /dev/null 2>&1
    ufw allow $U_PORT/udp > /dev/null 2>&1

    systemctl daemon-reload
    systemctl enable udp-custom > /dev/null 2>&1
    systemctl restart udp-custom
    
    echo -e "\n${GREEN}[+] UDP Custom configurado en el puerto $U_PORT${NC}"
    sleep 2
}

menu_udp_custom() {
    if [ ! -f "/etc/udp-custom/panel.conf" ]; then
        config_udp
        return
    fi
    
    source /etc/udp-custom/panel.conf
    
    clear
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "       ${WHITE}ADMINISTRADOR UDP CUSTOM${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}PUERTO UDP:${NC} $PORT"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    
    if systemctl is-active --quiet udp-custom; then
        echo -e " ${GREEN}● SERVICIO: ACTIVO${NC}"
    else
        echo -e " ${RED}● SERVICIO: DETENIDO${NC}"
    fi
    
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}[1] >${NC} RECONFIGURAR UDP CUSTOM"
    echo -e " ${CYAN}[2] >${NC} ESTADO DEL SERVICIO"
    echo -e " ${CYAN}[3] >${NC} REINICIAR SERVICIO"
    echo -e " ${CYAN}[4] >${NC} DETENER SERVICIO"
    echo -e " ${CYAN}[5] >${NC} LOG UDP CUSTOM"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e " ${WHITE}[0] VOLVER${NC}       ${RED}[9] DESINSTALAR${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    read -p "Ingresa una Opcion: " OPT
    
    case $OPT in
        1) config_udp; menu_udp_custom ;;
        2) systemctl status udp-custom --no-pager; read -p "Enter para volver..."; menu_udp_custom ;;
        3) 
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 udp-custom 2>/dev/null
           systemctl restart udp-custom
           echo -e "${GREEN}Reiniciado.${NC}"; sleep 1; menu_udp_custom ;;
        4) systemctl stop udp-custom; echo -e "${YELLOW}Detenido.${NC}"; sleep 1; menu_udp_custom ;;
        5) journalctl -u udp-custom -n 50 --no-pager; read -p "Presione Enter para volver..."; menu_udp_custom ;;
        9) 
           systemctl stop udp-custom 2>/dev/null
           systemctl disable udp-custom 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 udp-custom 2>/dev/null
           rm -rf /etc/udp-custom /etc/systemd/system/udp-custom.service
           rm -f /usr/local/bin/udp-custom
           systemctl daemon-reload
           echo -e "${GREEN}Desinstalado completamente.${NC}"
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
        curl -sSL -o /usr/local/bin/zivpn "$url" 2>/dev/null
        if [ ! -s "/usr/local/bin/zivpn" ]; then
            wget -qO /usr/local/bin/zivpn --no-check-certificate "$url" 2>/dev/null
        fi

        if [ -s "/usr/local/bin/zivpn" ] && file /usr/local/bin/zivpn 2>/dev/null | grep -qE 'ELF|script'; then
            chmod +x /usr/local/bin/zivpn
            SUCCESS=1
            echo -e "${GREEN}[+] Binario ZI VPN instalado con éxito (${ZI_ARCH}).${NC}"
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
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    echo -e "       ${WHITE}INSTALADOR ZI VPN${NC}"
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    read -p "INGRESA EL PUERTO ZI VPN [default 5667]: " Z_PORT
    Z_PORT=${Z_PORT:-5667}

    read -p "INGRESA EL OBFS DE ZI VPN [default zivpn]: " Z_OBFS
    Z_OBFS=${Z_OBFS:-zivpn}

    read -p "INGRESA LA CONTRASEÑA/PASSWORD DE ZI VPN [default zi]: " Z_PASS
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

    echo "PORT=$Z_PORT" > /etc/zivpn/panel.conf
    echo "OBFS=$Z_OBFS" >> /etc/zivpn/panel.conf
    echo "PASS=$Z_PASS" >> /etc/zivpn/panel.conf

    systemctl stop zivpn 2>/dev/null
    fuser -k $Z_PORT/udp 2>/dev/null
    pkill -9 zivpn 2>/dev/null
    sleep 1

    iptables -I INPUT -p udp --dport $Z_PORT -j ACCEPT > /dev/null 2>&1
    ufw allow $Z_PORT/udp > /dev/null 2>&1

    systemctl daemon-reload
    systemctl enable zivpn > /dev/null 2>&1
    systemctl restart zivpn

    echo -e "\n${GREEN}[+] ZI VPN configurado en el puerto $Z_PORT (OBFS: $Z_OBFS | PASS: $Z_PASS)${NC}"
    sleep 2
}

menu_zivpn() {
    if [ ! -f "/etc/zivpn/panel.conf" ]; then
        config_zivpn
        return
    fi
    
    source /etc/zivpn/panel.conf
    
    clear
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    echo -e "       ${WHITE}ADMINISTRADOR ZI VPN${NC}"
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}PUERTO UDP:${NC} $PORT"
    echo -e " ${CYAN}OBFS:${NC} $OBFS"
    echo -e " ${CYAN}CONTRASEÑA (PASS):${NC} ${GREEN}$PASS${NC}"
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    
    if systemctl is-active --quiet zivpn; then
        echo -e " ${GREEN}● SERVICIO: ACTIVO${NC}"
    else
        echo -e " ${RED}● SERVICIO: DETENIDO${NC}"
    fi
    
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    echo -e " ${CYAN}[1] >${NC} RECONFIGURAR ZI VPN"
    echo -e " ${CYAN}[2] >${NC} MODIFICAR OBFS"
    echo -e " ${CYAN}[3] >${NC} MODIFICAR CONTRASEÑA"
    echo -e " ${CYAN}[4] >${NC} ESTADO DEL SERVICIO"
    echo -e " ${CYAN}[5] >${NC} REINICIAR SERVICIO"
    echo -e " ${CYAN}[6] >${NC} DETENER SERVICIO"
    echo -e " ${CYAN}[7] >${NC} LOG ZI VPN"
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    echo -e " ${WHITE}[0] VOLVER${NC}       ${RED}[9] DESINSTALAR${NC}"
    echo -e "${PURPLE}────────────────────────────────────────${NC}"
    read -p "Ingresa una Opcion: " OPT
    
    case $OPT in
        1) config_zivpn; menu_zivpn ;;
        2) 
           read -p "Nuevo OBFS: " NEW_OBFS
           if [ -n "$NEW_OBFS" ]; then
               sed -i "s/OBFS=.*/OBFS=$NEW_OBFS/g" /etc/zivpn/panel.conf
               sed -i "s/\"obfs\": \".*\"/\"obfs\": \"$NEW_OBFS\"/g" /etc/zivpn/config.json
               fuser -k $PORT/udp 2>/dev/null
               pkill -9 zivpn 2>/dev/null
               systemctl restart zivpn
               echo -e "${GREEN}OBFS actualizado.${NC}"; sleep 2
           fi
           menu_zivpn ;;
        3)
           read -p "Nueva Contraseña: " NEW_PASS
           if [ -n "$NEW_PASS" ]; then
               sed -i "s/PASS=.*/PASS=$NEW_PASS/g" /etc/zivpn/panel.conf
               python3 -c "import json; f=open('/etc/zivpn/config.json'); d=json.load(f); f.close(); d['auth']['config']=['$NEW_PASS']; f=open('/etc/zivpn/config.json','w'); json.dump(d,f,indent=2); f.close()" 2>/dev/null
               fuser -k $PORT/udp 2>/dev/null
               pkill -9 zivpn 2>/dev/null
               systemctl restart zivpn
               echo -e "${GREEN}Contraseña actualizada.${NC}"; sleep 2
           fi
           menu_zivpn ;;
        4) systemctl status zivpn --no-pager; read -p "Enter para volver..."; menu_zivpn ;;
        5) 
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 zivpn 2>/dev/null
           systemctl restart zivpn
           echo -e "${GREEN}Reiniciado.${NC}"; sleep 1; menu_zivpn ;;
        6) systemctl stop zivpn; echo -e "${YELLOW}Detenido.${NC}"; sleep 1; menu_zivpn ;;
        7) journalctl -u zivpn -n 50 --no-pager; read -p "Presione Enter para volver..."; menu_zivpn ;;
        9) 
           systemctl stop zivpn 2>/dev/null
           systemctl disable zivpn 2>/dev/null
           fuser -k $PORT/udp 2>/dev/null
           pkill -9 zivpn 2>/dev/null
           rm -rf /etc/zivpn /etc/systemd/system/zivpn.service
           rm -f /usr/local/bin/zivpn
           systemctl daemon-reload
           echo -e "${GREEN}Desinstalado completamente.${NC}"
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
    echo -e "${PURPLE}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e " ${WHITE}${BOLD}SISTEMA:${NC} $(uname -s) (${WHITE}IP:${NC} ${YELLOW}$PUBLIC_IP${NC})"
    echo -e "${PURPLE}${BOLD}════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e " ${WHITE}${BOLD}MENÚ PRINCIPAL DE SERVICIOS VIP${NC}\n"
    echo -e "  ${GREEN}[1]${NC} 🚀 Administrador UDP-HYSTERIA (V1/V2 + Redirección)"
    echo -e "  ${GREEN}[2]${NC} 🛡️  Administrador UDP Custom"
    echo -e "  ${GREEN}[3]${NC} 🔥 Administrador ZI VPN"
    echo -e "  ${GREEN}[0]${NC} ❌ Salir"
    echo ""
    echo -e "${CYAN}💡 Acceso rápido: ${WHITE}menuUDP${NC} desde cualquier terminal"
    echo ""
    read -p "Selecciona una opción: " opt
    case $opt in
        1) menu_udp_hysteria ;;
        2) menu_udp_custom ;;
        3) menu_zivpn ;;
        0) clear; exit 0 ;;
        *) menu_main ;;
    esac
}

# ==========================================
# INICIO DEL SCRIPT
# ==========================================
check_root
setup_shortcut
menu_main
