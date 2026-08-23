cat << 'EOF' > /usr/local/bin/xray-menu
#!/bin/bash
# =========================================================
#  XRAY MANAGER - OFFICIAL CORE (VLESS, VMESS, TROJAN, SS)
# =========================================================

export TERM=xterm
export DEBIAN_FRONTEND=noninteractive

# Limpieza de retornos de carro
sed -i 's/\r$//' "$0" 2>/dev/null

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
CERT_DIR="/usr/local/etc/xray"
LOCK_FILE="/tmp/xray_manager.lock"

# Configurar únicamente el alias 'xray' sin tocar 'menu'
install_shortcuts() {
    chmod +x /usr/local/bin/xray-menu 2>/dev/null

    if ! grep -q "alias xray=" /root/.bashrc 2>/dev/null; then
        echo "alias xray='/usr/local/bin/xray-menu'" >> /root/.bashrc
    fi
    echo "alias xray='/usr/local/bin/xray-menu'" > /etc/profile.d/xray_alias.sh 2>/dev/null
    chmod +x /etc/profile.d/xray_alias.sh 2>/dev/null
}

detect_ip() {
    local ip=""
    ip=$(curl -4 -fsS --max-time 3 https://api.ipify.org 2>/dev/null | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '\r\n')
    [[ -n "$ip" ]] && echo "$ip" && return
    
    echo "127.0.0.1"
}

SERVER_IP=$(detect_ip)

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "\n${RED}${BOLD}[✗] Requiere permisos de root (sudo xray).${NC}\n"
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
    open_port 22
    open_port 443

    if [ ! -f "$XRAY_BIN" ]; then
        echo -e "${CYAN}${BOLD}⚡ Instalando dependencias y Xray Core Oficial...${NC}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl qrencode python3 openssl certbot >/dev/null 2>&1 || yum install -y curl qrencode python3 openssl >/dev/null 2>&1
        
        systemctl stop sing-box 2>/dev/null
        systemctl disable sing-box 2>/dev/null

        # Instalador Oficial XTLS
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root >/dev/null 2>&1
        mkdir -p /usr/local/etc/xray
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
    echo -e "${CYAN}${BOLD}                 XRAY MANAGER PANEL OFICIAL                 ${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e " ${PURPLE}${BOLD}▸ IP Servidor:${NC}  ${YELLOW}${SERVER_IP}${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Estado Xray:${NC}  $(get_status)"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────${NC}"
}

pause_screen() {
    echo
    echo -e -n "${YELLOW}Presiona [ENTER] para continuar...${NC}"
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
    mkdir -p /usr/local/etc/xray

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
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}Let's Encrypt (Certificado Oficial)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${YELLOW}Autofirmado (Rápido / Pruebas)${NC}\n"
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Selecciona una opción [1-2]: ${NC}"
    read -r cert_opt

    if [[ "$cert_opt" == "1" ]]; then
        systemctl stop xray 2>/dev/null
        certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email >/dev/null 2>&1

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
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}No hay ninguna configuración activa.${NC}"
        pause_screen
        return
    fi

    header
    echo -e "${PURPLE}${BOLD}[ 📋 DATOS DE CONEXIÓN ACTUAL ]${NC}\n"
    
    local GENERATED_LINK
    GENERATED_LINK=$(python3 - "$CONFIG_FILE" "$SERVER_IP" <<'PY'
import json, sys, base64, urllib.parse

cfg_file = sys.argv[1]
serv_ip  = sys.argv[2]

try:
    with open(cfg_file, "r") as f:
        cfg = json.load(f)
except Exception:
    print("ERROR_READ")
    sys.exit(1)

dom = str(cfg.get("_domain", serv_ip)).strip()
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
    extra = str(ws_st.get("path", "/xray-ws")).strip()
    ws_host = str((ws_st.get("headers") or {}).get("Host", dom)).strip()
elif trans == "xhttp":
    xh_st = str_st.get("xhttpSettings") or {}
    extra = str(xh_st.get("path", "/xhttp-path")).strip()
    ws_host = str((xh_st.get("headers") or {}).get("Host", dom)).strip()

print(f"\033[1;37mProtocolo   :\033[0m \033[0;36m{proto.upper()}\033[0m", file=sys.stderr)
print(f"\033[1;37mIP / Host   :\033[0m \033[1;33m{serv_ip}\033[0m", file=sys.stderr)
print(f"\033[1;37mPuerto      :\033[0m \033[0;32m{port}\033[0m", file=sys.stderr)
print(f"\033[1;37mTransporte  :\033[0m \033[0;36m{trans.upper()}\033[0m", file=sys.stderr)
print(f"\033[1;37mSeguridad   :\033[0m \033[0;36m{sec.upper()}\033[0m", file=sys.stderr)

if trans == "ws":
    print(f"\033[1;37mPath WS     :\033[0m \033[0;36m{extra}\033[0m", file=sys.stderr)
    print(f"\033[1;37mHost WS     :\033[0m \033[1;33m{ws_host}\033[0m", file=sys.stderr)
elif trans == "xhttp":
    print(f"\033[1;37mPath XHTTP  :\033[0m \033[0;36m{extra}\033[0m", file=sys.stderr)
    print(f"\033[1;37mModo XHTTP  :\033[0m \033[0;32mauto\033[0m", file=sys.stderr)

if sec == "reality":
    print(f"\033[1;37mSNI Destino :\033[0m \033[0;36m{sni}\033[0m", file=sys.stderr)
    print(f"\033[1;37mPublic Key  :\033[0m \033[1;32m{pub_key}\033[0m", file=sys.stderr)
    print(f"\033[1;37mShort ID    :\033[0m \033[1;33m{short_id}\033[0m", file=sys.stderr)

print("\n\033[1;35m--- USUARIOS Y ENLACES DE CONEXIÓN ---\033[0m\n", file=sys.stderr)

first_link = ""
if proto == "shadowsocks":
    method = str(st.get("method", "aes-256-gcm")).strip()
    pass_val = str(st.get("password", "")).strip()
    b64_ss = base64.b64encode(f"{method}:{pass_val}".encode()).decode()
    link = f"ss://{b64_ss}@{serv_ip}:{port}#Xray-Shadowsocks"
    first_link = link
    print(f"\033[1;37m[Usuario 1]\033[0m Clave: \033[1;33m{pass_val}\033[0m", file=sys.stderr)
    print(f"\033[0;32mEnlace:\033[0m {link}\n", file=sys.stderr)
else:
    clients = st.get("clients", [])
    for idx, c in enumerate(clients, 1):
        user_id = str(c.get("id") or c.get("password") or "").strip()
        print(f"\033[1;37m[Usuario {idx}]\033[0m ID/Clave: \033[1;33m{user_id}\033[0m", file=sys.stderr)
        
        link = ""
        if proto == "vless":
            if sec == "reality":
                if trans == "xhttp":
                    link = f"vless://{user_id}@{serv_ip}:{port}?security=reality&encryption=none&pbk={pub_key}&headerType=none&fp=chrome&type=xhttp&path={urllib.parse.quote(extra, safe='/')}&mode=auto&sni={sni}&sid={short_id}#VLESS-XHTTP-REALITY"
                else:
                    link = f"vless://{user_id}@{serv_ip}:{port}?security=reality&encryption=none&pbk={pub_key}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni={sni}&sid={short_id}#VLESS-TCP-REALITY"
            else:
                params = f"encryption=none&type={trans}"
                if trans == "ws":
                    params += f"&host={urllib.parse.quote(ws_host)}&path={urllib.parse.quote(extra, safe='/')}"
                elif trans == "xhttp":
                    params += f"&path={urllib.parse.quote(extra, safe='/')}&mode=auto"
                    if ws_host and ws_host != serv_ip:
                        params += f"&host={urllib.parse.quote(ws_host)}"
                
                if sec == "tls":
                    params += f"&security=tls&sni={urllib.parse.quote(dom)}"
                else:
                    params += f"&security=none"
                link = f"vless://{user_id}@{serv_ip}:{port}?{params}#VLESS-{trans.upper()}"

        elif proto == "vmess":
            v_json = {
                "v": "2", "ps": f"VMess-{idx}", "add": serv_ip, "port": str(port),
                "id": user_id, "aid": "0", "net": trans, "type": "none",
                "host": ws_host if trans in ["ws", "xhttp"] else "",
                "path": extra if trans in ["ws", "xhttp"] else "",
                "tls": "tls" if sec == "tls" else "",
                "sni": dom if sec == "tls" else ""
            }
            b64 = base64.b64encode(json.dumps(v_json).encode()).decode()
            link = f"vmess://{b64}"

        elif proto == "trojan":
            params = f"type={trans}"
            if trans in ["ws", "xhttp"]:
                params += f"&host={urllib.parse.quote(ws_host)}&path={urllib.parse.quote(extra, safe='/')}"
            if sec == "tls":
                params += f"&security=tls&sni={urllib.parse.quote(dom)}"
            elif sec == "reality":
                params += f"&security=reality&pbk={pub_key}&sni={sni}&sid={short_id}"
            link = f"trojan://{user_id}@{serv_ip}:{port}?{params}#Trojan-{trans.upper()}"

        elif proto == "socks":
            link = f"socks5://{serv_ip}:{port}#SOCKS5"

        if link:
            if not first_link:
                first_link = link
            print(f"\033[0;32mEnlace:\033[0m {link}\n", file=sys.stderr)

print(first_link)
PY
    )

    if [[ -n "$GENERATED_LINK" && "$GENERATED_LINK" != "ERROR_READ" ]] && command -v qrencode >/dev/null 2>&1; then
        echo -e "${YELLOW}${BOLD}📲 CÓDIGO QR PARA ESCANEAR:${NC}"
        qrencode -t ANSIUTF8 "$GENERATED_LINK"
    fi

    pause_screen
}

