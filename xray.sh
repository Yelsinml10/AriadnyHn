cat << 'EOF' > /usr/local/bin/xray
#!/bin/bash
# =========================================================
#  XRAY MANAGER - TRANSFORMED EDITION
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

# Rutas originales respetadas
CONFIG_FILE="/usr/local/xray/config.json"
XRAY_BIN="/usr/local/xray/xray"
SERVICE_FILE="/etc/systemd/system/xray.service"
CERT_DIR="/usr/local/xray"
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
    if [[ ! -x "$XRAY_BIN" || ! -f "$SERVICE_FILE" ]]; then
        echo -e "${CYAN}${BOLD}⚡ Instalando dependencias básicas y Xray Core...${NC}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y python3 wget unzip curl openssl certbot iptables-persistent >/dev/null 2>&1
        
        if ! command -v python3 &>/dev/null; then
            echo -e "${YELLOW}⚠️ Python3 no encontrado, instalando...${NC}"
            apt-get install -y python3 python3-json >/dev/null 2>&1
        fi
        
        mkdir -p /usr/local/xray

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

        local ARCH=$(uname -m)
        local XURL="https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-64.zip"
        if [[ "$ARCH" == *"aarch64"* || "$ARCH" == *"arm64"* ]]; then
            XURL="https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-arm64-v8a.zip"
        fi
        wget -q "$XURL" -O /tmp/xray.zip
        unzip -o /tmp/xray.zip -d /usr/local/xray/ >/dev/null 2>&1
        chmod +x /usr/local/xray/xray
        rm -f /tmp/xray.zip

        cat > "$SERVICE_FILE" <<EOFS
[Unit]
Description=Xray Core Service
After=network.target
[Service]
ExecStart=${XRAY_BIN} run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOFS
        systemctl daemon-reload >/dev/null 2>&1
        echo -e "${GREEN}✔ Instalación base completada exitosamente.${NC}\n"
        sleep 1
    fi
}

get_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e "${GREEN}● ONLINE / FUNCIONANDO${NC}"
    elif [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}● OFFLINE / DETENIDO${NC}"
    else
        echo -e "${YELLOW}● SIN CONFIGURACIÓN${NC}"
    fi
}

header() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                XRAY MANAGER PANEL (v1.8.24)             ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo -e " ${PURPLE}${BOLD}▸ IP Servidor:${NC} ${YELLOW}${SERVER_IP}${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Estado Xray:${NC} $(get_status)"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────${NC}"
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
    mkdir -p /usr/local/xray

    open_port 80
    open_port 443

    if [[ "$domain" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${YELLOW}⚙️ Generando certificado autofirmado para IP (${domain})...${NC}"
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=Xray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        echo -e "${GREEN}✔ Certificado autofirmado generado.${NC}"
        return 0
    fi

    header
    echo -e "${PURPLE}${BOLD}[ 🔒 CONFIGURACIÓN SSL / TLS PARA DOMINIO ]${NC}\n"
    echo -e " Dominio detectado: ${YELLOW}${domain}${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}Let's Encrypt (Oficial)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${YELLOW}Autofirmado (Recomendado)${NC}\n"
    read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}Selecciona una opción [1-2]: ${NC}")" cert_opt

    if [[ "$cert_opt" != "1" ]]; then
        echo -e "${YELLOW}⚙️ Generando certificado autofirmado...${NC}"
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=Xray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        echo -e "${GREEN}✔ Certificado autofirmado generado.${NC}"
        return 0
    fi

    echo -e "\n${CYAN}⚙️ Solicitando certificado Let's Encrypt...${NC}"
    apt-get install -y certbot >/dev/null 2>&1

    systemctl stop xray 2>/dev/null
    systemctl stop nginx 2>/dev/null
    systemctl stop apache2 2>/dev/null
    systemctl stop caddy 2>/dev/null

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

    echo -e "\n${YELLOW}⚠️ Let's Encrypt no disponible. Usando autofirmado...${NC}"
    openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 3650 \
        -key "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=Xray/CN=${domain}" >/dev/null 2>&1
    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"
    echo -e "${GREEN}✔ Certificado autofirmado generado (funciona igual para TLS).${NC}"
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
pub_key = cfg.get("_pub_key", "")
sni = cfg.get("_sni", "")
short_id = cfg.get("_short_id", "")

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

if sec == "reality":
    print(f"\033[1;37mPublic Key  :\033[0m \033[1;33m{pub_key}\033[0m")
    print(f"\033[1;37mSNI         :\033[0m \033[0;36m{sni}\033[0m")
    print(f"\033[1;37mShort ID    :\033[0m \033[0;36m{short_id}\033[0m")

clients = st.get("clients", [])
print("\n\033[1;35m--- USUARIOS Y ENLACES DE CONEXIÓN ---\033[0m\n")

for idx, c in enumerate(clients, 1):
    user_id = c.get("id") or c.get("password") or ""
    print(f"\033[1;37m[Usuario {idx}]\033[0m Contraseña / ID: \033[1;33m{user_id}\033[0m")
    
    link = ""
    if proto == "vless":
        if sec == "reality":
            link = f"vless://{user_id}@{dom}:{port}?type=tcp&security=reality&encryption=none&pbk={pub_key}&fp=chrome&sni={sni}&sid={short_id}&flow=xtls-rprx-vision#Xray-VLESS-REALITY"
        else:
            params = f"encryption=none&type={trans}&security={sec}"
            if trans == "ws":
                params += f"&path={urllib.parse.quote(extra)}&host={urllib.parse.quote(ws_host)}"
            elif trans == "grpc":
                params += f"&serviceName={urllib.parse.quote(extra)}&mode=gun"
            if sec == "tls":
                params += f"&sni={urllib.parse.quote(dom)}"
            link = f"vless://{user_id}@{dom}:{port}?{params}#Xray-VLESS"

    elif proto == "vmess":
        v_json = {
            "v": "2", "ps": f"Xray-VMess-{idx}", "add": dom, "port": str(port),
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
        link = f"trojan://{user_id}@{dom}:{port}?{params}#Xray-Trojan"

    elif proto == "shadowsocks":
        method = st.get("method", "aes-256-gcm")
        b64_ss = base64.b64encode(f"{method}:{user_id}".encode()).decode()
        link = f"ss://{b64_ss}@{dom}:{port}#Xray-Shadowsocks"

    elif proto == "socks":
        link = f"socks5://{dom}:{port}#Xray-SOCKS5"

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
    if [[ "$proto" == "vless" ]]; then
        echo -e "  ${WHITE}${BOLD}[ 7 ]${NC} ${GREEN}VLESS + REALITY (Vision)${NC}"
    fi
    echo
    read -r -p "$(echo -e "${YELLOW}➜ ${NC}${BOLD}Opción: ${NC}")" topt

    local trans="tcp" sec="none" sni="" dest="" priv_key="" pub_key="" short_id=""
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
        7) 
            if [[ "$proto" == "vless" ]]; then
                trans="tcp"; sec="reality"
                read_val sni "Target SNI (ej: www.apple.com):" "www.apple.com"
                read_val dest "Target Dest (ej: www.apple.com:443):" "www.apple.com:443"
                
                if [[ -x "$XRAY_BIN" ]]; then
                    local keypair=$($XRAY_BIN x25519 2>/dev/null)
                    priv_key=$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}' | tr -d ' ')
                    pub_key=$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}' | tr -d ' ')
                fi
                if [[ -z "$priv_key" ]]; then
                    priv_key=$(openssl rand -base64 32 2>/dev/null | head -c 43)
                    pub_key=$(openssl rand -base64 32 2>/dev/null | head -c 43)
                fi
                short_id=$(openssl rand -hex 4 2>/dev/null || echo "1a2b3c4d")
            else
                trans="tcp"; sec="none"
            fi
            ;;
        *) trans="tcp"; sec="none" ;;
    esac

    if [[ "$sec" == "tls" ]]; then
        setup_tls_cert "$dom"
    fi

    python3 - "$CONFIG_FILE" "$proto" "$port" "$trans" "$sec" "$user" "$extra" "$dom" "$sni" "$dest" "$priv_key" "$pub_key" "$short_id" "$host_header" "$CERT_DIR" <<'PY'
import json, sys

