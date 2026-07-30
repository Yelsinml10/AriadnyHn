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
XRAY_VERSION="v1.8.24"

INSTALL_BIN="/usr/local/bin/v2ray"
INSTALL_DIR="/usr/local/v2ray"
XRAY_BIN="${INSTALL_DIR}/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/v2ray.service"
CERT_DIR="${INSTALL_DIR}/cert"

SERVER_IP=""
PYTHON_CMD=""

# ==============================================================================
#  AUTO-INSTALACIÓN Y ACCESOS DIRECTOS
# ==============================================================================

install_self_command() {
    local current_script
    current_script="${BASH_SOURCE[0]:-$0}"

    if [[ ! -f "$current_script" || "$current_script" == *"/dev/fd"* || "$current_script" == *"/proc/"* ]]; then
        if [[ ! -f "$INSTALL_BIN" ]]; then
            cat "$0" > "$INSTALL_BIN" 2>/dev/null || true
        fi
    else
        if [[ "$(readlink -f "$current_script" 2>/dev/null)" != "$(readlink -f "$INSTALL_BIN" 2>/dev/null)" ]]; then
            cp -f "$current_script" "$INSTALL_BIN" 2>/dev/null || true
        fi
    fi

    chmod +x "$INSTALL_BIN" 2>/dev/null || true
    
    ln -sf "$INSTALL_BIN" "/usr/local/bin/v2ray" 2>/dev/null
    ln -sf "$INSTALL_BIN" "/usr/local/bin/menuV2" 2>/dev/null
    ln -sf "$INSTALL_BIN" "/usr/local/bin/menuv2" 2>/dev/null
    ln -sf "$INSTALL_BIN" "/usr/local/bin/menu" 2>/dev/null

    ln -sf "$INSTALL_BIN" "/usr/bin/v2ray" 2>/dev/null
    ln -sf "$INSTALL_BIN" "/usr/bin/menuV2" 2>/dev/null
    ln -sf "$INSTALL_BIN" "/usr/bin/menuv2" 2>/dev/null
    ln -sf "$INSTALL_BIN" "/usr/bin/menu" 2>/dev/null

    hash -r 2>/dev/null || true
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
    echo -e "${BLUE}│${NC}          ${BOLD}${CYAN}XRAY MANAGER (${XRAY_VERSION})${NC}       ${BLUE}│${NC}"
    echo -e "${BLUE}├────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC}  IP Server: ${WHITE}${SERVER_IP}${NC}"
    echo -e "${BLUE}│${NC}  Estado:    ${status_badge}"
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
        echo -e "${RED}❌ Requiere permisos de root.${NC}"
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

        echo -e "${RED}⚠️ Opción no válida.${NC}"
    done
}

generate_uuid() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        local hex
        hex=$(date +%s%N | sha256sum | cut -c1-32)
        echo "${hex:0:8}-${hex:8:4}-${hex:12:4}-${hex:16:4}-${hex:20:12}"
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
    $PYTHON_CMD - "$1" <<'PY'
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
#  INSTALACIÓN DE XRAY CORE Y CERTIFICADOS
# ==============================================================================

install_v2ray() {
    echo -e "${CYAN}📦 Instalando dependencias y Xray Core...${NC}\n"

    apt-get update -y >/dev/null 2>&1 || return 1
    
    # Instalar Python3 si no está instalado
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ Python3 no encontrado. Instalando...${NC}"
        apt-get install -y python3 python3-urllib3 >/dev/null 2>&1 || return 1
    fi
    
    # Detectar comando Python
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    else
        echo -e "${RED}❌ No se encontró Python. Instalando...${NC}"
        apt-get install -y python3 >/dev/null 2>&1 || return 1
        PYTHON_CMD="python3"
    fi
    
    apt-get install -y wget unzip curl openssl certbot >/dev/null 2>&1 || return 1

    if free -m | awk '/^Mem:/{print $2}' | awk '{if ($1 < 1024) exit 0; else exit 1}'; then
        if [[ $(swapon --show 2>/dev/null | wc -l) -eq 0 ]]; then
            echo -e "${YELLOW}⚙️ Añadiendo memoria SWAP para estabilizar la VPS...${NC}"
            fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 2>/dev/null
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile >/dev/null 2>&1
        fi
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || return 1

    local ARCH=$(uname -m)
    local XRAY_URL
    if [[ "$ARCH" == *"aarch64"* || "$ARCH" == *"arm64"* ]]; then
        XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-arm64-v8a.zip"
    else
        XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
    fi

    if ! wget -q --timeout=60 --tries=3 "$XRAY_URL" -O xray.zip; then
        echo -e "${RED}❌ Error al descargar Xray.${NC}"
        return 1
    fi

    if ! unzip -o xray.zip >/dev/null 2>&1; then
        echo -e "${RED}❌ Error al descomprimir Xray.${NC}"
        return 1
    fi

    rm -f xray.zip
    chmod +x xray 2>/dev/null || true
    ln -sf "${XRAY_BIN}" "/usr/bin/xray" 2>/dev/null || true
    ln -sf "${XRAY_BIN}" "${INSTALL_DIR}/v2ray" 2>/dev/null || true

    cat > "$SERVICE_FILE" <<EOFS
[Unit]
Description=Xray Core Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${XRAY_BIN} run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOFS

    systemctl daemon-reload
    systemctl enable v2ray >/dev/null 2>&1

    echo -e "${GREEN}✔ Xray instalado correctamente.${NC}"
    return 0
}

generate_self_signed() {
    local domain_target="$1"
    mkdir -p "$CERT_DIR"

    openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 365 \
        -key "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain_target}" >/dev/null 2>&1

    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"

    if [[ -f "${CERT_DIR}/cert.pem" && -f "${CERT_DIR}/key.pem" ]]; then
        echo -e "${GREEN}✔ Certificado Autofirmado generado.${NC}"
        return 0
    fi

    echo -e "${RED}❌ Error al generar certificado.${NC}"
    return 1
}

