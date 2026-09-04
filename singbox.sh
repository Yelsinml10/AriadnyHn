cat > /usr/local/bin/singbox << 'SINGBOX_EOF'
#!/bin/bash

# ==============================================================================
#  SING-BOX PRO CONTROL CENTER (ULTRA ANSI DASHBOARD EDITION)
# ==============================================================================

# Paleta ANSI 256-Color Premium
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

# Tonos Neón & Cyberpunk
C_VIOLET='\033[38;5;141m'
C_PURPLE='\033[38;5;99m'
C_CYAN='\033[38;5;51m'
C_BLUE='\033[38;5;39m'
C_GREEN='\033[38;5;48m'
C_YELLOW='\033[38;5;220m'
C_ORANGE='\033[38;5;208m'
C_RED='\033[38;5;196m'
C_PINK='\033[38;5;201m'
C_WHITE='\033[38;5;255m'
C_GRAY='\033[38;5;242m'
C_DARKGRAY='\033[38;5;236m'

# Fondos
BG_DARK='\033[48;5;235m'
BG_BADGE='\033[48;5;238m'

# Rutas del Sistema
CONF_DIR="/etc/sing-box"
CONF_FILE="${CONF_DIR}/config.json"
ENV_FILE="${CONF_DIR}/singbox.env"
INFO_FILE="${CONF_DIR}/singbox_info.txt"
BIN_PATH="/usr/local/bin/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${C_RED}${C_BOLD} [✖] Error: Ejecuta este panel como superusuario (root o sudo).${C_RESET}"
    exit 1
fi

clear_screen() { clear 2>/dev/null || printf '\033c'; }

pause() {
    echo ""
    echo -ne "  ${C_GRAY}Presiona ${C_WHITE}${C_BOLD}[ ENTER ]${C_RESET}${C_GRAY} para regresar al panel...${C_RESET}"
    read -r _ < /dev/tty 2>/dev/null || read -r _
}

flush_stdin() {
    while read -t 0.1 -n 10000 _ 2>/dev/null; do :; done
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi
}

save_env() {
    mkdir -p "$CONF_DIR"
    cat > "$ENV_FILE" <<EOF
VLESS_PORT="${VLESS_PORT}"
HY1_PORT="${HY1_PORT}"
HY2_PORT="${HY2_PORT}"
SNI_DOMAIN="${SNI_DOMAIN}"
UUID="${UUID}"
PUBLIC_KEY="${PUBLIC_KEY}"
PRIVATE_KEY="${PRIVATE_KEY}"
SHORT_ID="${SHORT_ID}"
HY_PASS="${HY_PASS}"
USE_DOMAIN="${USE_DOMAIN}"
MY_DOMAIN="${MY_DOMAIN}"
PUBLIC_IP="${PUBLIC_IP}"
USE_OBFS="${USE_OBFS}"
OBFS_PASS="${OBFS_PASS}"
EOF
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)  SARCH="amd64" ;;
        aarch64|arm64) SARCH="arm64" ;;
        armv7*|armhf)  SARCH="armv7" ;;
        *) SARCH="amd64" ;;
    esac
}

install_dependencies() {
    echo -e "  ${C_CYAN}➔ Verificando módulos de red y utilidades...${C_RESET}"
    export DEBIAN_FRONTEND=noninteractive
    local pkgs=(curl wget openssl tar socat jq qrencode net-tools iproute2 systemd-timesyncd)
    local missing=()
    
    for pkg in "${pkgs[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "  ${C_YELLOW}➔ Instalando: ${missing[*]}${C_RESET}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y >/dev/null 2>&1
            apt-get install -y "${missing[@]}" >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "${missing[@]}" >/dev/null 2>&1
        fi
    fi
    timedatectl set-ntp true 2>/dev/null || true
}

optimize_system() {
    sysctl -w net.core.rmem_max=8000000 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=8000000 >/dev/null 2>&1
    
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        modprobe tcp_bbr 2>/dev/null || true
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.core.rmem_max=8000000" >> /etc/sysctl.conf
        echo "net.core.wmem_max=8000000" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
}

update_firewall() {
    local tcp_p="$1"
    local hy1_p="$2"
    local hy2_p="$3"

    iptables -I INPUT 1 -p tcp --dport "$tcp_p" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT 1 -p udp --dport "$hy1_p" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT 1 -p udp --dport "$hy2_p" -j ACCEPT 2>/dev/null || true

    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        [[ -n "$tcp_p" ]] && ufw allow "$tcp_p"/tcp >/dev/null 2>&1
        [[ -n "$hy1_p" ]] && ufw allow "$hy1_p"/udp >/dev/null 2>&1
        [[ -n "$hy2_p" ]] && ufw allow "$hy2_p"/udp >/dev/null 2>&1
    fi
}

