cat << 'EOF' > /usr/local/bin/xray
#!/bin/bash
export TERM=xterm
export DEBIAN_FRONTEND=noninteractive
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

install_shortcuts() {
    chmod +x /usr/local/bin/xray 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/local/bin/v2ray 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/local/bin/menuV2 2>/dev/null
    ln -sf /usr/local/bin/xray /usr/bin/xray 2>/dev/null
}

detect_ip() {
    local ip=""
    ip=$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    ip=$(curl -4 -fsS --max-time 3 https://icanhazip.com 2>/dev/null | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    echo "127.0.0.1"
}

SERVER_IP=$(detect_ip)

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "\n${RED}${BOLD}[✗] Requiere permisos de root.${NC}\n"
       exit 1
    fi
}

open_port() {
    local port="$1"
    if [[ -n "$port" ]]; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        if command -v ufw >/dev/null 2>&1; then
            ufw allow "$port"/tcp >/dev/null 2>&1
            ufw allow "$port"/udp >/dev/null 2>&1
        fi
    fi
}

install_core_if_missing() {
    if [[ ! -x "$XRAY_BIN" || ! -f "$SERVICE_FILE" ]]; then
        echo -e "${CYAN}${BOLD}⚡ Instalando dependencias básicas y Xray Core...${NC}"
        apt-get update -y -qq >/dev/null 2>&1
        apt-get install -y -qq python3 wget unzip curl openssl >/dev/null 2>&1
        mkdir -p /usr/local/xray

        local ARCH=$(uname -m)
        local XURL="https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-64.zip"
        if [[ "$ARCH" == *"aarch64"* || "$ARCH" == *"arm64"* ]]; then
            XURL="https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-arm64-v8a.zip"
        fi

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

print(f"\033[1;37mProtocolo   :\033[0m \033[0;36m{proto.upper()}\033[0m")
print(f"\033[1;37mHost / IP   :\033[0m \033[1;33m{dom}\033[0m")
print(f"\033[1;37mPuerto      :\033[0m \033[0;32m{port}\033[0m")
print(f"\033[1;37mTransporte  :\033[0m \033[0;36m{trans}\033[0m")
print(f"\033[1;37mSeguridad   :\033[0m \033[0;36m{sec}\033[0m")

if trans == "ws":
    print(f"\033[1;37mPath WS     :\033[0m \033[0;36m{extra}\033[0m")
    print(f"\033[1;37mHost WS     :\033[0m \033[1;33m{ws_host}\033[0m")

print("\n\033[1;35m--- USUARIOS Y ENLACES DE CONEXIÓN ---\033[0m\n")

clients = st.get("clients", [])
for idx, c in enumerate(clients, 1):
    user_id = str(c.get("id") or c.get("password") or "").strip()
    print(f"\033[1;37m[Usuario {idx}]\033[0m ID/Clave: \033[1;33m{user_id}\033[0m")
    
    link = ""
    host_for_link = ws_host if ws_host else dom

    if proto == "trojan":
        params = f"type={trans}"
        if trans == "ws":
            params += f"&host={urllib.parse.quote(host_for_link)}&path={urllib.parse.quote(extra, safe='/')}"
        if sec == "tls":
            params += f"&security=tls&sni={urllib.parse.quote(dom)}"
        else:
            params += f"&security=none"

        link = f"trojan://{user_id}@{dom}:{port}?{params}#Xray-Trojan"

    elif proto == "vless":
        params = f"encryption=none&type={trans}"
        if trans == "ws":
            params += f"&host={urllib.parse.quote(host_for_link)}&path={urllib.parse.quote(extra, safe='/')}"
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
            "tls": "tls" if sec == "tls" else ""
        }
        b64 = base64.b64encode(json.dumps(v_json).encode()).decode().replace("\n", "").replace("\r", "")
        link = f"vmess://{b64}"

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
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver al Menú${NC}\n"
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción [0-3]: ${NC}"
    read -r popt

    local proto=""
    case "$popt" in
        1) proto="vless" ;;
        2) proto="vmess" ;;
        3) proto="trojan" ;;
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
    auto_user=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null | tr -d '\r\n')
    read_val user "Contraseña / ID [Auto]:" "$auto_user"

    header
    echo -e "${PURPLE}${BOLD}🛠️  TRANSPORTE Y SEGURIDAD:${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} WebSocket (WS)"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} WebSocket + TLS"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} TCP Directo"
    echo
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción: ${NC}"
    read -r topt

    local trans="ws" sec="none"
    case "$topt" in
        1) 
            trans="ws"; sec="none"
            read_val extra "Path WS [/trojan-ws]:" "/trojan-ws"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        2) 
            trans="ws"; sec="tls"
            read_val extra "Path WS [/trojan-ws]:" "/trojan-ws"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        3) trans="tcp"; sec="none" ;;
        *) trans="ws"; sec="none" ;;
    esac

    python3 - "$CONFIG_FILE" "$proto" "$port" "$trans" "$sec" "$user" "$extra" "$dom" "$host_header" <<'PY'
import json, sys

cfg_file    = sys.argv[1]
proto       = str(sys.argv[2]).strip()
port        = int(sys.argv[3])
trans       = str(sys.argv[4]).strip()
sec         = str(sys.argv[5]).strip()
user        = str(sys.argv[6]).strip()
extra       = str(sys.argv[7]).strip()
dom         = str(sys.argv[8]).strip()
host_header = str(sys.argv[9]).strip() if len(sys.argv) > 9 else dom

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
    if proto == "vless": st["decryption"] = "none"
elif proto == "trojan":
    st["clients"] = [{"password": user}]

if trans == "ws":
    str_st["wsSettings"] = {"path": extra, "headers": {"Host": host_header}}

with open(cfg_file, "w") as f:
    json.dump(config, f, indent=2)
PY

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1
    show_info
}

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
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}📋 Ver Datos de Conexión / Links${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}🔄 Reiniciar Servicio Xray${NC}"
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}🚪 Salir${NC}"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────${NC}"
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción [0-3]: ${NC}"
    read -r op

    case "$op" in
        1) configure_protocol ;;
        2) show_info ;;
        3) systemctl restart xray; echo -e "${GREEN}✔ Reiniciado.${NC}"; pause_screen ;;
        0) exit 0 ;;
        *) sleep 1 ;;
    esac
done
EOF
chmod +x /usr/local/bin/xray
