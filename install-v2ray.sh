cat << 'EOF' > /usr/local/bin/v2ray
#!/bin/bash
# =========================================================
#  V2RAY MANAGER - OFFICIAL EDITION (v2fly/v2ray-core)
# =========================================================

export TERM=xterm

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Rutas del sistema para V2Ray
CONFIG_FILE="/usr/local/v2ray/config.json"
V2RAY_BIN="/usr/local/v2ray/v2ray"
SERVICE_FILE="/etc/systemd/system/v2ray.service"
CERT_DIR="/usr/local/v2ray"
SERVER_IP=$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null || echo "127.0.0.1")

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "\n${RED}${BOLD}[✗] Requiere permisos de root para ejecutar este script.${NC}\n"
       exit 1
    fi
}

open_port() {
    local port="$1"
    if [[ -n "$port" ]]; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        ip6tables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        ip6tables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        if command -v ufw >/dev/null 2>&1; then
            ufw allow "$port"/tcp >/dev/null 2>&1
            ufw allow "$port"/udp >/dev/null 2>&1
        fi
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}

install_core_if_missing() {
    if [[ ! -x "$V2RAY_BIN" || ! -f "$SERVICE_FILE" ]]; then
        echo -e "${CYAN}${BOLD}⚡ Instalando dependencias y V2Ray Core oficial (v2fly)...${NC}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y python3 wget unzip curl openssl certbot iptables-persistent >/dev/null 2>&1
        
        if ! command -v python3 &>/dev/null; then
            echo -e "${YELLOW}⚠️ Python3 no encontrado, instalando...${NC}"
            apt-get install -y python3 python3-json >/dev/null 2>&1
        fi
        
        mkdir -p /usr/local/v2ray

        # Configurar Swap si la RAM es baja (< 1GB)
        local total_mem
        total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        if [[ -n "$total_mem" && "$total_mem" -lt 1024 ]]; then
            if [[ $(swapon --show 2>/dev/null | wc -l) -eq 0 ]]; then
                fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 2>/dev/null
                chmod 600 /swapfile
                mkswap /swapfile >/dev/null 2>&1
                swapon /swapfile >/dev/null 2>&1
            fi
        fi

        # Detectar arquitectura y obtener la versión
        local ARCH=$(uname -m)
        local V2ARCH="64"
        if [[ "$ARCH" == *"aarch64"* || "$ARCH" == *"arm64"* ]]; then
            V2ARCH="arm64-v8a"
        elif [[ "$ARCH" == *"armv7"* ]]; then
            V2ARCH="arm32-v7a"
        fi

        local LATEST_TAG
        LATEST_TAG=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [[ -z "$LATEST_TAG" ]] && LATEST_TAG="v5.14.1"

        local V2URL="https://github.com/v2fly/v2ray-core/releases/download/${LATEST_TAG}/v2ray-linux-${V2ARCH}.zip"
        
        echo -e "${CYAN}Descargando V2Ray Core (${LATEST_TAG})...${NC}"
        wget -q "$V2URL" -O /tmp/v2ray.zip
        unzip -o /tmp/v2ray.zip -d /usr/local/v2ray/ >/dev/null 2>&1
        chmod +x /usr/local/v2ray/v2ray
        rm -f /tmp/v2ray.zip

        # Crear servicio systemd
        cat > "$SERVICE_FILE" <<EOFS
[Unit]
Description=V2Ray Core Service
After=network.target
[Service]
ExecStart=${V2RAY_BIN} run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOFS
        systemctl daemon-reload >/dev/null 2>&1
        echo -e "${GREEN}✔ Instalación base de V2Ray Core completada.${NC}\n"
        sleep 1
    fi
}

get_status() {
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        echo -e "${GREEN}● ONLINE / FUNCIONANDO${NC}"
    elif [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}● OFFLINE / DETENIDO${NC}"
    else
        echo -e "${YELLOW}● SIN CONFIGURACIÓN${NC}"
    fi
}

header() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║             V2RAY MANAGER PANEL (v2fly-core)             ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e " ${PURPLE}${BOLD}▸ IP Servidor:${NC} ${YELLOW}${SERVER_IP}${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Estado V2Ray:${NC} $(get_status)"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────────────${NC}"
}

pause_screen() {
    echo
    read -r -p "$(echo -e "${YELLOW}Presiona [ENTER] para regresar al menú...${NC}")" _
}