cfg_file    = sys.argv[1]
proto       = sys.argv[2]
port        = int(sys.argv[3])
trans       = sys.argv[4]
sec         = sys.argv[5]
user        = sys.argv[6]
extra       = sys.argv[7]
dom         = sys.argv[8]
sni         = sys.argv[9] if len(sys.argv) > 9 else ""
dest        = sys.argv[10] if len(sys.argv) > 10 else ""
priv_key    = sys.argv[11] if len(sys.argv) > 11 else ""
pub_key     = sys.argv[12] if len(sys.argv) > 12 else ""
short_id    = sys.argv[13] if len(sys.argv) > 13 else ""
host_header = sys.argv[14] if len(sys.argv) > 14 else dom
cert_dir    = sys.argv[15] if len(sys.argv) > 15 else ""

config = {
    "_domain": dom,
    "_pub_key": pub_key,
    "_sni": sni,
    "_short_id": short_id,
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
    client_obj = {"id": user}
    if sec == "reality":
        client_obj["flow"] = "xtls-rprx-vision"
    st["clients"] = [client_obj]
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

if sec == "reality":
    str_st["realitySettings"] = {
        "show": False,
        "dest": dest,
        "xver": 0,
        "serverNames": [sni],
        "privateKey": priv_key,
        "shortIds": [short_id]
    }

with open(cfg_file, "w") as f:
    json.dump(config, f, indent=2)
PY

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1

    sleep 1
    if systemctl is-active --quiet xray; then
        echo -e "\n${GREEN}✔ Configuración aplicada y Xray reiniciado exitosamente.${NC}"
    else
        echo -e "\n${RED}❌ Error: Xray no pudo iniciar. Revisa los logs.${NC}"
        journalctl -u xray -n 10 --no-pager
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
        if str_st.get("security") == "reality":
            client_obj["flow"] = "xtls-rprx-vision"
        st["clients"].append(client_obj)

with open(cfg_file, "w") as f: json.dump(cfg, f, indent=2)
PY
    systemctl restart xray >/dev/null 2>&1
}

# Si se ejecuta con argumentos de servicio, pasar al binario real
if [[ "$1" == "run" ]] || [[ "$1" == "-config" ]] || [[ "$1" == "run-config" ]]; then
    exec /usr/local/xray/xray "$@"
fi

# 1. Verificar root e instalar binaries base si no están
check_root
install_core_if_missing

# 2. Si no hay configuración previa, abrir directo la selección de protocolos
if [[ ! -f "$CONFIG_FILE" ]]; then
    configure_protocol
fi

# 3. Bucle del menú administrativo
while true; do
    header
    echo -e " ${YELLOW}${BOLD}⚙️  PANEL PRINCIPAL XRAY${NC}"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}🔄 Cambiar Protocolo / Transmisión${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}🔌 Cambiar Puerto${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}🛤️  Cambiar Path WS / Host Header / ServiceName gRPC${NC}"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}🔑 Cambiar ID / Contraseña Principal${NC}"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}➕ Agregar Nuevo Usuario / ID${NC}"
    echo -e "  ${WHITE}${BOLD}[ 6 ]${NC} ${CYAN}📋 Ver Datos de Conexión / Links${NC}"
    echo -e "  ${WHITE}${BOLD}[ 7 ]${NC} ${YELLOW}🔍 Ver Logs en Vivo (Monitoreo HTTP Custom)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 8 ]${NC} ${CYAN}🔄 Reiniciar Servicio Xray${NC}"
    echo -e "  ${WHITE}${BOLD}[ 9 ]${NC} ${RED}🗑️  Desinstalar Xray por Completo${NC}"
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}🚪 Salir del Menú${NC}"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────${NC}"
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
            journalctl -u xray -f
            ;;
        8)
            systemctl restart xray >/dev/null 2>&1
            echo -e "${GREEN}✔ Xray reiniciado exitosamente.${NC}"
            sleep 1.5
            ;;
        9)
            systemctl stop xray 2>/dev/null
            systemctl disable xray 2>/dev/null
            rm -rf /usr/local/xray /etc/systemd/system/xray.service /usr/local/bin/xray
            systemctl daemon-reload
            echo -e "${GREEN}✔ Desinstalación completa realizada.${NC}"
            exit 0
            ;;
        0) exit 0 ;;
        *) sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/xray

# 🔥 EJECUTAR AUTOMÁTICAMENTE LA PRIMERA VEZ
echo -e "\n${CYAN}${BOLD}🚀 Iniciando instalación automática...${NC}\n"
/usr/local/bin/xray