configure_protocol() {
    header
    echo -e "${PURPLE}${BOLD}🌐 SELECCIONA EL PROTOCOLO A CONFIGURAR:${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}VLESS${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}VMess${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}Trojan${NC}"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Shadowsocks (aes-256-gcm)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${CYAN}SOCKS5${NC}"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Volver al Panel Principal${NC}\n"
    else
        echo
    fi
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Selecciona una opción: ${NC}"
    read -r popt

    local proto=""
    case "$popt" in
        1) proto="vless" ;;
        2) proto="vmess" ;;
        3) proto="trojan" ;;
        4) proto="shadowsocks" ;;
        5) proto="socks" ;;
        0) return ;;
        *) proto="vless" ;;
    esac

    header
    echo -e "${PURPLE}${BOLD}📝 PARÁMETROS GENERALES (${proto^^}):${NC}\n"
    local dom="$SERVER_IP" port="443" extra="" user="" host_header="$SERVER_IP"
    read_val dom "Dominio o IP de conexión [${SERVER_IP}]:" "$SERVER_IP"
    host_header="$dom"
    read_val port "Puerto de escucha [443]:" "443"

    open_port "$port"

    local auto_user
    auto_user=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 2>/dev/null || echo "12345678-1234-1234-1234-123456789abc")
    read_val user "UUID / Contraseña [${auto_user}]:" "$auto_user"

    header
    echo -e "${PURPLE}${BOLD}🛠️  TRANSPORTE Y SEGURIDAD (${proto^^}):${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} TCP Directo (Sin TLS)"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} TCP + TLS (Requiere Certificado / Dominio)"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} WebSocket (WS Directo - CDN / Cloudflare / Puerto 80)"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} WebSocket + TLS (WS + SSL 443)"
    if [[ "$proto" == "vless" ]]; then
        echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}${BOLD}VLESS + REALITY (Vision - TCP Directo sin Certificado)${NC}"
        echo -e "  ${WHITE}${BOLD}[ 6 ]${NC} ${GREEN}${BOLD}VLESS + XHTTP + REALITY (SplitHTTP Anti-Bloqueo)${NC}"
        echo -e "  ${WHITE}${BOLD}[ 7 ]${NC} ${CYAN}VLESS + XHTTP Directo (Puerto 80 / CDN)${NC}"
    elif [[ "$proto" == "trojan" ]]; then
        echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}${BOLD}Trojan + REALITY${NC}"
    fi
    echo
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Selecciona opción de transporte: ${NC}"
    read -r topt

    local trans="tcp" sec="none" sni="" dest="" priv_key="" pub_key="" short_id=""
    case "$topt" in
        1) trans="tcp"; sec="none" ;;
        2) trans="tcp"; sec="tls" ;;
        3) 
            trans="ws"; sec="none"
            read_val extra "Path WS [/ws-path]:" "/ws-path"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        4) 
            trans="ws"; sec="tls"
            read_val extra "Path WS [/ws-path]:" "/ws-path"
            read_val host_header "Host Header WS [${dom}]:" "$dom"
            ;;
        5) 
            if [[ "$proto" == "vless" || "$proto" == "trojan" ]]; then
                trans="tcp"; sec="reality"
                read_val sni "SNI / Dominio Destino [www.microsoft.com]:" "www.microsoft.com"
                dest="${sni}:443"
                
                local keypair=$($XRAY_BIN x25519 2>/dev/null)
                priv_key=$(echo "$keypair" | grep -Ei "Private" | head -n 1 | awk '{print $NF}' | tr -d '\r\n ')
                pub_key=$(echo "$keypair" | grep -Ei "Public|Password" | head -n 1 | awk '{print $NF}' | tr -d '\r\n ')
                short_id=$(openssl rand -hex 4 2>/dev/null || echo "e875")
            else
                trans="tcp"; sec="none"
            fi
            ;;
        6)
            if [[ "$proto" == "vless" ]]; then
                trans="xhttp"; sec="reality"
                read_val extra "Path XHTTP [/xhttp-path]:" "/xhttp-path"
                read_val sni "SNI / Dominio Destino [www.microsoft.com]:" "www.microsoft.com"
                dest="${sni}:443"
                
                local keypair=$($XRAY_BIN x25519 2>/dev/null)
                priv_key=$(echo "$keypair" | grep -Ei "Private" | head -n 1 | awk '{print $NF}' | tr -d '\r\n ')
                pub_key=$(echo "$keypair" | grep -Ei "Public|Password" | head -n 1 | awk '{print $NF}' | tr -d '\r\n ')
                short_id=$(openssl rand -hex 4 2>/dev/null || echo "e875")
            else
                trans="xhttp"; sec="none"
            fi
            ;;
        7)
            if [[ "$proto" == "vless" ]]; then
                trans="xhttp"; sec="none"
                read_val extra "Path XHTTP [/xhttp-path]:" "/xhttp-path"
                read_val host_header "Host Header XHTTP [${dom}]:" "$dom"
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
        "port": port,
        "protocol": proto,
        "settings": {},
        "streamSettings": {
            "network": trans,
            "security": sec
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}