read_val() {
    local var="$1" prompt="$2" def="$3" val
    read -r -p "$(echo -e "${CYAN}➜ ${NC}${WHITE}${prompt}${NC} ")" val
    [[ -z "$val" ]] && val="$def"
    printf -v "$var" '%s' "$val"
}

setup_tls_cert() {
    local domain="$1"
    mkdir -p /usr/local/v2ray

    open_port 80
    open_port 443

    if [[ "$domain" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${YELLOW}⚠️ Generando certificado autofirmado para IP (${domain})...${NC}"
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        echo -e "${GREEN}✔ Certificado autofirmado generado.${NC}"
        return 0
    fi

    header
    echo -e "${PURPLE}${BOLD}[ 🔒 CONFIGURACIÓN SSL / TLS PARA DOMINIO ]${NC}\n"
    echo -e " Dominio detectado: ${YELLOW}${domain}${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}Let's Encrypt (Oficial)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${YELLOW}Autofirmado (Rápido / Pruebas)${NC}\n"
    read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}Selecciona una opción [1-2]: ${NC}")" cert_opt

    if [[ "$cert_opt" != "1" ]]; then
        echo -e "${YELLOW}⚠️ Generando certificado autofirmado...${NC}"
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        echo -e "${GREEN}✔ Certificado autofirmado generado.${NC}"
        return 0
    fi

    echo -e "\n${CYAN}⚠️ Solicitando certificado Let's Encrypt...${NC}"
    apt-get install -y certbot >/dev/null 2>&1

    systemctl stop v2ray 2>/dev/null
    systemctl stop nginx 2>/dev/null
    systemctl stop apache2 2>/dev/null

    local cert_output
    cert_output=$(certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email 2>&1)
    local cert_exit=$?

    if [[ $cert_exit -eq 0 ]] && [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        cp -f "/etc/letsencrypt/live/${domain}/fullchain.pem" "${CERT_DIR}/cert.pem"
        cp -f "/etc/letsencrypt/live/${domain}/privkey.pem" "${CERT_DIR}/key.pem"
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        echo -e "${GREEN}✔ Certificado Let's Encrypt instalado.${NC}"
        sleep 1.5
        return 0
    fi

    echo -e "\n${YELLOW}⚠️ Let's Encrypt falló. Generando certificado autofirmado...${NC}"
    openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 3650 \
        -key "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain}" >/dev/null 2>&1
    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"
    echo -e "${GREEN}✔ Certificado autofirmado generado.${NC}"
    return 0
}

show_info() {
    header
    echo -e "${PURPLE}${BOLD}[ 📋 DATOS DE CONEXIÓN ACTUAL ]${NC}\n"
    python3 - "$CONFIG_FILE" <<'PY'
import json, sys, base64, urllib.parse

try:
    with open(sys.argv[1], "r") as f:
        cfg = json.load(f)
except Exception:
    print("\033[0;31mError al leer la configuración actual.\033[0m")
    sys.exit(1)

dom = cfg.get("_domain", "127.0.0.1")

inb = cfg["inbounds"][0]
proto = inb.get("protocol", "desconocido")
port = inb.get("port", 443)
st = inb.get("settings", {})
str_st = inb.get("streamSettings", {})
trans = str_st.get("network", "tcp")
sec = str_st.get("security", "none")

extra = ""
ws_host = dom
if trans == "ws":
    ws_st = str_st.get("wsSettings", {})
    extra = ws_st.get("path", "/ray")
    ws_host = ws_st.get("headers", {}).get("Host", dom)
elif trans == "grpc":
    extra = str_st.get("grpcSettings", {}).get("serviceName", "grpc")

print(f"\033[1;37mProtocolo   :\033[0m \033[0;36m{proto.upper()}\033[0m")
print(f"\033[1;37mHost / IP   :\033[0m \033[1;33m{dom}\033[0m")
print(f"\033[1;37mPuerto      :\033[0m \033[0;32m{port}\033[0m")
print(f"\033[1;37mTransporte  :\033[0m \033[0;36m{trans}\033[0m")
print(f"\033[1;37mSeguridad   :\033[0m \033[0;36m{sec}\033[0m")

if trans == "ws":
    print(f"\033[1;37mPath WS     :\033[0m \033[0;36m{extra}\033[0m")
    print(f"\033[1;37mHost WS     :\033[0m \033[1;33m{ws_host}\033[0m")
elif trans == "grpc":
    print(f"\033[1;37mServiceName :\033[0m \033[0;36m{extra}\033[0m")

clients = st.get("clients", [])
print("\n\033[1;35m--- USUARIOS Y ENLACES DE CONEXIÓN ---\033[0m\n")

for idx, c in enumerate(clients, 1):
    user_id = c.get("id") or c.get("password") or ""
    print(f"\033[1;37m[Usuario {idx}]\033[0m Contraseña / ID: \033[1;33m{user_id}\033[0m")
    
    link = ""
    if proto == "vless":
        params = f"encryption=none&type={trans}&security={sec}"
        if trans == "ws":
            params += f"&path={urllib.parse.quote(extra)}&host={urllib.parse.quote(ws_host)}"
        elif trans == "grpc":
            params += f"&serviceName={urllib.parse.quote(extra)}&mode=gun"
        if sec == "tls":
            params += f"&sni={urllib.parse.quote(dom)}"
        link = f"vless://{user_id}@{dom}:{port}?{params}#V2Ray-VLESS"

    elif proto == "vmess":
        v_json = {
            "v": "2", "ps": f"V2Ray-VMess-{idx}", "add": dom, "port": str(port),
            "id": user_id, "aid": "0", "net": trans, "type": "none",
            "host": ws_host if trans == "ws" else "",
            "path": extra if trans == "ws" else "",
            "tls": "tls" if sec == "tls" else "",
            "sni": dom if sec == "tls" else "",
            "serviceName": extra if trans == "grpc" else ""
        }
        b64 = base64.b64encode(json.dumps(v_json).encode()).decode()
        link = f"vmess://{b64}"

    elif proto == "trojan":
        params = f"type={trans}&security={sec}"
        if trans == "ws":
            params += f"&path={urllib.parse.quote(extra)}&host={urllib.parse.quote(ws_host)}"
        elif trans == "grpc":
            params += f"&serviceName={urllib.parse.quote(extra)}"
        if sec == "tls":
            params += f"&sni={urllib.parse.quote(dom)}"
        link = f"trojan://{user_id}@{dom}:{port}?{params}#V2Ray-Trojan"

    elif proto == "shadowsocks":
        method = st.get("method", "aes-256-gcm")
        b64_ss = base64.b64encode(f"{method}:{user_id}".encode()).decode()
        link = f"ss://{b64_ss}@{dom}:{port}#V2Ray-Shadowsocks"

    elif proto == "socks":
        link = f"socks5://{dom}:{port}#V2Ray-SOCKS5"

    if link:
        print(f"\033[0;32mEnlace de Conexión:\033[0m\n{link}\n")

PY
    pause_screen
}

configure_protocol() {
    header
    echo -e "${PURPLE}${BOLD}🌐 SELECCIONA UN PROTOCOLO:${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}VLESS${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}VMess${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Trojan${NC}"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Shadowsocks${NC}"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${CYAN}SOCKS5${NC}"
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver al Menú${NC}\n"
    read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}Opción [0-5]: ${NC}")" popt

    local proto=""
    case "$popt" in
        1) proto="vless" ;;
        2) proto="vmess" ;;
        3) proto="trojan" ;;
        4) proto="shadowsocks" ;;
        5) proto="socks" ;;
        0) return ;;
        *) return ;;
    esac

    header
    echo -e "${PURPLE}${BOLD}📝 DATOS DE CONEXIÓN:${NC}\n"
    local dom="$SERVER_IP" port="443" extra="" user="" host_header="$SERVER_IP"
    read_val dom "Dominio o IP [${SERVER_IP}]:" "$SERVER_IP"
    host_header="$dom"
    read_val port "Puerto [443]:" "443"

    open_port "$port"

    local auto_user
    if command -v python3 &>/dev/null; then
        auto_user=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null)
    fi
    if [[ -z "$auto_user" ]]; then
        auto_user=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s | sha256sum | head -c 32)
    fi
    
    local prompt_user="Contraseña / ID (UUID) [Auto]:"
    if [[ "$proto" == "trojan" ]]; then
        prompt_user="Contraseña Trojan [Auto]:"
    fi
    read_val user "$prompt_user" "$auto_user"

    header
    echo -e "${PURPLE}${BOLD}🛠️  TRANSPORTE Y SEGURIDAD:${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} TCP Directo"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} TCP + TLS"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} WebSocket (WS)"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} WebSocket + TLS"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} gRPC"
    echo -e "  ${WHITE}${BOLD}[ 6 ]${NC} gRPC + TLS"
    echo
    read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}Opción: ${NC}")" topt

    local trans="tcp" sec="none"
    case "$topt" in
        1) trans="tcp"; sec="none" ;;
        2) trans="tcp"; sec="tls" ;;
        3) 
            trans="ws"; sec="none"
            read_val extra "Path WS [/ray]:" "/ray"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        4) 
            trans="ws"; sec="tls"
            read_val extra "Path WS [/ray]:" "/ray"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        5) 
            trans="grpc"; sec="none"
            read_val extra "Service Name gRPC [grpc]:" "grpc"
            ;;
        6) 
            trans="grpc"; sec="tls"
            read_val extra "Service Name gRPC [grpc]:" "grpc"
            ;;
        *) trans="tcp"; sec="none" ;;
    esac

    if [[ "$sec" == "tls" ]]; then
        setup_tls_cert "$dom"
    fi

    python3 - "$CONFIG_FILE" "$proto" "$port" "$trans" "$sec" "$user" "$extra" "$dom" "$host_header" "$CERT_DIR" <<'PY'
