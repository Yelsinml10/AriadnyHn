cat << 'EOF' > /usr/local/bin/v2ray
#!/bin/bash

# ==============================================================================
#  PALETA DE COLORES
# ==============================================================================
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[38;5;196m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;220m'
BLUE='\033[38;5;39m'
CYAN='\033[38;5;51m'
WHITE='\033[38;5;255m'
MAGENTA='\033[38;5;207m'
GRAY='\033[38;5;244m'
NC='\033[0m'

# ==============================================================================
#  VARIABLES GLOBALES
# ==============================================================================
V2RAY_VERSION="v5.51.2"
V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/download/${V2RAY_VERSION}/v2ray-linux-arm64-v8a.zip"

INSTALL_BIN="/usr/local/bin/v2ray"
INSTALL_DIR="/usr/local/v2ray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/v2ray.service"
CERT_DIR="${INSTALL_DIR}/cert"

DOMAIN=""
SERVER_IP=""
PORT="9090"
UUID=""
PASSWORD=""
METHOD="aes-256-gcm"

PATH_WS="/"
WS_HOST=""
SERVICE_NAME="grpc"

PROTOCOL=""
TRANSPORT="tcp"
SECURITY="none"
SSL_TYPE="none"

# ==============================================================================
#  AUTO-INSTALACIÓN Y ACCESOS DIRECTOS
# ==============================================================================

install_self_command() {
    local current_script
    current_script=$(readlink -f "$0" 2>/dev/null || echo "$0")

    if [[ "$current_script" != "$INSTALL_BIN" ]]; then
        cp "$current_script" "$INSTALL_BIN"
        chmod +x "$INSTALL_BIN"
    fi
    
    # Crear enlace simbólico para menuV2
    ln -sf "$INSTALL_BIN" "/usr/local/bin/menuV2"
}

# ==============================================================================
#  FUNCIONES DE INTERFAZ Y UTILIDADES
# ==============================================================================

get_server_ip() {
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null || true)
        if [[ -z "$SERVER_IP" ]]; then
            SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        fi
        [[ -z "$SERVER_IP" ]] && SERVER_IP="127.0.0.1"
    fi
}

get_service_status_badge() {
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        echo -e "${GREEN}🟢 ACTIVO${NC}"
    elif [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}🔴 DETENIDO${NC}"
    else
        echo -e "${GRAY}⚪ SIN CONFIG${NC}"
    fi
}

header() {
    clear 2>/dev/null || true
    get_server_ip
    local status_badge
    status_badge=$(get_service_status_badge)

    echo -e "${BLUE}┌────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  ${BOLD}${CYAN}V2RAY MANAGER${NC} ${DIM}(ARM64)${NC}                 ${BLUE}│${NC}"
    echo -e "${BLUE}├────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC}  IP:     ${WHITE}${SERVER_IP}${NC}"
    echo -e "${BLUE}│${NC}  Estado: ${status_badge}"
    echo -e "${BLUE}└────────────────────────────────────────┘${NC}"
    echo
}

pause_screen() {
    echo
    echo -e "${DIM}────────────────────────────────────────${NC}"
    read -r -p "$(echo -e "${YELLOW}Presiona [ENTER] para continuar...${NC}")" _
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        header
        echo -e "${RED}❌ Requiere permisos de usuario root.${NC}"
        echo -e "Ejecuta: ${CYAN}sudo bash $0${NC}\n"
        exit 1
    fi
}

read_value() {
    local variable="$1"
    local prompt="$2"
    local default_value="$3"
    local value

    read -r -p "$(echo -e "${CYAN}➜ ${NC}${WHITE}${prompt}${NC} ")" value
    [[ -z "$value" ]] && value="$default_value"

    printf -v "$variable" '%s' "$value"
}