install_letsencrypt() {
    local domain_target="$1"
    echo -e "\n${YELLOW}Generando certificado Let's Encrypt para ${domain_target}${NC}"

    local restart_v2ray=false
    local restart_nginx=false

    if ss -tuln | awk '{print $5}' | grep -q -E ':(80)$'; then
        echo -e "${YELLOW}⚠️ Liberando temporalmente el puerto 80...${NC}"
        if systemctl is-active --quiet v2ray 2>/dev/null; then systemctl stop v2ray; restart_v2ray=true; fi
        if systemctl is-active --quiet nginx 2>/dev/null; then systemctl stop nginx; restart_nginx=true; fi
    fi

    if ! certbot certonly --standalone -d "$domain_target" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null; then
        echo -e "${RED}❌ Falló la validación SSL.${NC}"
        [[ "$restart_v2ray" == true ]] && systemctl start v2ray 2>/dev/null
        [[ "$restart_nginx" == true ]] && systemctl start nginx 2>/dev/null
        return 1
    fi

    [[ "$restart_v2ray" == true ]] && systemctl start v2ray 2>/dev/null
    [[ "$restart_nginx" == true ]] && systemctl start nginx 2>/dev/null

    if [[ ! -f "/etc/letsencrypt/live/${domain_target}/fullchain.pem" ]]; then
        return 1
    fi

    mkdir -p "$CERT_DIR"
    cp "/etc/letsencrypt/live/${domain_target}/fullchain.pem" "${CERT_DIR}/cert.pem"
    cp "/etc/letsencrypt/live/${domain_target}/privkey.pem" "${CERT_DIR}/key.pem"

    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"

    echo -e "${GREEN}✔ Certificado Let's Encrypt generado.${NC}"
    return 0
}

validate_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}❌ config.json no existe.${NC}"
        return 1
    fi

    if ! "${XRAY_BIN}" run -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Configuración con errores.${NC}"
        "${XRAY_BIN}" run -test -config "$CONFIG_FILE"
        return 1
    fi

    echo -e "${GREEN}✔ Configuración válida.${NC}"
}

restart_service() {
    systemctl daemon-reload

    if ! systemctl restart v2ray; then
        echo -e "${RED}❌ Error al reiniciar Xray.${NC}"
        journalctl -u v2ray -n 15 --no-pager
        return 1
    fi

    sleep 1.5

    if systemctl is-active --quiet v2ray; then
        echo -e "${GREEN}✔ Xray reiniciado y activo.${NC}"
        return 0
    fi

    echo -e "${RED}❌ Error al iniciar Xray.${NC}"
    journalctl -u v2ray -n 15 --no-pager
    return 1
}

# ==============================================================================
#  GESTOR PYTHON DE CONFIGURACIÓN Y CLIENTES
# ==============================================================================