import json, sys

cfg_file    = sys.argv[1]
proto       = sys.argv[2]
port        = int(sys.argv[3])
trans       = sys.argv[4]
sec         = sys.argv[5]
user        = sys.argv[6]
extra       = sys.argv[7]
dom         = sys.argv[8]
host_header = sys.argv[9] if len(sys.argv) > 9 else dom
cert_dir    = sys.argv[10] if len(sys.argv) > 10 else ""

config = {
    "_domain": dom,
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "listen": "0.0.0.0",
        "port": port,
        "protocol": proto,
        "settings": {},
        "streamSettings": {
            "network": trans,
            "security": sec
        },
        "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}
    }],
    "outbounds": [{"protocol": "freedom"}]
}

inb = config["inbounds"][0]
st = inb["settings"]
str_st = inb["streamSettings"]

if proto in ["vless", "vmess"]:
    st["clients"] = [{"id": user}]
    if proto == "vless":
        st["decryption"] = "none"
elif proto == "trojan":
    st["clients"] = [{"password": user}]
elif proto == "shadowsocks":
    st["method"] = "aes-256-gcm"
    st["password"] = user
elif proto == "socks":
    st["auth"] = "noauth"

if trans == "ws":
    str_st["wsSettings"] = {"path": extra, "headers": {"Host": host_header}}