read_option() {
    local variable="$1"
    local prompt="$2"
    local value

    while true; do
        read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}${prompt}${NC}")" value

        if [[ "$value" =~ ^[0-9]+$ ]]; then
            printf -v "$variable" '%s' "$value"
            return 0
        fi

        echo -e "${RED}⚠️ Ingrese un número válido.${NC}"
    done
}

generate_uuid() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        date +%s%N | sha256sum | cut -c1-32
    fi
}

generate_password() {
    generate_uuid | cut -d'-' -f1
}

encode_base64() {
    if base64 --help 2>/dev/null | grep -q -- "-w"; then
        printf '%s' "$1" | base64 -w 0
    else
        printf '%s' "$1" | base64 | tr -d '\n'
    fi
}

url_encode() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1], safe="/"), end="")
PY
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

is_ip_address() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# ==============================================================================
#  INSTALACIÓN DE V2RAY CORE Y CERTIFICADOS
# ==============================================================================

install_v2ray() {
    echo -e "${CYAN}📦 INSTALANDO DEPENDENCIAS Y V2RAY CORE...${NC}\n"

    apt-get update -y >/dev/null 2>&1 || return 1
    apt-get install -y wget unzip curl openssl certbot python3 >/dev/null 2>&1 || return 1

    mkdir -p "$INSTALL_DIR" /var/log/v2ray
    cd "$INSTALL_DIR" || return 1

    echo -e "${CYAN}⬇️  Descargando V2Ray Core (${V2RAY_VERSION})...${NC}"
    if ! wget -q "$V2RAY_URL" -O v2ray.zip; then
        echo -e "${RED}❌ Error al descargar V2Ray Core.${NC}"
        return 1
    fi

    echo -e "${CYAN}📂 Descomprimiendo archivos...${NC}"
    if ! unzip -o v2ray.zip >/dev/null 2>&1; then
        echo -e "${RED}❌ Error al descomprimir V2Ray.${NC}"
        return 1
    fi

    rm -f v2ray.zip
    chmod +x v2ray v2ctl 2>/dev/null || true

    # Crear configuración base inicial predeterminada en VMess
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOFD
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 9090,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "7985e3e4-1663-46ec-987f-c3afcfeaaf02",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOFD
    fi

    echo -e "${CYAN}⚙️  Configurando servicio systemd...${NC}"
    cat > "$SERVICE_FILE" <<EOFS
[Unit]
Description=V2Ray Core Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/v2ray run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOFS

    systemctl daemon-reload
    systemctl enable v2ray >/dev/null 2>&1

    echo -e "${GREEN}✔ V2Ray Core instalado con éxito.${NC}"
    return 0
}

generate_self_signed() {
    mkdir -p "$CERT_DIR"

    openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 365 \
        -key "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${DOMAIN}" >/dev/null 2>&1

    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"

    if [[ -f "${CERT_DIR}/cert.pem" && -f "${CERT_DIR}/key.pem" ]]; then
        SSL_TYPE="selfsigned"
        echo -e "${GREEN}✔ Certificado Autofirmado creado.${NC}"
        return 0
    fi

    echo -e "${RED}❌ Error al generar certificado.${NC}"
    return 1
}

install_letsencrypt() {
    echo -e "\n${YELLOW}⚠️ Certbot validará:${NC} ${WHITE}${DOMAIN}${NC}"

    read -r -p "$(echo -e "${CYAN}¿Continuar? (s/n): ${NC}")" answer
    [[ ! "$answer" =~ ^[Ss]$ ]] && return 1

    if ! certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email; then
        return 1
    fi

    if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        return 1
    fi

    mkdir -p "$CERT_DIR"
    cp "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "${CERT_DIR}/cert.pem"
    cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" "${CERT_DIR}/key.pem"

    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"

    SSL_TYPE="letsencrypt"
    echo -e "${GREEN}✔ Certificado Let's Encrypt instalado.${NC}"
}