install_singbox_binary() {
    detect_arch
    local latest_ver
    latest_ver=$(curl -s --connect-timeout 5 https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
    latest_ver=${latest_ver:-"1.10.7"}

    echo -e "  ${C_CYAN}➔ Instalando binario Sing-Box v${latest_ver} (${SARCH})...${C_RESET}"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${latest_ver}/sing-box-${latest_ver}-linux-${SARCH}.tar.gz"
    
    rm -f /tmp/singbox.tar.gz
    if ! curl -# -fL --connect-timeout 10 --max-time 60 "$download_url" -o /tmp/singbox.tar.gz; then
        echo -e "${C_RED} [✖] Falló la descarga de Sing-Box.${C_RESET}"
        return 1
    fi

    tar -xzf /tmp/singbox.tar.gz -C /tmp/
    find /tmp/ -type f -name "sing-box" -exec mv {} "$BIN_PATH" \;
    chmod +x "$BIN_PATH"
    rm -rf /tmp/sing-box* /tmp/singbox.tar.gz
    echo -e "  ${C_GREEN}✔ Binario instalado correctamente en ${BIN_PATH}${C_RESET}"
}

generate_ssl_certificate() {
    mkdir -p "$CONF_DIR"
    if [[ "$USE_DOMAIN" =~ ^[sSyY]$ ]] && [[ -n "$MY_DOMAIN" ]]; then
        echo -e "  ${C_CYAN}➔ Emitiendo SSL Let's Encrypt para ${C_BOLD}${MY_DOMAIN}${C_RESET}..."
        systemctl stop nginx 2>/dev/null || systemctl stop apache2 2>/dev/null || true
        
        if [[ ! -f "$HOME/.acme.sh/acme.sh" ]]; then
            curl -s https://get.acme.sh | sh -s email="admin@${MY_DOMAIN}" >/dev/null 2>&1
        fi

        "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1
        if "$HOME/.acme.sh/acme.sh" --issue -d "$MY_DOMAIN" --standalone --httpport 80 --force >/dev/null 2>&1; then
            "$HOME/.acme.sh/acme.sh" --install-cert -d "$MY_DOMAIN" \
                --key-file "${CONF_DIR}/hy_key.pem" \
                --fullchain-file "${CONF_DIR}/hy_cert.pem" >/dev/null 2>&1
            return 0
        fi
    fi

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${CONF_DIR}/hy_key.pem" \
        -out "${CONF_DIR}/hy_cert.pem" \
        -days 3650 \
        -subj "/CN=bing.com" \
        -addext "subjectAltName=DNS:bing.com,DNS:www.microsoft.com,DNS:${MY_DOMAIN:-arm3.freenethn.org},IP:${PUBLIC_IP}" >/dev/null 2>&1
}

generate_reality_pair() {
    local keys
    keys=$("$BIN_PATH" generate reality-keypair 2>/dev/null)
    PRIVATE_KEY=$(echo "$keys" | grep -i "PrivateKey" | awk '{print $2}')
    PUBLIC_KEY=$(echo "$keys" | grep -i "PublicKey" | awk '{print $2}')
    
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        PRIVATE_KEY=$(echo "$keys" | awk 'NR==1 {print $2}')
        PUBLIC_KEY=$(echo "$keys" | awk 'NR==2 {print $2}')
    fi
}

build_and_restart() {
    mkdir -p "$CONF_DIR"

    if [[ ! -f "${CONF_DIR}/hy_cert.pem" || ! -f "${CONF_DIR}/hy_key.pem" ]]; then
        generate_ssl_certificate
    fi

    local hy_sni hy_insecure
    if [[ "$USE_DOMAIN" =~ ^[sSyY]$ ]] && [[ -n "$MY_DOMAIN" ]]; then
        hy_sni="$MY_DOMAIN"
        hy_insecure="0"
    else
        hy_sni="${MY_DOMAIN:-bing.com}"
        hy_insecure="1"
    fi

    local hy1_obfs_json=""
    local hy2_obfs_json=""
    local hy1_obfs_param=""
    local hy2_obfs_param=""
    local obfs_display="Desactivada"

    if [[ "$USE_OBFS" =~ ^[sSyY]$ ]] && [[ -n "$OBFS_PASS" ]]; then
        hy1_obfs_json="\"obfs\": \"${OBFS_PASS}\","
        hy2_obfs_json="\"obfs\": { \"type\": \"salamander\", \"password\": \"${OBFS_PASS}\" },"
        hy1_obfs_param="&alpn=hysteria&obfs=xplus&obfsParam=${OBFS_PASS}&obfs_param=${OBFS_PASS}"
        hy2_obfs_param="&obfs=salamander&obfs-password=${OBFS_PASS}"
        obfs_display="Activa (Clave: ${OBFS_PASS})"
    fi

    HY1_LINK="hysteria://${PUBLIC_IP}:${HY1_PORT}?protocol=udp&auth=${HY_PASS}&peer=${hy_sni}&insecure=${hy_insecure}&upmbps=100&downmbps=100${hy1_obfs_param}#SingBox-Hysteria1"
    HY2_LINK="hysteria2://${HY_PASS}@${PUBLIC_IP}:${HY2_PORT}/?sni=${hy_sni}&insecure=${hy_insecure}${hy2_obfs_param}#SingBox-Hysteria2"
    VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${VLESS_PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&spx=%2F&type=tcp&sni=${SNI_DOMAIN}&sid=${SHORT_ID}&flow=xtls-rprx-vision#SingBox-VLESS-REALITY"

    cat > "$CONF_FILE" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": ${VLESS_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI_DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "hysteria",
      "tag": "hysteria1-in",
      "listen": "0.0.0.0",
      "listen_port": ${HY1_PORT},
      "up_mbps": 100,
      "down_mbps": 100,
      ${hy1_obfs_json}
      "users": [
        {
          "auth_str": "${HY_PASS}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CONF_DIR}/hy_cert.pem",
        "key_path": "${CONF_DIR}/hy_key.pem"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "0.0.0.0",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "password": "${HY_PASS}"
        }
      ],
      "ignore_client_bandwidth": false,
      "up_mbps": 100,
      "down_mbps": 100,
      ${hy2_obfs_json}
      "tls": {
        "enabled": true,
        "certificate_path": "${CONF_DIR}/hy_cert.pem",
        "key_path": "${CONF_DIR}/hy_key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-Box Universal Proxy Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${BIN_PATH} run -c ${CONF_FILE}
Restart=always
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1
    systemctl restart sing-box

    update_firewall "$VLESS_PORT" "$HY1_PORT" "$HY2_PORT"
    save_env

    cat > "$INFO_FILE" <<EOF
===============================================================
               DETALLES DE ACCESO SING-BOX
===============================================================
 IP Servidor       : ${PUBLIC_IP}
 Estado            : ACTIVO
 Ofuscación (OBFS) : ${obfs_display}

 ---------------------------------------------------------------
 [ 1. VLESS REALITY (TCP + Vision) ]
 ├─ Puerto          : ${VLESS_PORT}
 ├─ UUID            : ${UUID}
 ├─ Clave Pública   : ${PUBLIC_KEY}
 ├─ Short ID        : ${SHORT_ID}
 └─ SNI Destino     : ${SNI_DOMAIN}

 ${VLESS_LINK}

 ---------------------------------------------------------------
 [ 2. HYSTERIA VERSION 1 (UDP) ]
 ├─ Puerto UDP      : ${HY1_PORT}
 ├─ Auth Password   : ${HY_PASS}
 ├─ SNI (Peer)      : ${hy_sni}
 ├─ Insecure (Skip) : ${hy_insecure}
 ├─ Tipo OBFS       : $([[ "$USE_OBFS" =~ ^[sSyY]$ ]] && echo "xplus" || echo "Ninguno")
 └─ Clave OBFS      : ${OBFS_PASS:-"Desactivada"}

 ${HY1_LINK}

 ---------------------------------------------------------------
 [ 3. HYSTERIA VERSION 2 (UDP/QUIC) ]
 ├─ Puerto UDP      : ${HY2_PORT}
 ├─ Contraseña      : ${HY_PASS}
 ├─ SNI             : ${hy_sni}
 ├─ Insecure (Skip) : ${hy_insecure}
 └─ OBFS Salamander : ${OBFS_PASS:-"Desactivada"}

 ${HY2_LINK}
===============================================================
EOF
}

# Generador gráfico de barras visuales para telemetría
render_bar() {
    local val=$1
    local max=100
    local width=10
    local filled=$(( val * width / max ))
    local empty=$(( width - filled ))
    local bar=""
    
    local color="${C_GREEN}"
    if (( val > 70 )); then color="${C_YELLOW}"; fi
    if (( val > 85 )); then color="${C_RED}"; fi

    for ((i=0; i<filled; i++)); do bar+="█"; done
    local rest=""
    for ((i=0; i<empty; i++)); do rest+="░"; done
    echo -e "${color}${bar}${C_DARKGRAY}${rest}${C_RESET} ${color}${val}%${C_RESET}"
}

get_system_telemetry() {
    local cpu_raw ram_raw conns uptime_raw
    cpu_raw=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($2 + $4)}')
    cpu_raw=${cpu_raw:-0}
    
    ram_raw=$(free 2>/dev/null | awk '/Mem:/ { printf("%d", $3/$2*100) }')
    ram_raw=${ram_raw:-0}
    
    conns=$(ss -ant 2>/dev/null | grep -c ESTAB)
    uptime_raw=$(uptime -p 2>/dev/null | sed 's/up //; s/ hours\?/h/; s/ minutes\?/m/; s/ days\?/d/' | cut -d',' -f1,2)
    uptime_raw=${uptime_raw:-"Activo"}

    echo -e "  ${C_CYAN}CPU:${C_RESET} $(render_bar "$cpu_raw")   ${C_VIOLET}RAM:${C_RESET} $(render_bar "$ram_raw")   ${C_CYAN}Conexiones:${C_RESET} ${C_BOLD}${C_WHITE}${conns}${C_RESET}   ${C_VIOLET}Uptime:${C_RESET} ${C_BOLD}${C_WHITE}${uptime_raw}${C_RESET}"
}

interactive_install() {
    clear_screen
    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│             INSTALADOR GUIADO • SING-BOX MULTI-PROTOCOLO                   │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}\n"

    install_dependencies
    optimize_system
    install_singbox_binary || return 1

    PUBLIC_IP=$(curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo -e " ${C_PINK}${C_BOLD}[ 1/5 ] Configuración de Puertos${C_RESET}"
    local def_vless=443
    echo -ne "   ${C_CYAN}➔${C_RESET} Puerto TCP VLESS Reality [Default: ${C_GREEN}${def_vless}${C_RESET}]: "
    read -r in_vless < /dev/tty 2>/dev/null || read -r in_vless
    VLESS_PORT=${in_vless:-$def_vless}

    local def_hy1=8444
    echo -ne "   ${C_CYAN}➔${C_RESET} Puerto UDP Hysteria 1 [Default: ${C_GREEN}${def_hy1}${C_RESET}]: "
    read -r in_hy1 < /dev/tty 2>/dev/null || read -r in_hy1
    HY1_PORT=${in_hy1:-$def_hy1}

    local def_hy2=8445
    echo -ne "   ${C_CYAN}➔${C_RESET} Puerto UDP Hysteria 2 [Default: ${C_GREEN}${def_hy2}${C_RESET}]: "
    read -r in_hy2 < /dev/tty 2>/dev/null || read -r in_hy2
    HY2_PORT=${in_hy2:-$def_hy2}

    echo -e "\n ${C_PINK}${C_BOLD}[ 2/5 ] Dominio SNI REALITY${C_RESET}"
    local def_sni="dl.google.com"
    echo -ne "   ${C_CYAN}➔${C_RESET} SNI Destino [Default: ${C_GREEN}${def_sni}${C_RESET}]: "
    read -r in_sni < /dev/tty 2>/dev/null || read -r in_sni
    SNI_DOMAIN=${in_sni:-$def_sni}

    echo -e "\n ${C_PINK}${C_BOLD}[ 3/5 ] Ofuscación de Tráfico (OBFS)${C_RESET}"
    echo -e "   ${C_GRAY}Esencial para saltar inspección DPI de operadoras móviles.${C_RESET}"
    echo -ne "   ${C_CYAN}➔${C_RESET} ¿Activar ofuscación OBFS en Hy1 y Hy2? (s/n) [s]: "
    read -r USE_OBFS < /dev/tty 2>/dev/null || read -r USE_OBFS
    USE_OBFS=${USE_OBFS:-"s"}

    OBFS_PASS=""
    if [[ "$USE_OBFS" =~ ^[sSyY]$ ]]; then
        echo -ne "   ${C_CYAN}➔${C_RESET} Clave OBFS (Enter para aleatoria): "
        read -r custom_obfs < /dev/tty 2>/dev/null || read -r custom_obfs
        OBFS_PASS=${custom_obfs:-$(openssl rand -hex 8)}
        echo -e "   ${C_GREEN}✔ Clave asignada: ${C_BOLD}${OBFS_PASS}${C_RESET}"
    fi

    echo -e "\n ${C_PINK}${C_BOLD}[ 4/5 ] Dominio SNI / Host para Hysteria 1 y 2${C_RESET}"
    echo -ne "   ${C_CYAN}➔${C_RESET} Ingresa Host/SNI (ej: arm3.freenethn.org) [bing.com]: "
    read -r in_mydomain < /dev/tty 2>/dev/null || read -r in_mydomain
    MY_DOMAIN=${in_mydomain:-"bing.com"}
    USE_DOMAIN="n"

    echo -e "\n ${C_PINK}${C_BOLD}[ 5/5 ] Generando llaves criptográficas...${C_RESET}"
    UUID=$("$BIN_PATH" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    SHORT_ID=$(openssl rand -hex 4)
    HY_PASS=$(openssl rand -hex 12)
    generate_reality_pair

    build_and_restart

    clear_screen
    echo -e "  ${C_GREEN}${C_BOLD}✔ ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!${C_RESET}\n"
    [[ -f "$INFO_FILE" ]] && cat "$INFO_FILE"
    pause
}

show_info_and_qr() {
    clear_screen
    load_env
    if [[ ! -f "$INFO_FILE" ]]; then
        echo -e "\n  ${C_RED}[✖] No se encontró ninguna configuración activa.${C_RESET}"
        pause
        return
    fi

    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│                CREDENCIALES Y ENLACES DE CONEXIÓN                          │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
    echo -e "  ${C_CYAN}Servidor:${C_RESET} ${C_BOLD}${PUBLIC_IP}${C_RESET}  │  ${C_CYAN}Host/SNI Hy:${C_RESET} ${C_BOLD}${MY_DOMAIN:-"bing.com"}${C_RESET}\n"

    # Tarjeta VLESS REALITY
    echo -e "${C_DARKGRAY}╭─[ ${C_CYAN}${C_BOLD}PROTOCOLO 1: VLESS REALITY (TCP + XTLS Vision)${C_RESET}${C_DARKGRAY} ]───────────────────╮${C_RESET}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}Puerto:${C_RESET} ${C_GREEN}${VLESS_PORT}${C_RESET}  •  ${C_WHITE}SNI:${C_RESET} ${C_CYAN}${SNI_DOMAIN}${C_RESET}  •  ${C_WHITE}ShortID:${C_RESET} ${SHORT_ID}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}UUID:${C_RESET}   ${UUID}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}Pubkey:${C_RESET} ${PUBLIC_KEY}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_DIM}${VLESS_LINK}${C_RESET}"
    echo -e "${C_DARKGRAY}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
    echo -e "  ${C_CYAN}Código QR VLESS:${C_RESET}"
    qrencode -t ANSIUTF8 "${VLESS_LINK}" 2>/dev/null || echo -e "  ${C_GRAY}(qrencode no instalado)${C_RESET}"
    echo ""

    # Tarjeta Hysteria 1
    echo -e "${C_DARKGRAY}╭─[ ${C_PINK}${C_BOLD}PROTOCOLO 2: HYSTERIA VERSION 1 (UDP + OBFS xplus)${C_RESET}${C_DARKGRAY} ]───────────────╮${C_RESET}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}Puerto UDP:${C_RESET} ${C_GREEN}${HY1_PORT}${C_RESET}  •  ${C_WHITE}Auth:${C_RESET} ${HY_PASS}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}Ofuscación:${C_RESET} ${C_YELLOW}xplus${C_RESET}  •  ${C_WHITE}Clave OBFS:${C_RESET} ${C_GREEN}${OBFS_PASS:-"Desactivada"}${C_RESET}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_DIM}${HY1_LINK}${C_RESET}"
    echo -e "${C_DARKGRAY}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
    echo -e "  ${C_PINK}Código QR Hysteria 1:${C_RESET}"
    qrencode -t ANSIUTF8 "${HY1_LINK}" 2>/dev/null || echo -e "  ${C_GRAY}(qrencode no instalado)${C_RESET}"
    echo ""

    # Tarjeta Hysteria 2
    echo -e "${C_DARKGRAY}╭─[ ${C_PURPLE}${C_BOLD}PROTOCOLO 3: HYSTERIA VERSION 2 (UDP/QUIC + Salamander)${C_RESET}${C_DARKGRAY} ]───────────╮${C_RESET}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}Puerto UDP:${C_RESET} ${C_GREEN}${HY2_PORT}${C_RESET}  •  ${C_WHITE}Password:${C_RESET} ${HY_PASS}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_WHITE}Ofuscación:${C_RESET} ${C_YELLOW}Salamander${C_RESET}  •  ${C_WHITE}Clave OBFS:${C_RESET} ${C_GREEN}${OBFS_PASS:-"Desactivada"}${C_RESET}"
    echo -e "${C_DARKGRAY}│${C_RESET}  ${C_DIM}${HY2_LINK}${C_RESET}"
    echo -e "${C_DARKGRAY}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
    echo -e "  ${C_PURPLE}Código QR Hysteria 2:${C_RESET}"
    qrencode -t ANSIUTF8 "${HY2_LINK}" 2>/dev/null || echo -e "  ${C_GRAY}(qrencode no instalado)${C_RESET}"

    pause
}

change_ports() {
    clear_screen
    load_env
    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│                    MODIFICAR PUERTOS DE ENLACE                             │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}\n"
    echo -e "  ${C_WHITE}Puertos Actuales ➔${C_RESET}  VLESS: ${C_GREEN}${VLESS_PORT}${C_RESET}  │  Hy1: ${C_GREEN}${HY1_PORT}${C_RESET}  │  Hy2: ${C_GREEN}${HY2_PORT}${C_RESET}\n"

    echo -ne "  ${C_CYAN}➔${C_RESET} Nuevo puerto TCP VLESS [Enter = Mantener]: "
    read -r n_vl < /dev/tty 2>/dev/null || read -r n_vl
    echo -ne "  ${C_CYAN}➔${C_RESET} Nuevo puerto UDP Hy1   [Enter = Mantener]: "
    read -r n_h1 < /dev/tty 2>/dev/null || read -r n_h1
    echo -ne "  ${C_CYAN}➔${C_RESET} Nuevo puerto UDP Hy2   [Enter = Mantener]: "
    read -r n_h2 < /dev/tty 2>/dev/null || read -r n_h2

    [[ -n "$n_vl" && "$n_vl" =~ ^[0-9]+$ ]] && VLESS_PORT="$n_vl"
    [[ -n "$n_h1" && "$n_h1" =~ ^[0-9]+$ ]] && HY1_PORT="$n_h1"
    [[ -n "$n_h2" && "$n_h2" =~ ^[0-9]+$ ]] && HY2_PORT="$n_h2"

    build_and_restart
    echo -e "\n  ${C_GREEN}✔ Puertos reconfigurados y aplicados.${C_RESET}"
    pause
}

change_obfs() {
    clear_screen
    load_env
    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│              GESTIÓN DE OFUSCACIÓN (OBFS HY1 & HY2)                        │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}\n"
    local st_txt="${C_RED}DESACTIVADA${C_RESET}"
    if [[ "$USE_OBFS" =~ ^[sSyY]$ ]]; then
        st_txt="${C_GREEN}ACTIVADA${C_RESET} ${C_GRAY}(Clave: ${C_BOLD}${OBFS_PASS}${C_GRAY})${C_RESET}"
    fi
    echo -e "  ${C_WHITE}Estado actual:${C_RESET} ${st_txt}\n"
    echo -e "  ${C_CYAN}[ 1 ]${C_RESET} Activar / Regenerar Clave Automática"
    echo -e "  ${C_CYAN}[ 2 ]${C_RESET} Asignar Clave Manualmente"
    echo -e "  ${C_CYAN}[ 3 ]${C_RESET} Desactivar Ofuscación"
    echo -e "  ${C_GRAY}[ 0 ] Volver${C_RESET}\n"
    echo -ne "  ${C_BOLD}Selecciona una opción [0-3]:${C_RESET} "
    read -r ob_op < /dev/tty 2>/dev/null || read -r ob_op

    case $ob_op in
        1)
            USE_OBFS="s"
            OBFS_PASS=$(openssl rand -hex 8)
            build_and_restart
            echo -e "\n  ${C_GREEN}✔ Nueva clave aplicada: ${C_BOLD}${OBFS_PASS}${C_RESET}"
            ;;
        2)
            echo -ne "\n  ${C_CYAN}➔${C_RESET} Ingresa la nueva clave: "
            read -r custom_pass < /dev/tty 2>/dev/null || read -r custom_pass
            if [[ -n "$custom_pass" ]]; then
                USE_OBFS="s"
                OBFS_PASS="$custom_pass"
                build_and_restart
                echo -e "\n  ${C_GREEN}✔ Clave personalizada aplicada.${C_RESET}"
            fi
            ;;
        3)
            USE_OBFS="n"
            OBFS_PASS=""
            build_and_restart
            echo -e "\n  ${C_YELLOW}✔ Ofuscación desactivada.${C_RESET}"
            ;;
        *) return ;;
    esac
    pause
}