inb = config["inbounds"][0]
st = inb["settings"]
str_st = inb["streamSettings"]

if proto in ["vless", "vmess"]:
    client_obj = {"id": user}
    if sec == "reality" and trans == "tcp":
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
elif trans == "xhttp":
    str_st["xhttpSettings"] = {"path": extra, "mode": "auto"}
    if host_header and host_header != dom:
        str_st["xhttpSettings"]["headers"] = {"Host": host_header}

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
        echo -e "\n${GREEN}✔ Configuración aplicada y Xray iniciado correctamente.${NC}"
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

inb = (cfg.get("inbounds") or [{}])[0]
st = inb.get("settings") or {}
str_st = inb.get("streamSettings") or {}

if act == "port":
    inb["port"] = int(val)
elif act == "path":
    net = str_st.get("network")
    if net == "ws":
        ws_st = str_st.setdefault("wsSettings", {})
        ws_st["path"] = val
        if val2:
            headers = ws_st.setdefault("headers", {})
            headers["Host"] = val2
    elif net == "xhttp":
        xh_st = str_st.setdefault("xhttpSettings", {})
        xh_st["path"] = val
        if val2:
            headers = xh_st.setdefault("headers", {})
            headers["Host"] = val2
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
        if str_st.get("security") == "reality" and str_st.get("network") == "tcp":
            client_obj["flow"] = "xtls-rprx-vision"
        st["clients"].append(client_obj)