elif trans == "grpc":
    str_st["grpcSettings"] = {"serviceName": extra, "multiMode": False}

if sec == "tls" and cert_dir:
    str_st["tlsSettings"] = {
        "serverName": dom,
        "certificates": [{
            "certificateFile": f"{cert_dir}/cert.pem",
            "keyFile": f"{cert_dir}/key.pem"
        }]
    }

with open(cfg_file, "w") as f:
    json.dump(config, f, indent=2)
PY

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable v2ray >/dev/null 2>&1
    systemctl restart v2ray >/dev/null 2>&1

    sleep 1
    if systemctl is-active --quiet v2ray; then
        echo -e "\n${GREEN}✔ Configuración aplicada y V2Ray reiniciado exitosamente.${NC}"
    else
        echo -e "\n${RED}❌ Error: V2Ray no pudo iniciar. Revisa los logs.${NC}"
        journalctl -u v2ray -n 10 --no-pager
    fi
    show_info
}

modify_param() {
    local action="$1" val="$2" val2="$3"
    python3 - "$CONFIG_FILE" "$action" "$val" "$val2" <<'PY'
import json, sys
cfg_file, act, val = sys.argv[1:4]
val2 = sys.argv[4] if len(sys.argv) > 4 else ""

try:
    with open(cfg_file, "r") as f: cfg = json.load(f)
except: sys.exit(1)
inb = cfg["inbounds"][0]
st = inb.get("settings", {})
str_st = inb.get("streamSettings", {})

if act == "port": inb["port"] = int(val)
elif act == "path":
    if str_st.get("network") == "ws":
        str_st.setdefault("wsSettings", {})["path"] = val
        if val2:
            str_st.setdefault("wsSettings", {}).setdefault("headers", {})["Host"] = val2
    elif str_st.get("network") == "grpc":
        str_st.setdefault("grpcSettings", {})["serviceName"] = val
elif act == "id":
    if "clients" in st and len(st["clients"]) > 0:
        if "id" in st["clients"][0]: st["clients"][0]["id"] = val
        elif "password" in st["clients"][0]: st["clients"][0]["password"] = val
elif act == "add_id":
    if "clients" in st:
        client_obj = {}
        if "id" in st["clients"][0]: client_obj["id"] = val
        elif "password" in st["clients"][0]: client_obj["password"] = val
        st["clients"].append(client_obj)

with open(cfg_file, "w") as f: json.dump(cfg, f, indent=2)
PY
    systemctl restart v2ray >/dev/null 2>&1
}