setup_tls() {
    header
    echo -e "${BOLD}${WHITE}🔒 CERTIFICADO SSL/TLS${NC}\n"
    echo -e " ${YELLOW}1.${NC} Let's Encrypt ${GRAY}[Dominio]${NC}"
    echo -e " ${YELLOW}2.${NC} Autofirmado   ${GRAY}[Rápido / IP]${NC}\n"

    read_option tls_option "Opción [1-2]: "

    case "$tls_option" in
        1)
            if is_ip_address "$DOMAIN"; then
                echo -e "${YELLOW}⚠️ IP detectada. Usando Autofirmado...${NC}"
                generate_self_signed
            elif ! install_letsencrypt; then
                echo -e "${YELLOW}⚠️ Falló Let's Encrypt. Generando Autofirmado...${NC}"
                generate_self_signed
            fi
            ;;
        2|*)
            generate_self_signed
            ;;
    esac
}

# ==============================================================================
#  CONFIGURACIÓN DE PROTOCOLOS
# ==============================================================================

ask_basic_config() {
    echo -e "\n${BOLD}${WHITE}📝 DATOS DE CONEXIÓN${NC}\n"

    read_value DOMAIN "Dominio/IP [${SERVER_IP}]:" "$SERVER_IP"
    read_value PORT "Puerto [9090]:" "9090"

    while ! validate_port "$PORT"; do
        echo -e "${RED}❌ Puerto inválido (1-65535).${NC}"
        read_value PORT "Puerto [9090]:" "9090"
    done
}

select_protocol() {
    header
    echo -e "${BOLD}${WHITE}🌐 SELECCIONA PROTOCOLO${NC}\n"
    echo -e " ${YELLOW}1.${NC} VLESS       ${GREEN}[Recomendado]${NC}"
    echo -e " ${YELLOW}2.${NC} VMess       ${CYAN}[Estándar]${NC}"
    echo -e " ${YELLOW}3.${NC} Trojan      ${MAGENTA}[Camuflaje]${NC}"
    echo -e " ${YELLOW}4.${NC} Shadowsocks ${WHITE}[Clásico]${NC}"
    echo -e " ${YELLOW}5.${NC} SOCKS5      ${GRAY}[Proxy]${NC}"
    echo -e " ${YELLOW}6.${NC} ${RED}<< Cancelar${NC}\n"

    read_option protocol_option "Opción [1-6]: "

    case "$protocol_option" in
        1) PROTOCOL="vless" ;;
        2) PROTOCOL="vmess" ;;
        3) PROTOCOL="trojan" ;;
        4) PROTOCOL="shadowsocks" ;;
        5) PROTOCOL="socks" ;;
        6) return 1 ;;
        *) echo -e "${RED}❌ Opción inválida.${NC}"; return 1 ;;
    esac

    return 0
}