python_inspector() {
    $PYTHON_CMD - "$CONFIG_FILE" "$1" "$2" "$3" <<'PY'
import json, sys

config_file = sys.argv[1]
action = sys.argv[2] if len(sys.argv) > 2 else "info"
param1 = sys.argv[3] if len(sys.argv) > 3 else ""
param2 = sys.argv[4] if len(sys.argv) > 4 else ""

try:
    with open(config_file, "r", encoding="utf-8") as f:
        config = json.load(f)
except Exception as e:
    sys.exit(1)

inbound = config["inbounds"][0]
protocol = inbound.get("protocol", "desconocido")
port = inbound.get("port", 0)
stream = inbound.get("streamSettings", {})
transport = stream.get("network", "tcp")
security = stream.get("security", "none")
server_domain = config.get("_domain", "")

if action == "info":
    print(f"PROTOCOL='{protocol}'")
    print(f"PORT='{port}'")
    print(f"TRANSPORT='{transport}'")
    print(f"SECURITY='{security}'")
    print(f"SERVER_DOMAIN='{server_domain}'")
    
    if transport == "ws":
        ws = stream.get("wsSettings", {})
        print(f"WS_PATH='{ws.get('path', '/')}'")
        print(f"WS_HOST='{ws.get('headers', {}).get('Host', '')}'")
    elif transport == "grpc":
        grpc = stream.get("grpcSettings", {})
        print(f"SERVICE_NAME='{grpc.get('serviceName', '')}'")
        
    if security == "reality":
        real = stream.get("realitySettings", {})
        print(f"REALITY_DEST='{real.get('dest', '')}'")
        print(f"REALITY_SNI='{real.get('serverNames', [''])[0]}'")
        print(f"REALITY_PUBLIC_KEY='{real.get('publicKey', '')}'")
        print(f"REALITY_SHORT_ID='{real.get('shortIds', [''])[0]}'")
    elif security == "tls":
        tls = stream.get("tlsSettings", {})
        print(f"TLS_SNI='{tls.get('serverName', '')}'")

    settings = inbound.get("settings", {})
    if protocol in ["vless", "vmess", "trojan"]:
        clients = settings.get("clients", [])
        print(f"NUM_CLIENTS='{len(clients)}'")
    elif protocol == "shadowsocks":
        print(f"SS_METHOD='{settings.get('method', '')}'")
        print(f"SS_PASSWORD='{settings.get('password', '')}'")
        print(f"NUM_CLIENTS='1'")
    elif protocol == "socks":
        print(f"SOCKS_AUTH='{settings.get('auth', 'noauth')}'")
        print(f"NUM_CLIENTS='1'")

elif action == "list_clients":
    settings = inbound.get("settings", {})
    if protocol in ["vless", "vmess"]:
        clients = settings.get("clients", [])
        for idx, c in enumerate(clients):
            cid = c.get("id", "Sin-ID")
            print(f"{idx+1}) {cid}")
    elif protocol == "trojan":
        clients = settings.get("clients", [])
        for idx, c in enumerate(clients):
            cpass = c.get("password", "Sin-Pass")
            print(f"{idx+1}) {cpass}")
    elif protocol == "shadowsocks":
        print(f"1) {settings.get('password')}")
    elif protocol == "socks":
        print(f"1) {settings.get('auth')}")

elif action == "add_client":
    settings = inbound.setdefault("settings", {})
    clients = settings.setdefault("clients", [])
    if protocol in ["vless", "vmess"]:
        clients.append({"id": param1, "level": 0})
    elif protocol == "trojan":
        clients.append({"password": param1, "level": 0})
    with open(config_file, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)

elif action == "del_client":
    try:
        idx = int(param1) - 1
        clients = inbound.get("settings", {}).get("clients", [])
        if 0 <= idx < len(clients):
            del clients[idx]
            with open(config_file, "w", encoding="utf-8") as f:
                json.dump(config, f, indent=2)
            print("OK")
    except:
        pass

elif action == "set_param":
    key, val = param1.split("=", 1)
    if key == "domain":
        config["_domain"] = val
    elif key == "port":
        inbound["port"] = int(val)
    elif key == "path":
        stream.setdefault("wsSettings", {})["path"] = val
    elif key == "serviceName":
        stream.setdefault("grpcSettings", {})["serviceName"] = val
    elif key == "host":
        stream.setdefault("wsSettings", {}).setdefault("headers", {})["Host"] = val
    elif key == "reality_dest":
        stream.setdefault("realitySettings", {})["dest"] = val
    elif key == "reality_sni":
        stream.setdefault("realitySettings", {})["serverNames"] = [val]
    elif key == "short_id":
        stream.setdefault("realitySettings", {})["shortIds"] = [val]

    with open(config_file, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
PY
}

# ==============================================================================
#  CONFIGURACIÓN DE NUEVO PROTOCOLO
# ==============================================================================

configure_new_protocol() {
    header
    echo -e "${BOLD}${WHITE}🌐 SELECCIONA UN PROTOCOLO:${NC}\n"
    echo -e " ${YELLOW}1.${NC} VLESS"
    echo -e " ${YELLOW}2.${NC} VMess"
    echo -e " ${YELLOW}3.${NC} Trojan"
    echo -e " ${YELLOW}4.${NC} Shadowsocks"
    echo -e " ${YELLOW}5.${NC} SOCKS5"
    echo -e " ${YELLOW}6.${NC} Volver\n"

    read_option proto_opt "Opción [1-6]: "

    local selected_proto=""
    case "$proto_opt" in
        1) selected_proto="vless" ;;
        2) selected_proto="vmess" ;;
        3) selected_proto="trojan" ;;
        4) selected_proto="shadowsocks" ;;
        5) selected_proto="socks" ;;
        6) return ;;
        *) echo -e "${RED}❌ Opción no válida.${NC}"; return ;;
    esac

    echo -e "\n${BOLD}${WHITE}📝 DATOS DE CONEXIÓN:${NC}\n"
    local target_domain
    read_value target_domain "Dominio o IP [${SERVER_IP}]:" "${SERVER_IP}"
    
    local selected_port
    read_value selected_port "Puerto [443]:" "443"
    while ! validate_port "$selected_port"; do
        echo -e "${RED}❌ Puerto inválido (1-65535).${NC}"
        read_value selected_port "Puerto [443]:" "443"
    done

    local transport="tcp" security="none" path_ws="/" host_ws="" service_name=""
    local reality_sni="" reality_key="" reality_pub="" reality_sid=""
    local ss_method="aes-256-gcm" ss_password=""
    local need_tls=false

    # Configuración de transporte y seguridad para protocolos que lo soportan
    if [[ "$selected_proto" =~ ^(vless|vmess|trojan)$ ]]; then
        echo -e "\n${BOLD}${WHITE}🛠️  TRANSPORTE Y SEGURIDAD:${NC}\n"
        echo -e " ${YELLOW}1.${NC} TCP Directo"
        echo -e " ${YELLOW}2.${NC} TCP + TLS"
        echo -e " ${YELLOW}3.${NC} WebSocket (WS)"
        echo -e " ${YELLOW}4.${NC} WebSocket + TLS"
        echo -e " ${YELLOW}5.${NC} gRPC"
        echo -e " ${YELLOW}6.${NC} gRPC + TLS"
        if [[ "$selected_proto" == "vless" ]]; then
            echo -e " ${YELLOW}7.${NC} TCP + XTLS-Reality"
        fi
        echo

        read_option trans_opt "Opción: "

        case "$trans_opt" in
            1) transport="tcp"; security="none" ;;
            2) transport="tcp"; security="tls"; need_tls=true ;;
            3) transport="ws"; security="none" ;;
            4) transport="ws"; security="tls"; need_tls=true ;;
            5) transport="grpc"; security="none" ;;
            6) transport="grpc"; security="tls"; need_tls=true ;;
            7)
                if [[ "$selected_proto" == "vless" ]]; then
                    transport="tcp"; security="reality"
                else
                    transport="tcp"; security="none"
                fi
                ;;
            *) transport="tcp"; security="none" ;;
        esac

        # Configuración específica por transporte
        if [[ "$transport" == "ws" ]]; then
            read_value path_ws "Path WS [/ray]:" "/ray"
            [[ "$path_ws" != /* ]] && path_ws="/${path_ws}"
            read_value host_ws "Host WS [${target_domain}]:" "$target_domain"
        fi

        if [[ "$transport" == "grpc" ]]; then
            read_value service_name "Service Name [grpc]:" "grpc"
        fi

        # Configuración Reality (solo VLESS)
        if [[ "$security" == "reality" ]]; then
            read_value reality_sni "SNI a clonar [www.microsoft.com]:" "www.microsoft.com"
            local keys
            keys=$("${XRAY_BIN}" x25519 2>/dev/null)
            reality_key=$(echo "$keys" | grep -i "Private" | awk '{print $NF}')
            reality_pub=$(echo "$keys" | grep -i "Public" | awk '{print $NF}')
            reality_sid=$(openssl rand -hex 8)
        fi
    fi

    # Configuración Shadowsocks
    if [[ "$selected_proto" == "shadowsocks" ]]; then
        read_value ss_password "Contraseña SS [auto]:" "$(generate_password)"
        read_value ss_method "Método [aes-256-gcm]:" "aes-256-gcm"
    fi

    # Generar usuario inicial
    local initial_user
    if [[ "$selected_proto" == "trojan" ]]; then
        read_value initial_user "Contraseña para Trojan [auto]:" "$(generate_password)"
    else
        initial_user=$(generate_uuid)
    fi

    # ====== PRIMERO: Configurar TLS si es necesario (ANTES de crear config.json) ======
    if [[ "$need_tls" == true ]]; then
        echo -e "\n${BOLD}${WHITE}🔒 Configurando certificado TLS...${NC}"
        mkdir -p "$CERT_DIR"
        generate_self_signed "$target_domain"
        
        if ! is_ip_address "$target_domain"; then
            echo -e "\n${YELLOW}¿Quieres usar Let's Encrypt en lugar del certificado autofirmado?${NC}"
            read -r -p "$(echo -e "${CYAN}Opción [1=Let's Encrypt, 2=Autofirmado, ENTER=Autofirmado]: ${NC}")" le_choice
            
            if [[ "$le_choice" == "1" ]]; then
                if install_letsencrypt "$target_domain"; then
                    echo -e "${GREEN}✔ Certificado Let's Encrypt generado.${NC}"
                else
                    echo -e "${YELLOW}⚠️ Usando certificado autofirmado como respaldo.${NC}"
                    generate_self_signed "$target_domain"
                fi
            fi
        fi
    fi

    # ====== SEGUNDO: Crear la configuración JSON ======
    echo -e "\n${CYAN}📝 Generando configuración para ${selected_proto}...${NC}"
    
    $PYTHON_CMD - "$CONFIG_FILE" "$selected_proto" "$selected_port" "$transport" "$security" "$initial_user" "$path_ws" "$host_ws" "$service_name" "$target_domain" "$CERT_DIR" "$reality_sni" "$reality_key" "$reality_pub" "$reality_sid" "$ss_method" "$ss_password" <<'PY'
import json, sys

# Recibir argumentos
config_file = sys.argv[1]
proto = sys.argv[2]
port = int(sys.argv[3])
transport = sys.argv[4]
security = sys.argv[5]
user = sys.argv[6]
path_ws = sys.argv[7]
host_ws = sys.argv[8]
service_name = sys.argv[9]
domain = sys.argv[10]
cert_dir = sys.argv[11]
r_sni = sys.argv[12]
r_key = sys.argv[13]
r_pub = sys.argv[14]
r_sid = sys.argv[15]
ss_method = sys.argv[16]
ss_pass = sys.argv[17]

# Estructura base
config = {
    "_domain": domain,
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "listen": "0.0.0.0",
        "port": port,
        "protocol": proto,
        "settings": {},
        "streamSettings": {
            "network": transport,
            "security": security
        },
        "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}
    }],
    "outbounds": [{"protocol": "freedom", "settings": {}}]
}

inbound = config["inbounds"][0]
settings = inbound["settings"]

# Configurar settings según protocolo
if proto == "vless":
    settings["clients"] = [{"id": user, "level": 0}]
    settings["decryption"] = "none"
    if security == "reality":
        settings["clients"][0]["flow"] = "xtls-rprx-vision"
elif proto == "vmess":
    settings["clients"] = [{"id": user, "alterId": 0, "level": 0}]
elif proto == "trojan":
    settings["clients"] = [{"password": user, "level": 0}]
elif proto == "shadowsocks":
    settings["method"] = ss_method
    settings["password"] = ss_pass if ss_pass and ss_pass != "auto" else user
    settings["network"] = "tcp,udp"
elif proto == "socks":
    settings["auth"] = "noauth"
    settings["udp"] = True

# Configurar streamSettings
stream = inbound["streamSettings"]

if transport == "ws":
    stream["wsSettings"] = {
        "path": path_ws,
        "headers": {"Host": host_ws if host_ws else domain}
    }
elif transport == "grpc":
    stream["grpcSettings"] = {"serviceName": service_name}

# Configurar TLS (solo si existen los archivos)
if security == "tls":
    if cert_dir and cert_dir != "":
        stream["tlsSettings"] = {
            "serverName": domain,
            "certificates": [{
                "certificateFile": f"{cert_dir}/cert.pem",
                "keyFile": f"{cert_dir}/key.pem"
            }]
        }

# Configurar Reality
if security == "reality":
    stream["realitySettings"] = {
        "show": False,
        "dest": f"{r_sni}:443",
        "xver": 0,
        "serverNames": [r_sni],
        "privateKey": r_key,
        "publicKey": r_pub,
        "shortIds": [r_sid]
    }

# Guardar configuración
with open(config_file, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
PY

    if validate_config && restart_service; then
        display_protocol_details "$initial_user"
    fi
}

# ==============================================================================
#  SUBMENÚ: GESTIÓN DEL PROTOCOLO ACTIVO
# ==============================================================================

manage_active_protocol() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        header
        echo -e "${RED}❌ No hay ningún protocolo configurado actualmente.${NC}"
        pause_screen
        return
    fi

    while true; do
        header
        echo -e "${BOLD}${WHITE}🔍 INFORMACIÓN ACTUAL:${NC}\n"

        eval $($PYTHON_CMD -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    inbound = config['inbounds'][0]
    protocol = inbound.get('protocol', 'desconocido')
    port = inbound.get('port', 0)
    stream = inbound.get('streamSettings', {})
    transport = stream.get('network', 'tcp')
    security = stream.get('security', 'none')
    server_domain = config.get('_domain', '')
    
    print(f\"PROTOCOL='{protocol}'\")
    print(f\"PORT='{port}'\")
    print(f\"TRANSPORT='{transport}'\")
    print(f\"SECURITY='{security}'\")
    print(f\"SERVER_DOMAIN='{server_domain}'\")
    
    if transport == 'ws':
        ws = stream.get('wsSettings', {})
        print(f\"WS_PATH='{ws.get('path', '/')}'\")
        print(f\"WS_HOST='{ws.get('headers', {}).get('Host', '')}'\")
    elif transport == 'grpc':
        grpc = stream.get('grpcSettings', {})
        print(f\"SERVICE_NAME='{grpc.get('serviceName', '')}'\")
        
    if security == 'reality':
        real = stream.get('realitySettings', {})
        print(f\"REALITY_DEST='{real.get('dest', '')}'\")
        print(f\"REALITY_SNI='{real.get('serverNames', [''])[0]}'\")
        print(f\"REALITY_PUBLIC_KEY='{real.get('publicKey', '')}'\")
        print(f\"REALITY_SHORT_ID='{real.get('shortIds', [''])[0]}'\")
    elif security == 'tls':
        tls = stream.get('tlsSettings', {})
        print(f\"TLS_SNI='{tls.get('serverName', '')}'\")
    
    settings = inbound.get('settings', {})
    if protocol in ['vless', 'vmess', 'trojan']:
        clients = settings.get('clients', [])
        print(f\"NUM_CLIENTS='{len(clients)}'\")
    elif protocol == 'shadowsocks':
        print(f\"SS_METHOD='{settings.get('method', '')}'\")
        print(f\"SS_PASSWORD='{settings.get('password', '')}'\")
        print(f\"NUM_CLIENTS='1'\")
    elif protocol == 'socks':
        print(f\"SOCKS_AUTH='{settings.get('auth', 'noauth')}'\")
        print(f\"NUM_CLIENTS='1'\")
except Exception as e:
    print(\"PROTOCOL='error'\")
")

        local current_domain="${SERVER_DOMAIN:-$SERVER_IP}"

        echo -e "  ${CYAN}• Protocolo:${NC}    ${WHITE}${PROTOCOL^^}${NC}"
        echo -e "  ${CYAN}• Servidor:${NC}     ${WHITE}${current_domain}${NC}"
        echo -e "  ${CYAN}• Puerto:${NC}       ${WHITE}${PORT}${NC}"
        echo -e "  ${CYAN}• Transporte:${NC}   ${WHITE}${TRANSPORT}${NC}"
        echo -e "  ${CYAN}• Cifrado:${NC}      ${WHITE}${SECURITY}${NC}"

        [[ -n "$WS_PATH" ]] && echo -e "  ${CYAN}• Path WS:${NC}      ${WHITE}${WS_PATH}${NC}"
        [[ -n "$WS_HOST" ]] && echo -e "  ${CYAN}• Host WS:${NC}      ${WHITE}${WS_HOST}${NC}"
        [[ -n "$SERVICE_NAME" ]] && echo -e "  ${CYAN}• Service Name:${NC} ${WHITE}${SERVICE_NAME}${NC}"
        [[ -n "$REALITY_DEST" ]] && echo -e "  ${CYAN}• Destino:${NC}      ${WHITE}${REALITY_DEST}${NC}"
        [[ -n "$REALITY_SNI" ]] && echo -e "  ${CYAN}• SNI Reality:${NC}  ${WHITE}${REALITY_SNI}${NC}"
        [[ -n "$TLS_SNI" ]] && echo -e "  ${CYAN}• SNI TLS:${NC}      ${WHITE}${TLS_SNI}${NC}"
        [[ -n "$SS_METHOD" ]] && echo -e "  ${CYAN}• Método SS:${NC}    ${WHITE}${SS_METHOD}${NC}"
        echo -e "  ${CYAN}• Usuarios:${NC}     ${YELLOW}${NUM_CLIENTS} activo(s)${NC}"

        echo -e "\n${BLUE}────────────────────────────────────────${NC}"
        echo -e "${BOLD}${WHITE}⚙️  GESTIONAR:${NC}\n"
        echo -e " ${YELLOW}1.${NC} Ver Usuarios y Enlace de Conexión"
        if [[ "$PROTOCOL" =~ ^(vless|vmess|trojan)$ ]]; then
            echo -e " ${YELLOW}2.${NC} Agregar Usuario"
            echo -e " ${YELLOW}3.${NC} Eliminar Usuario"
        fi
        echo -e " ${YELLOW}4.${NC} Cambiar Dominio / IP (${current_domain})"
        echo -e " ${YELLOW}5.${NC} Cambiar Puerto (${PORT})"
        [[ "$TRANSPORT" == "ws" ]] && echo -e " ${YELLOW}6.${NC} Cambiar Path WS (${WS_PATH})"
        [[ "$TRANSPORT" == "grpc" ]] && echo -e " ${YELLOW}6.${NC} Cambiar Service Name gRPC (${SERVICE_NAME})"
        [[ "$SECURITY" == "reality" ]] && echo -e " ${YELLOW}7.${NC} Cambiar SNI Reality (${REALITY_SNI})"
        echo -e " ${YELLOW}8.${NC} Volver\n"

        read_option sub_opt "Opción [1-8]: "

        case "$sub_opt" in
            1) show_all_user_links; pause_screen ;;
            2) 
                if [[ "$PROTOCOL" =~ ^(vless|vmess|trojan)$ ]]; then
                    add_user_interactive
                else
                    echo -e "${YELLOW}⚠️ Este protocolo no admite usuarios dinámicos.${NC}"
                fi
                pause_screen 
                ;;
            3) 
                if [[ "$PROTOCOL" =~ ^(vless|vmess|trojan)$ ]]; then
                    del_user_interactive
                else
                    echo -e "${YELLOW}⚠️ No se pueden eliminar usuarios en este protocolo.${NC}"
                fi
                pause_screen 
                ;;
            4)
                read_value new_domain "Nuevo Dominio/IP:" "$current_domain"
                if [[ -n "$new_domain" ]]; then
                    python_inspector "set_param" "domain=${new_domain}"
                    validate_config && restart_service
                fi
                pause_screen
                ;;
            5) 
                read_value new_port "Nuevo Puerto:" "$PORT"
                if validate_port "$new_port"; then
                    python_inspector "set_param" "port=${new_port}"
                    validate_config && restart_service
                else
                    echo -e "${RED}❌ Puerto inválido.${NC}"
                fi
                pause_screen
                ;;
            6)
                if [[ "$TRANSPORT" == "ws" ]]; then
                    read_value new_path "Nuevo Path WS:" "$WS_PATH"
                    [[ "$new_path" != /* ]] && new_path="/${new_path}"
                    python_inspector "set_param" "path=${new_path}"
                elif [[ "$TRANSPORT" == "grpc" ]]; then
                    read_value new_service "Nuevo Service Name:" "$SERVICE_NAME"
                    python_inspector "set_param" "serviceName=${new_service}"
                fi
                validate_config && restart_service
                pause_screen
                ;;
            7)
                if [[ "$SECURITY" == "reality" ]]; then
                    read_value new_sni "Nuevo SNI Reality [www.microsoft.com]:" "$REALITY_SNI"
                    python_inspector "set_param" "reality_sni=${new_sni}"
                    python_inspector "set_param" "reality_dest=${new_sni}:443"
                    validate_config && restart_service
                fi
                pause_screen
                ;;
            8) return ;;
            *) echo -e "${RED}❌ Opción no válida.${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
#  ENLACE DE CONEXIÓN POR PROTOCOLO
# ==============================================================================

show_all_user_links() {
    header
    
    local clients_list
    clients_list=$(python_inspector "list_clients")

    if [[ -z "$clients_list" ]]; then
        echo -e "${RED}No hay usuarios registrados.${NC}"
        return
    fi

    echo -e "${BOLD}${WHITE}📋 USUARIOS REGISTRADOS:${NC}\n"
    echo "$clients_list"
    echo
    read_value user_num "Selecciona el número de usuario [1]:" "1"

    local selected_user
    selected_user=$(echo "$clients_list" | sed -n "${user_num}p" | awk -F') ' '{print $2}')

    if [[ -z "$selected_user" ]]; then
        echo -e "${RED}❌ Usuario no encontrado.${NC}"
        return
    fi

    display_protocol_details "$selected_user"
}

display_protocol_details() {
    local uid="$1"
    eval $($PYTHON_CMD -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    inbound = config['inbounds'][0]
    protocol = inbound.get('protocol', 'desconocido')
    port = inbound.get('port', 0)
    stream = inbound.get('streamSettings', {})
    transport = stream.get('network', 'tcp')
    security = stream.get('security', 'none')
    server_domain = config.get('_domain', '')
    
    print(f\"PROTOCOL='{protocol}'\")
    print(f\"PORT='{port}'\")
    print(f\"TRANSPORT='{transport}'\")
    print(f\"SECURITY='{security}'\")
    print(f\"SERVER_DOMAIN='{server_domain}'\")
    
    if transport == 'ws':
        ws = stream.get('wsSettings', {})
        print(f\"WS_PATH='{ws.get('path', '/')}'\")
        print(f\"WS_HOST='{ws.get('headers', {}).get('Host', '')}'\")
    elif transport == 'grpc':
        grpc = stream.get('grpcSettings', {})
        print(f\"SERVICE_NAME='{grpc.get('serviceName', '')}'\")
        
    if security == 'reality':
        real = stream.get('realitySettings', {})
        print(f\"REALITY_PUBLIC_KEY='{real.get('publicKey', '')}'\")
        print(f\"REALITY_SNI='{real.get('serverNames', [''])[0]}'\")
        print(f\"REALITY_SHORT_ID='{real.get('shortIds', [''])[0]}'\")
    elif security == 'tls':
        tls = stream.get('tlsSettings', {})
        print(f\"TLS_SNI='{tls.get('serverName', '')}'\")
    
    settings = inbound.get('settings', {})
    if protocol == 'shadowsocks':
        print(f\"SS_METHOD='{settings.get('method', '')}'\")
        print(f\"SS_PASSWORD='{settings.get('password', '')}'\")
    elif protocol == 'socks':
        print(f\"SOCKS_AUTH='{settings.get('auth', 'noauth')}'\")
except Exception as e:
    print(\"PROTOCOL='error'\")
")

    local domain_target="${SERVER_DOMAIN}"
    [[ -z "$domain_target" ]] && domain_target="${SERVER_IP}"

    echo -e "\n${BLUE}┌────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  ${BOLD}${GREEN}✅ CÓDIGO DE CONEXIÓN CLIENTE (${PROTOCOL^^})${NC} ${BLUE}│${NC}"
    echo -e "${BLUE}└────────────────────────────────────────┘${NC}\n"

    echo -e "${BOLD}${WHITE}💻 PARÁMETROS:${NC}"
    echo -e "  ${CYAN}• Servidor:${NC}    ${WHITE}${domain_target}${NC}"
    echo -e "  ${CYAN}• Puerto:${NC}      ${WHITE}${PORT}${NC}"
    echo -e "  ${CYAN}• Red:${NC}         ${WHITE}${TRANSPORT}${NC}"
    echo -e "  ${CYAN}• Cifrado:${NC}     ${WHITE}${SECURITY}${NC}"

    case "$PROTOCOL" in
        vless|vmess)
            echo -e "  ${CYAN}• UUID:${NC}        ${YELLOW}${uid}${NC}"
            ;;
        trojan)
            echo -e "  ${CYAN}• Password:${NC}    ${YELLOW}${uid}${NC}"
            ;;
        shadowsocks)
            echo -e "  ${CYAN}• Método:${NC}      ${WHITE}${SS_METHOD}${NC}"
            echo -e "  ${CYAN}• Password:${NC}    ${YELLOW}${SS_PASSWORD}${NC}"
            ;;
        socks)
            echo -e "  ${CYAN}• Auth:${NC}        ${WHITE}${SOCKS_AUTH}${NC}"
            ;;
    esac

    [[ "$TRANSPORT" == "ws" ]] && echo -e "  ${CYAN}• Path WS:${NC}     ${WHITE}${WS_PATH}${NC}" && echo -e "  ${CYAN}• Host WS:${NC}     ${WHITE}${WS_HOST:-$domain_target}${NC}"
    [[ "$TRANSPORT" == "grpc" ]] && echo -e "  ${CYAN}• Service:${NC}     ${WHITE}${SERVICE_NAME}${NC}"

    if [[ "$SECURITY" == "reality" ]]; then
        echo -e "  ${CYAN}• Public Key:${NC}  ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
        echo -e "  ${CYAN}• SNI Target:${NC}  ${WHITE}${REALITY_SNI}${NC}"
        echo -e "  ${CYAN}• Short ID:${NC}    ${YELLOW}${REALITY_SHORT_ID}${NC}"
        echo -e "  ${CYAN}• Flow:${NC}        ${WHITE}xtls-rprx-vision${NC}"
        echo -e "  ${CYAN}• Fingerprint:${NC} ${WHITE}chrome${NC}"
    fi

    local link
    link=$(build_single_link "$uid")

    echo -e "\n${BOLD}${WHITE}🔗 ENLACE DE IMPORTACIÓN:${NC}"
    echo -e "${GREEN}${link}${NC}"
}

build_single_link() {
    local uid="$1"
    eval $($PYTHON_CMD -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    inbound = config['inbounds'][0]
    protocol = inbound.get('protocol', 'desconocido')
    port = inbound.get('port', 0)
    stream = inbound.get('streamSettings', {})
    transport = stream.get('network', 'tcp')
    security = stream.get('security', 'none')
    server_domain = config.get('_domain', '')
    
    print(f\"PROTOCOL='{protocol}'\")
    print(f\"PORT='{port}'\")
    print(f\"TRANSPORT='{transport}'\")
    print(f\"SECURITY='{security}'\")
    print(f\"SERVER_DOMAIN='{server_domain}'\")
    
    if transport == 'ws':
        ws = stream.get('wsSettings', {})
        print(f\"WS_PATH='{ws.get('path', '/')}'\")
        print(f\"WS_HOST='{ws.get('headers', {}).get('Host', '')}'\")
    elif transport == 'grpc':
        grpc = stream.get('grpcSettings', {})
        print(f\"SERVICE_NAME='{grpc.get('serviceName', '')}'\")
        
    if security == 'reality':
        real = stream.get('realitySettings', {})
        print(f\"REALITY_PUBLIC_KEY='{real.get('publicKey', '')}'\")
        print(f\"REALITY_SNI='{real.get('serverNames', [''])[0]}'\")
        print(f\"REALITY_SHORT_ID='{real.get('shortIds', [''])[0]}'\")
    elif security == 'tls':
        tls = stream.get('tlsSettings', {})
        print(f\"TLS_SNI='{tls.get('serverName', '')}'\")
    
    settings = inbound.get('settings', {})
    if protocol == 'shadowsocks':
        print(f\"SS_METHOD='{settings.get('method', '')}'\")
        print(f\"SS_PASSWORD='{settings.get('password', '')}'\")
    elif protocol == 'socks':
        print(f\"SOCKS_AUTH='{settings.get('auth', 'noauth')}'\")
except Exception as e:
    print(\"PROTOCOL='error'\")
")

    local link=""
    local domain_target="${SERVER_DOMAIN}"
    [[ -z "$domain_target" ]] && domain_target="${SERVER_IP}"

    case "$PROTOCOL" in
        vmess)
            local tls_val=""
            [[ "$SECURITY" == "tls" ]] && tls_val="tls"
            local vmess_json="{\"v\":\"2\",\"ps\":\"VMess-${domain_target}\",\"add\":\"${domain_target}\",\"port\":\"${PORT}\",\"id\":\"${uid}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"${TRANSPORT}\",\"type\":\"none\",\"host\":\"${WS_HOST}\",\"path\":\"${WS_PATH}\",\"tls\":\"${tls_val}\",\"sni\":\"${domain_target}\",\"serviceName\":\"${SERVICE_NAME}\"}"
            link="vmess://$(encode_base64 "$vmess_json")"
            ;;

        vless)
            local params="encryption=none"
            if [[ "$TRANSPORT" == "ws" ]]; then
                params="${params}&type=ws&path=$(url_encode "$WS_PATH")&host=$(url_encode "$WS_HOST")"
            elif [[ "$TRANSPORT" == "grpc" ]]; then
                params="${params}&type=grpc&serviceName=$(url_encode "$SERVICE_NAME")"
            else
                params="${params}&type=tcp"
            fi

            if [[ "$SECURITY" == "tls" ]]; then
                params="${params}&security=tls&sni=$(url_encode "$domain_target")"
            elif [[ "$SECURITY" == "reality" ]]; then
                params="${params}&security=reality&pbk=${REALITY_PUBLIC_KEY}&fp=chrome&sni=${REALITY_SNI}&sid=${REALITY_SHORT_ID}&flow=xtls-rprx-vision"
            fi
            
            link="vless://${uid}@${domain_target}:${PORT}?${params}#VLESS-${domain_target}"
            ;;

        trojan)
            local params="type=${TRANSPORT}"
            [[ "$TRANSPORT" == "ws" ]] && params="${params}&path=$(url_encode "$WS_PATH")&host=$(url_encode "$WS_HOST")"
            [[ "$TRANSPORT" == "grpc" ]] && params="${params}&serviceName=$(url_encode "$SERVICE_NAME")"
            [[ "$SECURITY" == "tls" ]] && params="${params}&security=tls&sni=$(url_encode "$domain_target")"

            link="trojan://${uid}@${domain_target}:${PORT}?${params}#Trojan-${domain_target}"
            ;;

        shadowsocks)
            local ss_pass="${SS_PASSWORD:-$uid}"
            local ss_data="${SS_METHOD}:${ss_pass}@${domain_target}:${PORT}"
            link="ss://$(encode_base64 "$ss_data")#SS-${domain_target}"
            ;;

        socks)
            link="socks5://${domain_target}:${PORT}#SOCKS5-${domain_target}"
            ;;
    esac

    echo "$link"
}

add_user_interactive() {
    local new_id

    if [[ "$PROTOCOL" == "trojan" ]]; then
        read_value new_id "Nueva Contraseña [auto]:" "$(generate_password)"
    else
        read_value new_id "Nuevo UUID [auto]:" "$(generate_uuid)"
    fi

    python_inspector "add_client" "$new_id"
    
    if validate_config && restart_service; then
        display_protocol_details "$new_id"
    fi
}

del_user_interactive() {
    header
    echo -e "${BOLD}${WHITE}❌ ELIMINAR USUARIO:${NC}\n"
    python_inspector "list_clients"
    echo

    read_value num_del "Número de usuario a eliminar:" ""
    if [[ -n "$num_del" ]]; then
        python_inspector "del_client" "$num_del"
        validate_config && restart_service
        echo -e "${GREEN}✔ Usuario eliminado.${NC}"
    fi
}

# ==============================================================================
#  MENÚ PRINCIPAL Y CONTROL
# ==============================================================================

show_main_menu() {
    header

    echo -e "${BOLD}${WHITE}🚀 CONFIGURACIÓN DE RED${NC}"
    echo -e " ${YELLOW}1.${NC} 🔍 Gestionar Protocolo Activo"
    echo -e " ${YELLOW}2.${NC} 🔄 Configurar Nuevo Protocolo"
    echo -e " ${YELLOW}3.${NC} 🔒 Certificados SSL / TLS"
    echo -e " ${YELLOW}4.${NC} ✍️  Editar Config JSON Manualmente"
    echo
    echo -e "${BOLD}${WHITE}⚙️  GESTIÓN DEL SERVICIO${NC}"
    echo -e " ${YELLOW}5.${NC} ${GREEN}Iniciar Xray${NC}"
    echo -e " ${YELLOW}6.${NC} ${RED}Detener Xray${NC}"
    echo -e " ${YELLOW}7.${NC} ${CYAN}Reiniciar Xray${NC}"
    echo -e " ${YELLOW}8.${NC} Estado del Servicio"
    echo
    echo -e "${BOLD}${WHITE}🔧 MANTENIMIENTO${NC}"
    echo -e " ${YELLOW}9.${NC} Ver Logs en Vivo"
    echo -e " ${YELLOW}10.${NC} ${RED}Desinstalar Xray y Panel${NC}"
    echo -e " ${YELLOW}11.${NC} Salir del Menú"
    echo
    echo -e "${BLUE}────────────────────────────────────────${NC}"
}

main() {
    require_root
    install_self_command

    # Detectar Python al inicio
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    else
        echo -e "${YELLOW}⚠️ Python no encontrado. Instalando...${NC}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y python3 >/dev/null 2>&1
        if command -v python3 >/dev/null 2>&1; then
            PYTHON_CMD="python3"
        else
            echo -e "${RED}❌ No se pudo instalar Python.${NC}"
            exit 1
        fi
    fi

    if [[ ! -x "${XRAY_BIN}" ]]; then
        header
        echo -e "${CYAN}🚀 Instalando dependencias y Xray Core...${NC}\n"
        if install_v2ray; then
            echo -e "${GREEN}✅ Instalación completada.${NC}"
            echo -e "Accede escribiendo: ${CYAN}menuV2${NC}, ${CYAN}menu${NC} o ${CYAN}v2ray${NC}\n"
            pause_screen
        else
            echo -e "${RED}❌ Error al instalar.${NC}"
            exit 1
        fi
    fi

    while true; do
        show_main_menu
        read_option main_option "Opción [1-11]: "

        case "$main_option" in
            1) manage_active_protocol ;;
            2) configure_new_protocol; pause_screen ;;
            3) 
                read_value ssl_domain "Dominio o IP [${SERVER_IP}]:" "$SERVER_IP"
                mkdir -p "$CERT_DIR"
                generate_self_signed "$ssl_domain"
                if ! is_ip_address "$ssl_domain"; then
                    echo -e "\n${YELLOW}¿Quieres usar Let's Encrypt en lugar del certificado autofirmado?${NC}"
                    read -r -p "$(echo -e "${CYAN}Opción [1=Let's Encrypt, 2=Autofirmado, ENTER=Autofirmado]: ${NC}")" le_choice
                    if [[ "$le_choice" == "1" ]]; then
                        install_letsencrypt "$ssl_domain"
                    fi
                fi
                validate_config && restart_service
                pause_screen
                ;;
            4) 
                if command -v nano >/dev/null 2>&1; then nano "$CONFIG_FILE"; else vi "$CONFIG_FILE"; fi
                validate_config && restart_service
                pause_screen 
                ;;
            5) systemctl start v2ray; pause_screen ;;
            6) systemctl stop v2ray; pause_screen ;;
            7) restart_service; pause_screen ;;
            8) systemctl status v2ray --no-pager; pause_screen ;;
            9) journalctl -u v2ray -f -n 20 ;;
            10) 
                systemctl stop v2ray 2>/dev/null || true
                systemctl disable v2ray 2>/dev/null || true
                rm -rf "$INSTALL_DIR" "$SERVICE_FILE" "$INSTALL_BIN" \
                       "/usr/local/bin/menuV2" "/usr/local/bin/menuv2" "/usr/local/bin/menu" "/usr/local/bin/v2ray" \
                       "/usr/bin/menuV2" "/usr/bin/menuv2" "/usr/bin/menu" "/usr/bin/v2ray"
                systemctl daemon-reload
                hash -r 2>/dev/null || true
                echo -e "\n${GREEN}✔ Panel y Xray desinstalados por completo.${NC}"
                echo -e "${YELLOW}Nota: El comando 'menuV2' ha sido eliminado de la VPS.${NC}\n"
                break
                ;;
            11) 
                echo -e "\n${GREEN}Saliendo del menú... (Tu VPS sigue conectada)${NC}\n"
                break
                ;;
            *) echo -e "${RED}❌ Opción no válida.${NC}"; sleep 1 ;;
        esac
    done
}

main