change_sni() {
    clear_screen
    load_env
    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│                 MODIFICAR DOMINIO SNI / HOST PAYLOAD                       │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}\n"
    echo -e "  ${C_WHITE}SNI VLESS Reality actual :${C_RESET} ${C_CYAN}${SNI_DOMAIN}${C_RESET}"
    echo -e "  ${C_WHITE}SNI / Host Hysteria      :${C_RESET} ${C_PINK}${MY_DOMAIN}${C_RESET}\n"
    echo -ne "  ${C_CYAN}➔${C_RESET} Nuevo SNI/Host Hysteria (ej: arm3.freenethn.org): "
    read -r n_sni < /dev/tty 2>/dev/null || read -r n_sni

    if [[ -n "$n_sni" ]]; then
        MY_DOMAIN="$n_sni"
        build_and_restart
        echo -e "\n  ${C_GREEN}✔ Host de Hysteria actualizado.${C_RESET}"
    fi
    pause
}

regenerate_credentials() {
    clear_screen
    load_env
    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│               REGENERACIÓN TOTAL DE CLAVES Y CERTIFICADOS                  │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}\n"
    echo -ne "  ${C_YELLOW}¿Estás seguro de renovar todas las credenciales criptográficas? (s/n):${C_RESET} "
    read -r conf < /dev/tty 2>/dev/null || read -r conf

    if [[ "$conf" =~ ^[sSyY]$ ]]; then
        UUID=$("$BIN_PATH" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        SHORT_ID=$(openssl rand -hex 4)
        HY_PASS=$(openssl rand -hex 12)
        [[ "$USE_OBFS" =~ ^[sSyY]$ ]] && OBFS_PASS=$(openssl rand -hex 8)
        generate_reality_pair
        rm -f "${CONF_DIR}/hy_cert.pem" "${CONF_DIR}/hy_key.pem"
        build_and_restart
        echo -e "\n  ${C_GREEN}✔ Nuevas llaves y tokens generados con éxito.${C_RESET}"
    fi
    pause
}

