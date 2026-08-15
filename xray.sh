cat << 'EOF' > /usr/local/bin/xray
#!/bin/bash
# =========================================================
#  XRAY MANAGER - FIXED & OPTIMIZED EDITION
# =========================================================

export TERM=xterm
export DEBIAN_FRONTEND=noninteractive

# Auto-limpieza de caracteres de fin de línea de Windows (CRLF a LF)
sed -i 's/\r$//' "$0" 2>/dev/null

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

CONFIG_FILE="/usr/local/xray/config.json"
XRAY_BIN="/usr/local/xray/xray"
SERVICE_FILE="/etc/systemd/system/xray.service"
CERT_DIR="/usr/local/xray"
LOCK_FILE="/tmp/xray_manager.lock"

# Crear accesos directos
install_shortcuts() {
    chmod +x /usr/local/bin/xray 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/local/bin/v2ray 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/local/bin/menu 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/bin/xray 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/bin/v2ray 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/bin/menu 2>/dev/null
}

detect_ip() {
    local ip=""
    ip=$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(curl -4 -fsS --max-time 3 https://icanhazip.com 2>/dev/null | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1 | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    
    echo "127.0.0.1"
}

SERVER_IP=$(detect_ip)

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
    fi
}

install_core_if_missing() {
    if [[ ! -x "$XRAY_BIN" || ! -f "$SERVICE_FILE" ]]; then
        echo -e "${CYAN}${BOLD}⚡ Instalando dependencias básicas y Xray Core...${NC}"
        
        killall apt apt-get dpkg 2>/dev/null
        rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock* /var/cache/apt/archives/lock 2>/dev/null

        apt-get update -y -qq >/dev/null 2>&1
        apt-get install -y -qq python3 wget unzip curl openssl certbot psmisc >/dev/null 2>&1
        
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

        echo -e "${CYAN}Descargando Xray Core...${NC}"
        wget -q --timeout=30 "$XURL" -O /tmp/xray.zip
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
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}                XRAY MANAGER PANEL (v1.8.24)             ${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e " ${PURPLE}${BOLD}▸ IP Servidor:${NC}  ${YELLOW}${SERVER_IP}${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Estado Xray:${NC}  $(get_status)"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────${NC}"
}

pause_screen() {
    echo
    echo -e -n "${YELLOW}Presiona [ENTER] para regresar al menú...${NC}"
    read -r _
}

read_val() {
    local var="$1" prompt="$2" def="$3" val
    echo -e -n "${CYAN}➜ ${NC}${WHITE}${prompt}${NC} "
    read -r val
    val=$(echo "$val" | tr -d '\r\n')
    [[ -z "$val" ]] && val="$def"
    printf -v "$var" '%s' "$val"
}