# Redireccionar comandos de servicio
if [[ "$1" == "run" ]] || [[ "$1" == "-config" ]] || [[ "$1" == "run-config" ]]; then
    exec /usr/local/v2ray/v2ray "$@"
fi

# 1. Verificar root e instalar binaries base si faltan
check_root
install_core_if_missing

# 2. Si no hay configuración previa, abrir directo la selección de protocolos
if [[ ! -f "$CONFIG_FILE" ]]; then
    configure_protocol
fi

# 3. Menú administrativo
while true; do
    header
    echo -e " ${YELLOW}${BOLD}⚠️  PANEL PRINCIPAL V2RAY${NC}"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}🔄 Cambiar Protocolo / Transmisión${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}🔌 Cambiar Puerto${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}🛤️  Cambiar Path WS / Host Header / ServiceName gRPC${NC}"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}🔑 Cambiar ID / Contraseña Principal${NC}"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}➕ Agregar Nuevo Usuario / ID${NC}"
    echo -e "  ${WHITE}${BOLD}[ 6 ]${NC} ${CYAN}📋 Ver Datos de Conexión / Links${NC}"
    echo -e "  ${WHITE}${BOLD}[ 7 ]${NC} ${YELLOW}🔍 Ver Logs en Vivo${NC}"
    echo -e "  ${WHITE}${BOLD}[ 8 ]${NC} ${CYAN}🔄 Reiniciar Servicio V2Ray${NC}"
    echo -e "  ${WHITE}${BOLD}[ 9 ]${NC} ${RED}🗑️  Desinstalar V2Ray por Completo${NC}"
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}🚪 Salir del Menú${NC}"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────────────${NC}"
    read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}Opción [0-9]: ${NC}")" op

    case "$op" in
        1) configure_protocol ;;
        2)
            read_val np "Nuevo Puerto:" "443"
            open_port "$np"
            modify_param "port" "$np"
            echo -e "${GREEN}✔ Puerto actualizado a $np y abierto en Firewall.${NC}"
            pause_screen
            ;;
        3)
            read_val npath "Nuevo Path WS / ServiceName gRPC:" "/ray"
            read_val nhost "Nuevo Host Header WS (Enter para omitir):" ""
            modify_param "path" "$npath" "$nhost"
            echo -e "${GREEN}✔ Parámetros actualizados exitosamente.${NC}"
            pause_screen
            ;;
        4)
            nid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)
            read_val nid "Nueva ID/Contraseña:" "$nid"
            modify_param "id" "$nid"
            echo -e "${GREEN}✔ ID/Contraseña actualizada a $nid${NC}"
            pause_screen
            ;;
        5)
            aid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)
            read_val aid "ID/Contraseña a agregar:" "$aid"
            modify_param "add_id" "$aid"
            echo -e "${GREEN}✔ ID/Contraseña $aid agregada correctamente.${NC}"
            pause_screen
            ;;
        6) show_info ;;
        7)
            echo -e "\n${YELLOW}Presiona CTRL + C para detener el monitoreo de logs...${NC}\n"
            sleep 1.5
            journalctl -u v2ray -f
            ;;
        8)
            systemctl restart v2ray >/dev/null 2>&1
            echo -e "${GREEN}✔ V2Ray reiniciado exitosamente.${NC}"
            sleep 1.5
            ;;
        9)
            systemctl stop v2ray 2>/dev/null
            systemctl disable v2ray 2>/dev/null
            rm -rf /usr/local/v2ray /etc/systemd/system/v2ray.service /usr/local/bin/v2ray
            systemctl daemon-reload
            echo -e "${GREEN}✔ Desinstalación completa realizada.${NC}"
            exit 0
            ;;
        0) exit 0 ;;
        *) sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/v2ray

# EJECUTAR AUTOMÁTICAMENTE LA PRIMERA VEZ
echo -e "\n${CYAN}${BOLD}🚀 Iniciando V2Ray Manager...${NC}\n"
/usr/local/bin/v2ray
