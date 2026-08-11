cat > /usr/local/bin/singbox << 'SINGBOX_EOF'
#!/bin/bash

# =======================================================
# PANEL ADMINISTRATIVO DE SING-BOX
# =======================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

CONF_FILE="/etc/sing-box/config.json"
INFO_FILE="/root/singbox_info.txt"
BIN_PATH="/usr/local/bin/sing-box-bin"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${RED}Ejecuta este panel como root (sudo).${NC}"
    exit 1
fi

clear_screen() { clear 2>/dev/null || printf '\033c'; }

pause_screen() {
    echo ""
    echo -ne "${YELLOW}Presiona ENTER para continuar...${NC}"
    read -r discard < /dev/tty 2>/dev/null || read -r discard
}

flush_stdin() {
    while read -t 0.1 -n 10000 discard 2>/dev/null; do :; done
}

sync_time() {
    timedatectl set-ntp true 2>/dev/null
    systemctl restart systemd-timesyncd 2>/dev/null
}

show_info() {
    clear_screen
    if [[ -f "$INFO_FILE" ]]; then
        cat "$INFO_FILE"
    else
        echo -e "${RED}No se encontró la información de configuración.${NC}"
    fi
    pause_screen
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) SARCH="amd64" ;;
        aarch64|arm64) SARCH="arm64" ;;
        armv7*|armhf) SARCH="armv7" ;;
        *) SARCH="amd64" ;;
    esac
}

install_binary() {
    detect_arch
    echo -e " ${CYAN}➔ Arquitectura:${NC} ${BOLD}${ARCH} (${SARCH})${NC}"
    
    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
        echo -e " ${CYAN}➔ Instalando herramientas de sistema...${NC}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget openssl coreutils tar socat systemd-timesyncd >/dev/null 2>&1 || yum install -y curl wget openssl coreutils tar socat >/dev/null 2>&1
    fi

    SB_VER="1.9.3"
    echo -e " ${CYAN}➔ Descargando Sing-Box v${SB_VER}...${NC}"
    
    rm -f /tmp/sb.tar.gz
    curl -# -fL --connect-timeout 10 --max-time 45 \
        "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-${SARCH}.tar.gz" \
        -o /tmp/sb.tar.gz

    if [[ ! -s /tmp/sb.tar.gz ]]; then
        echo -e "${RED}Error al descargar Sing-Box.${NC}"
        rm -f /tmp/sb.tar.gz
        return 1
    fi

    echo -e " ${CYAN}➔ Instalando binario en la VPS...${NC}"
    tar -xzf /tmp/sb.tar.gz -C /tmp/
    mv /tmp/sing-box-*/sing-box "$BIN_PATH" 2>/dev/null || mv /tmp/sing-box "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf /tmp/sb*
    echo -e " ${GREEN}✔ Binario instalado correctamente.${NC}"
}

install_acme_cert() {
    local domain="$1"
    echo -e " ${CYAN}➔ Emitiendo certificado SSL de Let's Encrypt para ${BOLD}${domain}${NC}${CYAN}...${NC}"
    
    apt-get install -y socat >/dev/null 2>&1 || yum install -y socat >/dev/null 2>&1
    curl -s https://get.acme.sh | sh -s email="admin@${domain}" >/dev/null 2>&1
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    if ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --httpport 80 >/dev/null 2>&1; then
        ~/.acme.sh/acme.sh --install-cert -d "$domain" \
            --key-file /etc/sing-box/hy2_key.pem \
            --fullchain-file /etc/sing-box/hy2_cert.pem >/dev/null 2>&1
        echo -e " ${GREEN}✔ Certificado SSL Let's Encrypt emitido e instalado con éxito.${NC}"
        return 0
    else
        echo -e " ${RED}❌ No se pudo emitir el certificado (verifica que el puerto 80 esté libre y el dominio apunte a la IP de la VPS).${NC}"
        echo -e " ${YELLOW}➔ Se generará un certificado autofirmado como alternativa...${NC}"
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/sing-box/hy2_key.pem -out /etc/sing-box/hy2_cert.pem -days 3650 -subj "/CN=${domain}" >/dev/null 2>&1
        return 1
    fi
}

generate_reality_pair() {
    REALITY_KEYS=$("$BIN_PATH" generate reality-keypair 2>/dev/null)
    PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep -i "PrivateKey" | awk '{print $2}')
    PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep -i "PublicKey" | awk '{print $2}')
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk 'NR==1 {print $2}')
        PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk 'NR==2 {print $2}')
    fi
}