setup_tls_cert() {
    local domain="$1"
    mkdir -p /usr/local/xray

    open_port 80
    open_port 443

    if [[ "$domain" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=Xray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        return 0
    fi

    header
    echo -e "${PURPLE}${BOLD}[ 🔒 CONFIGURACIÓN SSL / TLS PARA DOMINIO ]${NC}\n"
    echo -e " Dominio detectado: ${YELLOW}${domain}${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}Let's Encrypt (Oficial / Válido)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${YELLOW}Autofirmado (Rápido / Pruebas)${NC}\n"
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Selecciona una opción [1-2]: ${NC}"
    read -r cert_opt

    if [[ "$cert_opt" == "1" ]]; then
        if ! command -v certbot >/dev/null 2>&1; then
            apt-get update -y -qq >/dev/null 2>&1
            apt-get install -y -qq certbot >/dev/null 2>&1
        fi

        systemctl stop xray 2>/dev/null
        fuser -k 80/tcp >/dev/null 2>&1

        DEBIAN_FRONTEND=noninteractive certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email >/dev/null 2>&1

        if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
            cp -f "/etc/letsencrypt/live/${domain}/fullchain.pem" "${CERT_DIR}/cert.pem"
            cp -f "/etc/letsencrypt/live/${domain}/privkey.pem" "${CERT_DIR}/key.pem"
            chmod 600 "${CERT_DIR}/key.pem"
            chmod 644 "${CERT_DIR}/cert.pem"
            return 0
        fi
    fi

    openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 3650 \
        -key "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=Xray/CN=${domain}" >/dev/null 2>&1
    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"
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

dom = str(cfg.get("_domain", "127.0.0.1")).strip()
pub_key = str(cfg.get("_pub_key", "")).strip()
sni = str(cfg.get("_sni", "")).strip()
short_id = str(cfg.get("_short_id", "")).strip()

inb = (cfg.get("inbounds") or [{}])[0]
proto = str(inb.get("protocol", "desconocido")).strip()
port = inb.get("port", 443)
st = inb.get("settings") or {}
str_st = inb.get("streamSettings") or {}
trans = str(str_st.get("network", "tcp")).strip()
sec = str(str_st.get("security", "none")).strip()

extra = ""
ws_host = dom
if trans == "ws":
    ws_st = str_st.get("wsSettings") or {}
    extra = str(ws_st.get("path", "/trojan-ws")).strip()
    ws_host = str((ws_st.get("headers") or {}).get("Host", dom)).strip()
elif trans == "grpc":
    grpc_st = str_st.get("grpcSettings") or {}
    extra = str(grpc_st.get("serviceName", "grpc")).strip()

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

print("\n\033[1;35m--- USUARIOS Y ENLACES DE CONEXIÓN ---\033[0m\n")

if proto == "shadowsocks":
    method = str(st.get("method", "aes-256-gcm")).strip()
    pass_val = str(st.get("password", "")).strip()
    b64_ss = base64.b64encode(f"{method}:{pass_val}".encode()).decode()
    link = f"ss://{b64_ss}@{dom}:{port}#Xray-Shadowsocks"
    print(f"\033[1;37m[Usuario 1]\033[0m Clave: \033[1;33m{pass_val}\033[0m")
    print(f"\033[0;32mEnlace:\033[0m {link}\n")
else:
    clients = st.get("clients", [])
    for idx, c in enumerate(clients, 1):
        user_id = str(c.get("id") or c.get("password") or "").strip()
        print(f"\033[1;37m[Usuario {idx}]\033[0m ID/Clave: \033[1;33m{user_id}\033[0m")
        
        link = ""
        host_for_link = ws_host if ws_host else dom

        if proto == "vless":
            if sec == "reality":
                link = f"vless://{user_id}@{dom}:{port}?type=tcp&security=reality&encryption=none&pbk={pub_key}&fp=chrome&sni={sni}&sid={short_id}&flow=xtls-rprx-vision#Xray-VLESS-REALITY"
            else:
                params = f"encryption=none&type={trans}"
                if trans == "ws":
                    # CORRECCIÓN: host ANTES que path
                    params += f"&host={urllib.parse.quote(host_for_link)}&path={urllib.parse.quote(extra, safe='/')}"
                elif trans == "grpc":
                    params += f"&serviceName={urllib.parse.quote(extra, safe='')}&mode=gun"
                
                if sec == "tls":
                    params += f"&security=tls&sni={urllib.parse.quote(dom)}"
                else:
                    params += f"&security=none"
                
                link = f"vless://{user_id}@{dom}:{port}?{params}#Xray-VLESS"

        elif proto == "vmess":
            v_json = {
                "v": "2", "ps": f"Xray-VMess-{idx}", "add": dom, "port": str(port),
                "id": user_id, "aid": "0", "net": trans, "type": "none",
                "host": host_for_link if trans == "ws" else "",
                "path": extra if trans == "ws" else "",
                "tls": "tls" if sec == "tls" else "",
                "sni": dom if sec == "tls" else "",
                "serviceName": extra if trans == "grpc" else ""
            }
            b64 = base64.b64encode(json.dumps(v_json).encode()).decode()
            link = f"vmess://{b64}"

        elif proto == "trojan":
            params = f"type={trans}"
            if trans == "ws":
                # CORRECCIÓN CRÍTICA: host ANTES que path para compatibilidad con HTTP Custom
                params += f"&host={urllib.parse.quote(host_for_link)}&path={urllib.parse.quote(extra, safe='/')}"
            elif trans == "grpc":
                params += f"&serviceName={urllib.parse.quote(extra, safe='')}"

            if sec == "tls":
                params += f"&security=tls&sni={urllib.parse.quote(dom)}"
            elif sec == "reality":
                params += f"&security=reality&pbk={pub_key}&sni={sni}&sid={short_id}"

            link = f"trojan://{user_id}@{dom}:{port}?{params}#Xray-Trojan"

        elif proto == "socks":
            link = f"socks5://{dom}:{port}#Xray-SOCKS5"

        if link:
            print(f"\033[0;32mEnlace:\033[0m {link}\n")

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
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción [0-5]: ${NC}"
    read -r popt

    local proto=""
    case "$popt" in
        1) proto="vless" ;;
        2) proto="vmess" ;;
        3) proto="trojan" ;;
        4) proto="shadowsocks" ;;
        5) proto="socks" ;;
        0|*) return ;;
    esac

    header
    echo -e "${PURPLE}${BOLD}📝 DATOS DE CONEXIÓN:${NC}\n"
    local dom="$SERVER_IP" port="9090" extra="" user="" host_header="$SERVER_IP"
    read_val dom "Dominio o IP [${SERVER_IP}]:" "$SERVER_IP"
    host_header="$dom"
    read_val port "Puerto [9090]:" "9090"

    open_port "$port"

    local auto_user
    if command -v python3 &>/dev/null; then
        auto_user=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null | tr -d '\r\n')
    fi
    if [[ -z "$auto_user" ]]; then
        auto_user=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s | sha256sum | head -c 32)
    fi
    
    local prompt_user="Contraseña / ID (UUID) [Auto]:"
    if [[ "$proto" == "trojan" || "$proto" == "shadowsocks" ]]; then
        prompt_user="Contraseña [Auto]:"
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
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción: ${NC}"
    read -r topt

    local trans="tcp" sec="none" sni="" dest="" priv_key="" pub_key="" short_id=""
    case "$topt" in
        1) trans="tcp"; sec="none" ;;
        2) trans="tcp"; sec="tls" ;;
        3) 
            trans="ws"; sec="none"
            read_val extra "Path WS [/trojan-ws]:" "/trojan-ws"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        4) 
            trans="ws"; sec="tls"
            read_val extra "Path WS [/trojan-ws]:" "/trojan-ws"
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
                
                local keypair=$($XRAY_BIN x25519 2>/dev/null)
                priv_key=$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}' | tr -d ' \r\n')
                pub_key=$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}' | tr -d ' \r\n')
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
proto       = str(sys.argv[2]).strip()
port        = int(sys.argv[3])
trans       = str(sys.argv[4]).strip()
sec         = str(sys.argv[5]).strip()
user        = str(sys.argv[6]).strip()
extra       = str(sys.argv[7]).strip()
dom         = str(sys.argv[8]).strip()
sni         = str(sys.argv[9]).strip() if len(sys.argv) > 9 else ""
dest        = str(sys.argv[10]).strip() if len(sys.argv) > 10 else ""
priv_key    = str(sys.argv[11]).strip() if len(sys.argv) > 11 else ""
pub_key     = str(sys.argv[12]).strip() if len(sys.argv) > 12 else ""
short_id    = str(sys.argv[13]).strip() if len(sys.argv) > 13 else ""
host_header = str(sys.argv[14]).strip() if len(sys.argv) > 14 else dom
cert_dir    = str(sys.argv[15]).strip() if len(sys.argv) > 15 else ""

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