select_transport() {
    header
    echo -e "${BOLD}${WHITE}🛠️  TRANSPORTE PARA (${PROTOCOL^^})${NC}\n"
    echo -e " ${YELLOW}1.${NC} TCP Directo"
    echo -e " ${YELLOW}2.${NC} TCP + TLS"
    echo -e " ${YELLOW}3.${NC} WebSocket (WS)"
    echo -e " ${YELLOW}4.${NC} WebSocket + TLS ${GREEN}[CDN/Cloudflare]${NC}"
    echo -e " ${YELLOW}5.${NC} gRPC"
    echo -e " ${YELLOW}6.${NC} gRPC + TLS"
    echo

    read_option transport_option "Opción [1-6]: "

    case "$transport_option" in
        1) TRANSPORT="tcp"; SECURITY="none" ;;
        2) TRANSPORT="tcp"; SECURITY="tls" ;;
        3) TRANSPORT="ws";  SECURITY="none" ;;
        4) TRANSPORT="ws";  SECURITY="tls" ;;
        5) TRANSPORT="grpc"; SECURITY="none" ;;
        6) TRANSPORT="grpc"; SECURITY="tls" ;;
        *) TRANSPORT="tcp"; SECURITY="none" ;;
    esac

    if [[ "$TRANSPORT" == "ws" ]]; then
        echo
        read_value PATH_WS "Ruta WS [/]:" "/"
        [[ "$PATH_WS" != /* ]] && PATH_WS="/${PATH_WS}"

        read_value WS_HOST "Dominio Host WS [${DOMAIN}]:" "$DOMAIN"
    else
        PATH_WS="/"
        WS_HOST=""
    fi

    if [[ "$TRANSPORT" == "grpc" ]]; then
        echo
        read_value SERVICE_NAME "Service Name gRPC [grpc]:" "grpc"
    else
        SERVICE_NAME="grpc"
    fi

    if [[ "$SECURITY" == "tls" ]]; then
        setup_tls
    else
        SSL_TYPE="none"
    fi
}

write_base_config() {
    cat > "$CONFIG_FILE" <<EOFC
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "listen": "127.0.0.1",
      "protocol": "${PROTOCOL}",
      "settings": {},
      "streamSettings": {
        "network": "${TRANSPORT}",
        "security": "${SECURITY}"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOFC
}

add_client_settings() {
    python3 - "$CONFIG_FILE" "$PROTOCOL" "$UUID" "$PASSWORD" <<'PY'
import json, sys

config_file, protocol, uuid, password = sys.argv[1:5]

with open(config_file, encoding="utf-8") as file:
    config = json.load(file)

settings = config["inbounds"][0]["settings"]

if protocol == "vless":
    settings["clients"] = [{"id": uuid, "level": 0}]
    settings["decryption"] = "none"

if protocol == "vmess":
    settings["clients"] = [{"id": uuid, "alterId": 0}]

if protocol == "trojan":
    settings["clients"] = [{"password": password, "level": 0}]

if protocol == "socks":
    settings["auth"] = "noauth"
    settings["udp"] = True

with open(config_file, "w", encoding="utf-8") as file:
    json.dump(config, file, indent=2)
PY
}

add_stream_settings() {
    python3 - "$CONFIG_FILE" "$TRANSPORT" "$SECURITY" "$PATH_WS" "$WS_HOST" "$SERVICE_NAME" "$CERT_DIR" "$DOMAIN" <<'PY'
import json, sys

config_file, transport, security, path_ws, ws_host, service_name, cert_dir, domain = sys.argv[1:9]

with open(config_file, encoding="utf-8") as file:
    config = json.load(file)

stream = config["inbounds"][0]["streamSettings"]

if transport == "ws":
    stream["wsSettings"] = {
        "path": path_ws,
        "headers": {"Host": ws_host if ws_host else domain}
    }

if transport == "grpc":
    stream["grpcSettings"] = {
        "serviceName": service_name
    }

if security == "tls":
    sni_target = ws_host if (ws_host and transport == "ws") else domain
    stream["tlsSettings"] = {
        "serverName": sni_target,
        "certificates": [
            {
                "certificateFile": f"{cert_dir}/cert.pem",
                "keyFile": f"{cert_dir}/key.pem"
            }
        ]
    }

with open(config_file, "w", encoding="utf-8") as file:
    json.dump(config, file, indent=2)
PY
}

generate_config() {
    mkdir -p "$INSTALL_DIR"

    if [[ "$PROTOCOL" == "shadowsocks" ]]; then
        cat > "$CONFIG_FILE" <<EOFS
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {
        "method": "${METHOD}",
        "password": "${PASSWORD}",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOFS
        return 0
    fi

    if [[ "$PROTOCOL" == "socks" ]]; then
        TRANSPORT="tcp"
        SECURITY="none"
        write_base_config
        add_client_settings
        return 0
    fi

    write_base_config
    add_client_settings
    add_stream_settings
}

generate_link() {
    local link
    local encoded_path encoded_host encoded_service tls_value="" vmess_json params=""

    case "$PROTOCOL" in
        vmess)
            [[ "$SECURITY" == "tls" ]] && tls_value="tls"
            vmess_json="{\"v\":\"2\",\"ps\":\"VMess-${DOMAIN}\",\"add\":\"${DOMAIN}\",\"port\":\"${PORT}\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"${TRANSPORT}\",\"type\":\"none\",\"host\":\"${WS_HOST}\",\"path\":\"${PATH_WS}\",\"tls\":\"${tls_value}\",\"sni\":\"${DOMAIN}\",\"serviceName\":\"${SERVICE_NAME}\"}"
            link="vmess://$(encode_base64 "$vmess_json")"
            ;;

        vless)
            params="encryption=none"
            if [[ "$TRANSPORT" == "ws" ]]; then
                encoded_path=$(url_encode "$PATH_WS")
                encoded_host=$(url_encode "$WS_HOST")
                params="${params}&type=ws&path=${encoded_path}&host=${encoded_host}"
            elif [[ "$TRANSPORT" == "grpc" ]]; then
                encoded_service=$(url_encode "$SERVICE_NAME")
                params="${params}&type=grpc&serviceName=${encoded_service}"
            else
                params="${params}&type=tcp"
            fi

            if [[ "$SECURITY" == "tls" ]]; then
                params="${params}&security=tls&sni=$(url_encode "$DOMAIN")"
                [[ "$SSL_TYPE" == "selfsigned" ]] && params="${params}&allowInsecure=1"
            fi

            link="vless://${UUID}@${DOMAIN}:${PORT}?${params}#VLESS-${DOMAIN}"
            ;;

        trojan)
            if [[ "$TRANSPORT" == "ws" ]]; then
                encoded_path=$(url_encode "$PATH_WS")
                encoded_host=$(url_encode "$WS_HOST")
                params="type=ws&path=${encoded_path}&host=${encoded_host}"
            elif [[ "$TRANSPORT" == "grpc" ]]; then
                encoded_service=$(url_encode "$SERVICE_NAME")
                params="type=grpc&serviceName=${encoded_service}"
            else
                params="type=tcp"
            fi

            if [[ "$SECURITY" == "tls" ]]; then
                params="${params}&security=tls&sni=$(url_encode "$DOMAIN")"
                [[ "$SSL_TYPE" == "selfsigned" ]] && params="${params}&allowInsecure=1"
            fi

            link="trojan://${PASSWORD}@${DOMAIN}:${PORT}?${params}#Trojan-${DOMAIN}"
            ;;

        shadowsocks)
            local ss_data="${METHOD}:${PASSWORD}@${DOMAIN}:${PORT}"
            link="ss://$(encode_base64 "$ss_data")#SS-${DOMAIN}"
            ;;

        socks)
            link="socks5://${DOMAIN}:${PORT}#SOCKS5-${DOMAIN}"
            ;;
    esac

    printf '%s\n' "$link"
}

validate_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}❌ config.json no existe.${NC}"
        return 1
    fi

    if ! "${INSTALL_DIR}/v2ray" test -config "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Configuración con errores.${NC}"
        return 1
    fi

    echo -e "${GREEN}✔ Configuración válida.${NC}"
}

restart_service() {
    systemctl daemon-reload

    if ! systemctl restart v2ray; then
        echo -e "${RED}❌ Error al reiniciar V2Ray.${NC}"
        journalctl -u v2ray -n 15 --no-pager
        return 1
    fi

    sleep 1.5

    if systemctl is-active --quiet v2ray; then
        echo -e "${GREEN}✔ V2Ray activo en puerto ${PORT}.${NC}"
        return 0
    fi

    echo -e "${RED}❌ V2Ray no logró iniciar.${NC}"
    journalctl -u v2ray -n 15 --no-pager
    return 1
}

show_connection_data() {
    local link="$1"

    echo -e "\n${BLUE}┌────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}   ${BOLD}${GREEN}✅ CONFIGURACIÓN GENERADA${NC}           ${BLUE}│${NC}"
    echo -e "${BLUE}└────────────────────────────────────────┘${NC}\n"

    echo -e "${BOLD}${WHITE}📋 DETALLES:${NC}"
    echo -e "  ${CYAN}• Protocolo:${NC}       ${WHITE}${PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}• Servidor:${NC}        ${WHITE}${DOMAIN}${NC}"
    echo -e "  ${CYAN}• Puerto:${NC}          ${WHITE}${PORT}${NC}"

    if [[ "$PROTOCOL" != "shadowsocks" && "$PROTOCOL" != "socks" ]]; then
        echo -e "  ${CYAN}• Transporte:${NC}      ${WHITE}${TRANSPORT}${NC}"
        echo -e "  ${CYAN}• Cifrado:${NC}         ${WHITE}${SECURITY}${NC}"
    fi

    if [[ "$PROTOCOL" == "vmess" || "$PROTOCOL" == "vless" ]]; then
        echo -e "  ${CYAN}• UUID:${NC}            ${YELLOW}${UUID}${NC}"
    fi

    if [[ "$PROTOCOL" == "trojan" || "$PROTOCOL" == "shadowsocks" ]]; then
        echo -e "  ${CYAN}• Password:${NC}        ${YELLOW}${PASSWORD}${NC}"
    fi

    if [[ "$TRANSPORT" == "ws" ]]; then
        echo -e "  ${CYAN}• Path WS:${NC}         ${WHITE}${PATH_WS}${NC}"
        echo -e "  ${CYAN}• Host WS:${NC}         ${WHITE}${WS_HOST}${NC}"
    fi

    if [[ "$TRANSPORT" == "grpc" ]]; then
        echo -e "  ${CYAN}• Service Name:${NC}    ${WHITE}${SERVICE_NAME}${NC}"
    fi

    if [[ "$SECURITY" == "tls" && "$SSL_TYPE" == "selfsigned" ]]; then
        echo -e "\n  ${YELLOW}⚠️ Activa 'Allow Insecure' en tu app.${NC}"
    fi

    echo -e "\n${BOLD}${WHITE}🔗 ENLACE DE IMPORTACIÓN:${NC}"
    echo -e "${GREEN}${link}${NC}"
}

configure_protocol() {
    select_protocol || return

    ask_basic_config

    case "$PROTOCOL" in
        vmess|vless)
            UUID=$(generate_uuid)
            select_transport
            ;;

        trojan)
            read_value PASSWORD "Contraseña Trojan [auto]:" "$(generate_password)"
            select_transport
            ;;

        shadowsocks)
            read_value PASSWORD "Contraseña SS [auto]:" "$(generate_password)"
            read_value METHOD "Cifrado [aes-256-gcm]:" "aes-256-gcm"
            TRANSPORT="tcp"
            SECURITY="none"
            ;;

        socks)
            TRANSPORT="tcp"
            SECURITY="none"
            ;;
    esac

    generate_config

    if ! validate_config; then
        return 1
    fi

    local link
    link=$(generate_link)

    if ! restart_service; then
        return 1
    fi

    show_connection_data "$link"
}

edit_config() {
    header
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}❌ No existe config.json.${NC}"
        return
    fi

    echo -e "${CYAN}✍️ Editando config.json...${NC}\n"
    if command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
    else
        vi "$CONFIG_FILE"
    fi
}

start_v2ray() {
    header
    echo -e "${CYAN}▶️ Iniciando V2Ray...${NC}\n"
    systemctl start v2ray
    systemctl status v2ray --no-pager
}

stop_v2ray() {
    header
    echo -e "${CYAN}⏹️ Deteniendo V2Ray...${NC}\n"
    systemctl stop v2ray
    echo -e "${GREEN}✔ Servicio detenido.${NC}"
}

restart_v2ray() {
    header
    echo -e "${CYAN}🔄 Reiniciando V2Ray...${NC}\n"
    systemctl restart v2ray
    systemctl status v2ray --no-pager
}

status_v2ray() {
    header
    echo -e "${CYAN}📊 ESTADO DEL SERVICIO${NC}\n"
    systemctl status v2ray --no-pager
}

logs_v2ray() {
    header
    echo -e "${CYAN}📜 REGISTROS (CTRL+C para salir)${NC}\n"
    journalctl -u v2ray -f -n 20
}

uninstall_v2ray() {
    header
    echo -e "${RED}⚠️ DESINSTALAR V2RAY${NC}\n"
    read -r -p "$(echo -e "${YELLOW}¿Eliminar V2Ray por completo? (s/n): ${NC}")" answer
    [[ ! "$answer" =~ ^[Ss]$ ]] && return

    systemctl stop v2ray 2>/dev/null || true
    systemctl disable v2ray 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    rm -f "$SERVICE_FILE"
    rm -f "$INSTALL_BIN"
    rm -f "/usr/local/bin/menuV2"
    systemctl daemon-reload

    echo -e "\n${GREEN}✔ V2Ray desinstalado del sistema.${NC}"
}

show_main_menu() {
    header

    echo -e "${BOLD}${WHITE}🚀 CONFIGURACIÓN DE RED${NC}"
    echo -e " ${YELLOW}1.${NC} Configurar Protocolo"
    echo -e " ${YELLOW}2.${NC} Editar Config JSON"
    echo
    echo -e "${BOLD}${WHITE}⚙️  GESTIÓN DEL SERVICIO${NC}"
    echo -e " ${YELLOW}3.${NC} ${GREEN}Iniciar V2Ray${NC}"
    echo -e " ${YELLOW}4.${NC} ${RED}Detener V2Ray${NC}"
    echo -e " ${YELLOW}5.${NC} ${CYAN}Reiniciar V2Ray${NC}"
    echo -e " ${YELLOW}6.${NC} Estado Detallado"
    echo
    echo -e "${BOLD}${WHITE}🔧 MANTENIMIENTO${NC}"
    echo -e " ${YELLOW}7.${NC} Ver Logs en Vivo"
    echo -e " ${YELLOW}8.${NC} ${RED}Desinstalar V2Ray${NC}"
    echo -e " ${YELLOW}9.${NC} Salir"
    echo
    echo -e "${BLUE}────────────────────────────────────────${NC}"
}

main() {
    require_root
    install_self_command

    # Si V2Ray Core no está instalado, realizar la instalación directa
    if [[ ! -x "${INSTALL_DIR}/v2ray" ]]; then
        header
        echo -e "${CYAN}🚀 Iniciando instalación de V2Ray...${NC}\n"
        if install_v2ray; then
            echo
            echo -e "${GREEN}====================================================${NC}"
            echo -e "${GREEN}✅ ¡INSTALACIÓN COMPLETADA CON ÉXITO!${NC}"
            echo -e "${WHITE}Ahora puedes acceder al menú en cualquier momento escribiendo:${NC}"
            echo -e "  ${CYAN}• menuV2${NC}"
            echo -e "  ${CYAN}• v2ray${NC}"
            echo -e "${GREEN}====================================================${NC}\n"
            exit 0
        else
            echo -e "${RED}❌ Ocurrió un error en la instalación.${NC}"
            exit 1
        fi
    fi

    # Si V2Ray ya está instalado, mostrar el menú
    while true; do
        show_main_menu
        read_option main_option "Opción [1-9]: "

        case "$main_option" in
            1) configure_protocol; pause_screen ;;
            2) edit_config; pause_screen ;;
            3) start_v2ray; pause_screen ;;
            4) stop_v2ray; pause_screen ;;
            5) restart_v2ray; pause_screen ;;
            6) status_v2ray; pause_screen ;;
            7) logs_v2ray ;;
            8) uninstall_v2ray; pause_screen ;;
            9)
                echo -e "\n${GREEN}👋 ¡Hasta luego!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Opción inválida.${NC}"
                sleep 1
                ;;
        esac
    done
}

main
EOF
chmod +x /usr/local/bin/v2ray