view_logs() {
    clear_screen
    echo -e "${C_VIOLET}${C_BOLD}╭────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}│                MONITOR DE LOGS EN TIEMPO REAL                              │${C_RESET}"
    echo -e "${C_VIOLET}${C_BOLD}╰────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
    echo -e "  ${C_GRAY}(Presiona ${C_WHITE}Ctrl + C${C_GRAY} para salir y volver al panel)${C_RESET}\n"
    sleep 1
    journalctl -u sing-box -f -n 40
}

menu_principal() {
    while true; do
        clear_screen
        load_env
        local status_indicator
        if systemctl is-active --quiet sing-box 2>/dev/null; then
            status_indicator="${C_GREEN}● ONLINE${C_RESET}"
        else
            status_indicator="${C_RED}○ OFFLINE${C_RESET}"
        fi

        # Header Visual con Banner Estilizado
        echo -e "${C_PURPLE}${C_BOLD} ╭──────────────────────────────────────────────────────────────────────────╮${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} │   ${C_CYAN}███████╗██╗███╗   ██╗ ██████╗       ██████╗  ██████╗ ██╗  ██╗${C_PURPLE}          │${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} │   ${C_CYAN}██╔════╝██║████╗  ██║██╔════╝       ██╔══██╗██╔═══██╗╚██╗██╔╝${C_PURPLE}          │${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} │   ${C_CYAN}███████╗██║██╔██╗ ██║██║  ███╗█████╗██████╔╝██║   ██║ ╚███╔╝ ${C_PURPLE}          │${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} │   ${C_CYAN}╚════██║██║██║╚██╗██║██║   ██║╚════╝██╔══██╗██║   ██║ ██╔██╗ ${C_PURPLE}          │${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} │   ${C_CYAN}███████║██║██║ ╚████║╚██████╔╝      ██████╔╝╚██████╔╝██╔╝ ██╗${C_PURPLE}          │${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} │   ${C_CYAN}╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝       ╚═════╝  ╚═════╝ ╚═╝  ╚═╝${C_PURPLE}  ${C_YELLOW}PRO v3.0${C_PURPLE} │${C_RESET}"
        echo -e "${C_PURPLE}${C_BOLD} ╰──────────────────────────────────────────────────────────────────────────╯${C_RESET}"

        # Tarjeta de Telemetría del Sistema
        echo -e "${C_DARKGRAY} ╭─[ ${C_WHITE}${C_BOLD}ESTADO DEL NODO${C_RESET}${C_DARKGRAY} ]─────────────────────────────────────────────────────────╮${C_RESET}"
        echo -e "   ${C_WHITE}Estado:${C_RESET} ${status_indicator}   ${C_DARKGRAY}│${C_RESET}   ${C_WHITE}IP VPS:${C_RESET} ${C_BOLD}${C_CYAN}${PUBLIC_IP}${C_RESET}   ${C_DARKGRAY}│${C_RESET}   ${C_WHITE}Núcleo:${C_RESET} ${C_BOLD}Sing-Box${C_RESET}"
        echo -e "$(get_system_telemetry)"
        echo -e "${C_DARKGRAY} ╰──────────────────────────────────────────────────────────────────────────╯${C_RESET}"

        # Matriz de Protocolos Activos
        local obfs_badge="${C_RED}OFF${C_RESET}"
        if [[ "$USE_OBFS" =~ ^[sSyY]$ ]]; then obfs_badge="${C_GREEN}ON (${OBFS_PASS})${C_RESET}"; fi

        echo -e "${C_DARKGRAY} ╭─[ ${C_WHITE}${C_BOLD}MATRIZ DE PROTOCOLOS ACTIVOS${C_RESET}${C_DARKGRAY} ]────────────────────────────────────────╮${C_RESET}"
        echo -e "   ${C_CYAN}● VLESS Reality${C_RESET} : Puerto ${C_BOLD}${VLESS_PORT}/TCP${C_RESET}   ${C_DARKGRAY}│${C_RESET} SNI: ${C_DIM}${SNI_DOMAIN}${C_RESET}"
        echo -e "   ${C_PINK}● Hysteria 1   ${C_RESET} : Puerto ${C_BOLD}${HY1_PORT}/UDP${C_RESET}   ${C_DARKGRAY}│${C_RESET} OBFS: ${C_YELLOW}xplus${C_RESET} • ${obfs_badge}"
        echo -e "   ${C_PURPLE}● Hysteria 2   ${C_RESET} : Puerto ${C_BOLD}${HY2_PORT}/UDP${C_RESET}   ${C_DARKGRAY}│${C_RESET} OBFS: ${C_YELLOW}Salamander${C_RESET} • ${obfs_badge}"
        echo -e "${C_DARKGRAY} ╰──────────────────────────────────────────────────────────────────────────╯${C_RESET}"

        # Rejilla de Opciones en Doble Columna
        echo -e "   ${C_VIOLET}${C_BOLD}[ GESTIÓN DE ACCESOS ]${C_RESET}                  ${C_VIOLET}${C_BOLD}[ CONTROL & SISTEMA ]${C_RESET}"
        echo -e "   ${C_CYAN}${C_BOLD}01.${C_RESET} 📋 Ver Enlaces & QR               ${C_BLUE}${C_BOLD}06.${C_RESET} 🚀 Optimizar BBR & Kernel"
        echo -e "   ${C_CYAN}${C_BOLD}02.${C_RESET} 🔌 Modificar Puertos              ${C_BLUE}${C_BOLD}07.${C_RESET} 📊 Monitor de Logs en Vivo"
        echo -e "   ${C_CYAN}${C_BOLD}03.${C_RESET} 🌐 Cambiar SNI / Host             ${C_GREEN}${C_BOLD}08.${C_RESET} 🔄 Reiniciar Sing-Box"
        echo -e "   ${C_CYAN}${C_BOLD}04.${C_RESET} 🛡️ Gestionar Ofuscación (OBFS)    ${C_ORANGE}${C_BOLD}09.${C_RESET} ⏹️ Detener Servicio"
        echo -e "   ${C_CYAN}${C_BOLD}05.${C_RESET} 🔑 Regenerar Todas las Claves     ${C_YELLOW}${C_BOLD}10.${C_RESET} ⚙️ Reconfigurar Desde Cero"
        echo -e "                                         ${C_RED}${C_BOLD}11.${C_RESET} 🗑️ Desinstalar Completamente"
        echo -e "   ${C_DARKGRAY}────────────────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "   ${C_GRAY}00. 🚪 Salir del Panel${C_RESET}\n"

        flush_stdin
        echo -ne "   ${C_BOLD}${C_WHITE}Selecciona una opción [0-11]:${C_RESET} "
        read -r op < /dev/tty 2>/dev/null || read -r op

        case $op in
            1|01) show_info_and_qr ;;
            2|02) change_ports ;;
            3|03) change_sni ;;
            4|04) change_obfs ;;
            5|05) regenerate_credentials ;;
            6|06) optimize_system; echo -e "\n  ${C_GREEN}✔ Parámetros BBR y búferes UDP actualizados.${C_RESET}"; pause ;;
            7|07) view_logs ;;
            8|08)
                systemctl restart sing-box
                echo -e "\n  ${C_GREEN}✔ Servicio reiniciado exitosamente.${C_RESET}"
                pause
                ;;
            9|09)
                systemctl stop sing-box
                echo -e "\n  ${C_YELLOW}✔ Servicio detenido.${C_RESET}"
                pause
                ;;
            10) interactive_install ;;
            11)
                clear_screen
                echo -e "\n  ${C_RED}${C_BOLD}⚠ ALERTA DE SEGURIDAD ⚠${C_RESET}"
                echo -e "  Se eliminará Sing-Box, los binarios y todos los certificados."
                echo -ne "  ¿Confirmas desinstalación completa? (s/n): "
                read -r conf < /dev/tty 2>/dev/null || read -r conf
                if [[ "$conf" =~ ^[sSyY]$ ]]; then
                    systemctl stop sing-box 2>/dev/null
                    systemctl disable sing-box 2>/dev/null
                    rm -rf "$CONF_DIR" "$SERVICE_FILE" "$BIN_PATH" /usr/local/bin/singbox /usr/bin/singbox
                    systemctl daemon-reload
                    echo -e "\n  ${C_GREEN}✔ Sing-Box ha sido desinstalado completamente.${C_RESET}\n"
                    exit 0
                fi
                ;;
            0|00) clear_screen; exit 0 ;;
            *) echo -e "  ${C_RED}Opción inválida.${C_RESET}"; sleep 0.8 ;;
        esac
    done
}

if [[ ! -f "$CONF_FILE" || ! -f "$ENV_FILE" ]]; then
    interactive_install
fi

menu_principal
SINGBOX_EOF

chmod +x /usr/local/bin/singbox
ln -sf /usr/local/bin/singbox /usr/bin/singbox 2>/dev/null
singbox