val = str(val).strip()
val2 = str(val2).strip()

try:
    with open(cfg_file, "r") as f: cfg = json.load(f)
except: sys.exit(1)

inb = (cfg.get("inbounds") or [{}])[0]
st = inb.get("settings") or {}
str_st = inb.get("streamSettings") or {}

if act == "port":
    inb["port"] = int(val)
elif act == "path":
    if str_st.get("network") == "ws":
        ws_st = str_st.setdefault("wsSettings", {})
        ws_st["path"] = val
        if val2:
            headers = ws_st.setdefault("headers", {})
            headers["Host"] = val2
    elif str_st.get("network") == "grpc":
        grpc_st = str_st.setdefault("grpcSettings", {})
        grpc_st["serviceName"] = val
elif act == "id":
    if "password" in st and "clients" not in st:
        st["password"] = val
    elif "clients" in st and len(st.get("clients", [])) > 0:
        if "id" in st["clients"][0]: st["clients"][0]["id"] = val
        elif "password" in st["clients"][0]: st["clients"][0]["password"] = val
elif act == "add_id":
    if "clients" in st and len(st.get("clients", [])) > 0:
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

if [[ "$1" == "run" ]] || [[ "$1" == "-config" ]] || [[ "$1" == "run-config" ]]; then
    exec /usr/local/xray/xray "$@"
fi

if [[ -f "$LOCK_FILE" ]]; then
    rm -f "$LOCK_FILE"
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT

check_root
install_shortcuts
install_core_if_missing

if [[ ! -f "$CONFIG_FILE" ]]; then
    configure_protocol
fi

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
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción [0-9]: ${NC}"
    read -r op

    case "$op" in
        1) configure_protocol ;;
        2)
            read_val np "Nuevo Puerto:" "9090"
            open_port "$np"
            modify_param "port" "$np"
            echo -e "${GREEN}✔ Puerto actualizado a $np.${NC}"
            pause_screen
            ;;
        3)
            read_val npath "Nuevo Path WS / ServiceName gRPC:" "/trojan-ws"
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
            echo -e "\n${YELLOW}Presiona CTRL + C para detener logs...${NC}\n"
            sleep 1.5
            journalctl -u xray -f
            ;;
        8)
            systemctl restart xray >/dev/null 2>&1
            echo -e "${GREEN}✔ Xray reiniciado exitosamente.${NC}"
            sleep 1.5
            ;;
        9)
            echo -e "\n${YELLOW}⚡ Desinstalando Xray por completo...${NC}"
            systemctl stop xray 2>/dev/null
            systemctl disable xray 2>/dev/null
            rm -rf /usr/local/xray /etc/systemd/system/xray.service /usr/local/bin/xray /usr/local/bin/v2ray /usr/local/bin/menu
            systemctl daemon-reload
            rm -f "$LOCK_FILE"
            echo -e "${GREEN}✔ Desinstalación completa realizada.${NC}"
            exit 0
            ;;
        0) 
            rm -f "$LOCK_FILE"
            exit 0 
            ;;
        *) sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/xray
echo -e "\n${GREEN}${BOLD}🚀 Script corregido e instalado exitosamente.${NC}\n"
/usr/local/bin/xray