with open(cfg_file, "w") as f: json.dump(cfg, f, indent=2)
PY
    systemctl restart xray >/dev/null 2>&1
}

if [[ -f "$LOCK_FILE" ]]; then
    rm -f "$LOCK_FILE"
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT

check_root
install_shortcuts
install_core_if_missing

# Si no existe archivo de configuración, entra directamente al selector de protocolos
if [[ ! -f "$CONFIG_FILE" ]]; then
    configure_protocol
fi

while true; do
    header
    echo -e " ${YELLOW}${BOLD}⚙️  PANEL PRINCIPAL XRAY${NC}"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}🔄 Cambiar / Configurar Protocolo (VLESS, VMess, etc.)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}🔌 Cambiar Puerto${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}🛤️  Cambiar Path WS / XHTTP / Host Header${NC}"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}🔑 Cambiar ID / Contraseña Principal${NC}"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}➕ Agregar Nuevo Usuario / ID${NC}"
    echo -e "  ${WHITE}${BOLD}[ 6 ]${NC} ${CYAN}📋 Ver Datos de Conexión / Enlaces / QR${NC}"
    echo -e "  ${WHITE}${BOLD}[ 7 ]${NC} ${YELLOW}🔍 Ver Logs en Vivo (Monitoreo)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 8 ]${NC} ${CYAN}🔄 Reiniciar Servicio Xray${NC}"
    echo -e "  ${WHITE}${BOLD}[ 9 ]${NC} ${RED}🗑️  Desinstalar Xray por Completo${NC}"
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}🚪 Salir del Panel${NC}"
    echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────────────${NC}"
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción [0-9]: ${NC}"
    read -r op

    case "$op" in
        1) configure_protocol ;;
        2)
            read_val np "Nuevo Puerto:" "443"
            open_port "$np"
            modify_param "port" "$np"
            echo -e "${GREEN}✔ Puerto actualizado a $np.${NC}"
            pause_screen
            ;;
        3)
            read_val npath "Nuevo Path WS / XHTTP:" "/ws-path"
            read_val nhost "Nuevo Host Header (Enter para omitir):" ""
            modify_param "path" "$npath" "$nhost"
            echo -e "${GREEN}✔ Parámetros actualizados exitosamente.${NC}"
            pause_screen
            ;;
        4)
            nid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)
            read_val nid "Nueva ID/Contraseña:" "$nid"
            modify_param "id" "$nid"
            echo -e "${GREEN}✔ ID actualizada a $nid${NC}"
            pause_screen
            ;;
        5)
            aid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)
            read_val aid "ID a agregar:" "$aid"
            modify_param "add_id" "$aid"
            echo -e "${GREEN}✔ ID $aid agregada correctamente.${NC}"
            pause_screen
            ;;
        6) show_info ;;
        7)
            echo -e "\n${YELLOW}Presiona CTRL + C para detener logs...${NC}\n"
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
            rm -rf /usr/local/etc/xray /usr/local/bin/xray-menu /etc/profile.d/xray_alias.sh
            sed -i '/alias xray=/d' /root/.bashrc 2>/dev/null
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

chmod +x /usr/local/bin/xray-menu
alias xray='/usr/local/bin/xray-menu'
bash /usr/local/bin/xray-menu