build_config_and_restart() {
    sync_time
    mkdir -p /etc/sing-box

    if [[ "$USE_DOMAIN" == "s" || "$USE_DOMAIN" == "S" ]] && [[ -n "$MY_DOMAIN" ]]; then
        install_acme_cert "$MY_DOMAIN"
        HY2_SNI="$MY_DOMAIN"
        HY2_INSECURE="false (Certificado Oficial Let's Encrypt)"
        HY2_LINK="hysteria2://${HY2_PASS}@${PUBLIC_IP}:${HY2_PORT}?sni=${MY_DOMAIN}#SingBox-Hysteria2"
    else
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/sing-box/hy2_key.pem -out /etc/sing-box/hy2_cert.pem -days 3650 -subj "/CN=bing.com" >/dev/null 2>&1
        HY2_SNI="bing.com"
        HY2_INSECURE="true (Certificado Autofirmado)"
        HY2_LINK="hysteria2://${HY2_PASS}@${PUBLIC_IP}:${HY2_PORT}?insecure=1&sni=bing.com#SingBox-Hysteria2"
    fi

    cat > "$CONF_FILE" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${VLESS_PORT},
      "users": [{ "uuid": "${UUID}", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SNI_DOMAIN}", "server_port": 443 },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [{ "password": "${HY2_PASS}" }],
      "ignore_client_bandwidth": true,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/hy2_cert.pem",
        "key_path": "/etc/sing-box/hy2_key.pem"
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF

    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=${BIN_PATH} run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1
    systemctl restart sing-box

    VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${VLESS_PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&spx=%2F&type=tcp&sni=${SNI_DOMAIN}&sid=${SHORT_ID}&flow=xtls-rprx-vision#SingBox-VLESS-REALITY"

    cat > "$INFO_FILE" <<EOF
=======================================================
       CONFIGURACIÓN SING-BOX INSTALADA
=======================================================
IP VPS: ${PUBLIC_IP}

--- VLESS REALITY ---
Puerto      : ${VLESS_PORT}
UUID        : ${UUID}
PublicKey   : ${PUBLIC_KEY}
ShortID     : ${SHORT_ID}
SNI (Target): ${SNI_DOMAIN}
Flow        : xtls-rprx-vision

Enlace VLESS:
${VLESS_LINK}

--- HYSTERIA 2 ---
Puerto UDP  : ${HY2_PORT}
Password    : ${HY2_PASS}
SNI         : ${HY2_SNI}
Insecure    : ${HY2_INSECURE}

Enlace HY2:
${HY2_LINK}
=======================================================
EOF
}

interactive_install() {
    clear_screen
    flush_stdin

    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│       CONFIGURACIÓN INICIAL DE SING-BOX                │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo ""

    PUBLIC_IP=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

    DEF_VLESS=8443
    ! ss -tulpn | grep -q ":443 " && DEF_VLESS=443

    echo -e "${YELLOW}${BOLD}PASO 1: Configurar Puertos, SNI y Certificado SSL${NC}\n"
    
    echo -ne " ${WHITE}[1] Puerto VLESS-REALITY [Predeterminado: ${DEF_VLESS}]: ${NC}"
    read -r input_vless < /dev/tty 2>/dev/null || read -r input_vless
    VLESS_PORT=${input_vless:-$DEF_VLESS}

    DEF_HY2=8444
    echo -ne " ${WHITE}[2] Puerto UDP Hysteria2 [Predeterminado: ${DEF_HY2}]: ${NC}"
    read -r input_hy2 < /dev/tty 2>/dev/null || read -r input_hy2
    HY2_PORT=${input_hy2:-$DEF_HY2}

    DEF_SNI="dl.google.com"
    echo -e " ${CYAN}💡 Nota REALITY: Usa dominios compatibles como dl.google.com o www.microsoft.com${NC}"
    echo -ne " ${WHITE}[3] Dominio SNI REALITY [Predeterminado: ${DEF_SNI}]: ${NC}"
    read -r input_sni < /dev/tty 2>/dev/null || read -r input_sni
    SNI_DOMAIN=${input_sni:-$DEF_SNI}

    echo ""
    echo -ne " ${WHITE}[4] ¿Tienes un dominio propio apuntando a la VPS para Hysteria2? (s/n) [Predeterminado: n]: ${NC}"
    read -r USE_DOMAIN < /dev/tty 2>/dev/null || read -r USE_DOMAIN
    
    MY_DOMAIN=""
    if [[ "$USE_DOMAIN" == "s" || "$USE_DOMAIN" == "S" ]]; then
        echo -ne "     Ingresa tu dominio (ej: vps.midominio.com): "
        read -r MY_DOMAIN < /dev/tty 2>/dev/null || read -r MY_DOMAIN
    fi

    echo -e "\n${GREEN}✔ Parámetros seleccionados:${NC}"
    echo -e "   • Puerto VLESS   : ${BOLD}${VLESS_PORT}${NC}"
    echo -e "   • Puerto Hy2 UDP : ${BOLD}${HY2_PORT}${NC}"
    echo -e "   • Dominio SNI    : ${BOLD}${SNI_DOMAIN}${NC}"
    if [[ -n "$MY_DOMAIN" ]]; then
        echo -e "   • Dominio Propio : ${BOLD}${MY_DOMAIN} (SSL Let's Encrypt)${NC}\n"
    else
        echo -e "   • Certificado    : ${BOLD}Autofirmado (Sin dominio)${NC}\n"
    fi

    if [[ ! -x "$BIN_PATH" ]]; then
        echo -e "${YELLOW}${BOLD}PASO 2: Instalando binario de Sing-Box${NC}"
        install_binary || return 1
        echo ""
    fi

    echo -e "${YELLOW}${BOLD}PASO 3: Generando llaves REALITY, UUID y certificados...${NC}"
    UUID=$("$BIN_PATH" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    generate_reality_pair

    SHORT_ID=$(openssl rand -hex 4)
    HY2_PASS=$(openssl rand -hex 12)

    build_config_and_restart
    echo -e "\n${GREEN}${BOLD}✔ Sing-Box se ha instalado y configurado correctamente.${NC}\n"
    
    if [[ -f "$INFO_FILE" ]]; then
        cat "$INFO_FILE"
    fi
    pause_screen
}

get_status() {
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        echo -e "${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e "${RED}[DETENIDO / STOPPED]${NC}"
    fi
}

menu_principal() {
    while true; do
        clear_screen
        echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}${BOLD}│         PANEL DE ADMINISTRACIÓN SING-BOX               │${NC}"
        echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
        echo -e " ${PURPLE}${BOLD}Estado del Servicio :${NC} $(get_status)"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        echo -e " ${WHITE}[ 1 ]${NC} ${GREEN}Ver Información y Enlaces de Conexión${NC}"
        echo -e " ${WHITE}[ 2 ]${NC} ${CYAN}Cambiar Puertos (VLESS / Hysteria2)${NC}"
        echo -e " ${WHITE}[ 3 ]${NC} ${CYAN}Cambiar Dominio SNI (REALITY)${NC}"
        echo -e " ${WHITE}[ 4 ]${NC} ${CYAN}Regenerar Llaves REALITY y Enlaces${NC}"
        echo -e " ${WHITE}[ 5 ]${NC} ${CYAN}Ver Estado Detallado / Logs${NC}"
        echo -e " ${WHITE}[ 6 ]${NC} ${GREEN}Reiniciar Servicio Sing-Box${NC}"
        echo -e " ${WHITE}[ 7 ]${NC} ${YELLOW}Reinstalar / Reconfigurar Desde Cero${NC}"
        echo -e " ${WHITE}[ 8 ]${NC} ${RED}Desinstalar Sing-Box Completamente${NC}"
        echo -e " ${WHITE}[ 0 ]${NC} ${YELLOW}Salir${NC}"
        echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
        flush_stdin
        echo -ne " Selecciona una opción [0-8]: "
        read -r op < /dev/tty 2>/dev/null || read -r op

        case $op in
            1) show_info ;;
            2)
                echo -ne " Nuevo puerto VLESS (REALITY): "
                read -r new_vless < /dev/tty 2>/dev/null || read -r new_vless
                echo -ne " Nuevo puerto Hysteria 2 (UDP): "
                read -r new_hy2 < /dev/tty 2>/dev/null || read -r new_hy2
                
                if [[ "$new_vless" =~ ^[0-9]+$ && "$new_hy2" =~ ^[0-9]+$ ]]; then
                    VLESS_PORT="$new_vless"
                    HY2_PORT="$new_hy2"
                    PUBLIC_IP=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
                    UUID=$(grep '"uuid"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"uuid":[[:space:]]*"([^"]+)".*/\1/')
                    PRIVATE_KEY=$(grep '"private_key"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"private_key":[[:space:]]*"([^"]+)".*/\1/')
                    SNI_DOMAIN=$(grep '"server_name"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"server_name":[[:space:]]*"([^"]+)".*/\1/')
                    SHORT_ID=$(grep '"short_id"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"short_id":[[:space:]]*\["([^"]+)".*/\1/')
                    HY2_PASS=$(grep '"password"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"password":[[:space:]]*"([^"]+)".*/\1/')
                    PUBLIC_KEY=$(grep "PublicKey" "$INFO_FILE" 2>/dev/null | awk '{print $3}')
                    
                    build_config_and_restart
                    echo -e "${GREEN}✔ Puertos actualizados correctamente.${NC}\n"
                    if [[ -f "$INFO_FILE" ]]; then
                        cat "$INFO_FILE"
                    fi
                else
                    echo -e "${RED}❌ Cancelado o puertos inválidos (deben ser números).${NC}"
                fi
                pause_screen
                ;;
            3)
                echo -e " ${CYAN}Ejemplos recomendados: dl.google.com , www.microsoft.com , gateway.icloud.com${NC}"
                echo -ne " Nuevo dominio SNI REALITY [Predeterminado: dl.google.com]: "
                read -r new_sni < /dev/tty 2>/dev/null || read -r new_sni
                SNI_DOMAIN=${new_sni:-"dl.google.com"}
                
                PUBLIC_IP=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
                VLESS_PORT=$(grep '"listen_port"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/[^0-9]*([0-9]+).*/\1/')
                HY2_PORT=$(grep '"listen_port"' "$CONF_FILE" 2>/dev/null | tail -n 1 | sed -E 's/[^0-9]*([0-9]+).*/\1/')
                UUID=$(grep '"uuid"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"uuid":[[:space:]]*"([^"]+)".*/\1/')
                PRIVATE_KEY=$(grep '"private_key"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"private_key":[[:space:]]*"([^"]+)".*/\1/')
                SHORT_ID=$(grep '"short_id"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"short_id":[[:space:]]*\["([^"]+)".*/\1/')
                HY2_PASS=$(grep '"password"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"password":[[:space:]]*"([^"]+)".*/\1/')
                PUBLIC_KEY=$(grep "PublicKey" "$INFO_FILE" 2>/dev/null | awk '{print $3}')
                
                build_config_and_restart
                echo -e "${GREEN}✔ Dominio SNI actualizado correctamente.${NC}\n"
                if [[ -f "$INFO_FILE" ]]; then
                    cat "$INFO_FILE"
                fi
                pause_screen
                ;;
            4)
                echo -e " ${CYAN}Regenerando llaves REALITY y actualizando enlaces...${NC}"
                PUBLIC_IP=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
                VLESS_PORT=$(grep '"listen_port"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/[^0-9]*([0-9]+).*/\1/')
                HY2_PORT=$(grep '"listen_port"' "$CONF_FILE" 2>/dev/null | tail -n 1 | sed -E 's/[^0-9]*([0-9]+).*/\1/')
                UUID=$("$BIN_PATH" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
                SNI_DOMAIN="dl.google.com"
                SHORT_ID=$(openssl rand -hex 4)
                HY2_PASS=$(grep '"password"' "$CONF_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*"password":[[:space:]]*"([^"]+)".*/\1/')
                generate_reality_pair
                build_config_and_restart
                echo -e "${GREEN}✔ Llaves y enlaces regenerados con éxito.${NC}\n"
                if [[ -f "$INFO_FILE" ]]; then
                    cat "$INFO_FILE"
                fi
                pause_screen
                ;;
            5)
                clear_screen
                echo -e "${CYAN}${BOLD}--- ESTADO DEL SERVICIO SING-BOX ---${NC}\n"
                systemctl status sing-box --no-pager -n 10
                echo -e "\n${CYAN}${BOLD}--- ÚLTIMOS LOGS DEL SISTEMA ---${NC}\n"
                journalctl -u sing-box -n 15 --no-pager 2>/dev/null || true
                pause_screen
                ;;
            6)
                if systemctl restart sing-box; then
                    echo -e "${GREEN}✔ Servicio reiniciado correctamente.${NC}"
                else
                    echo -e "${RED}❌ Ocurrió un error al reiniciar el servicio.${NC}"
                fi
                pause_screen
                ;;
            7) interactive_install ;;
            8)
                echo -ne "¿Confirmas eliminar Sing-Box completamente? (s/n): "
                read -r confirm < /dev/tty 2>/dev/null || read -r confirm
                if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                    echo -e "${YELLOW}Deteniendo y eliminando Sing-Box...${NC}"
                    systemctl stop sing-box 2>/dev/null
                    systemctl disable sing-box 2>/dev/null
                    pkill -9 -f sing-box-bin 2>/dev/null
                    rm -rf /etc/sing-box /etc/systemd/system/sing-box.service "$BIN_PATH" "$INFO_FILE"
                    systemctl daemon-reload 2>/dev/null
                    rm -f /usr/local/bin/singbox /usr/bin/singbox 2>/dev/null
                    echo -e "${GREEN}✔ Sing-Box desinstalado por completo.${NC}"
                    exit 0
                else
                    echo -e "${YELLOW}Desinstalación cancelada.${NC}"
                    pause_screen
                fi
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ ! -f "$CONF_FILE" ]]; then
    interactive_install
fi

menu_principal
SINGBOX_EOF

chmod +x /usr/local/bin/singbox
ln -sf /usr/local/bin/singbox /usr/bin/singbox 2>/dev/null
singbox
