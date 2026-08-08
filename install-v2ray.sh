cat << 'EOF' > /usr/local/bin/v2ray
#!/bin/bash
# =========================================================
#  V2RAY MANAGER - OFFICIAL EDITION (v2fly/v2ray-core)
#  Compatible con Ubuntu 14.04, 16.04, 18.04, 20.04, 22.04, 24.04+
#  DISEÑO OPTIMIZADO Y FIX DE TERMINAL
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

CONFIG_FILE="/usr/local/v2ray/config.json"
V2RAY_BIN="/usr/local/v2ray/v2ray"
SERVICE_FILE="/etc/systemd/system/v2ray.service"
SERVICE_FILE_SYSV="/etc/init.d/v2ray"
CERT_DIR="/usr/local/v2ray"
LOCK_FILE="/tmp/v2ray_manager.lock"

TIMEOUT_DOWNLOAD=30
TIMEOUT_CURL=5
TIMEOUT_APT=60
TIMEOUT_CERTBOT=120

detect_ip() {
    local ip=""
    local timeout=3
    
    ip=$(timeout $timeout curl -4 -fsS https://ifconfig.me 2>/dev/null)
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(timeout $timeout curl -4 -fsS https://icanhazip.com 2>/dev/null)
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(timeout $timeout curl -4 -fsS https://ipinfo.io/ip 2>/dev/null)
    [[ -n "$ip" ]] && echo "$ip" && return
    
    ip=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    [[ -n "$ip" ]] && echo "$ip" && return
    
    echo "127.0.0.1"
}

SERVER_IP=$(detect_ip)

detect_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$VERSION_ID"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        echo "$DISTRIB_RELEASE"
    else
        echo "unknown"
    fi
}

UBUNTU_VERSION=$(detect_ubuntu_version)

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "\n${RED}${BOLD}[✗] Requiere permisos de root para ejecutar este script.${NC}\n"
       exit 1
    fi
}

open_port() {
    local port="$1"
    if [[ -n "$port" ]]; then
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
            iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        fi
        
        if command -v ip6tables >/dev/null 2>&1; then
            ip6tables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
            ip6tables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        fi
        
        if command -v ufw >/dev/null 2>&1; then
            timeout 5 ufw allow "$port"/tcp >/dev/null 2>&1
            timeout 5 ufw allow "$port"/udp >/dev/null 2>&1
        fi
        
        if command -v firewall-cmd >/dev/null 2>&1; then
            timeout 5 firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1
            timeout 5 firewall-cmd --permanent --add-port="$port"/udp >/dev/null 2>&1
            timeout 5 firewall-cmd --reload >/dev/null 2>&1
        fi
        
        if command -v netfilter-persistent >/dev/null 2>&1; then
            timeout 5 netfilter-persistent save >/dev/null 2>&1
        elif command -v iptables-save >/dev/null 2>&1; then
            if [[ -d /etc/iptables ]]; then
                timeout 5 iptables-save > /etc/iptables/rules.v4 2>/dev/null
                timeout 5 ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
            fi
        fi
    fi
}

install_dependencies() {
    echo -e "${CYAN}${BOLD}⚡ Instalando dependencias para Ubuntu ${UBUNTU_VERSION}...${NC}"
    
    timeout $TIMEOUT_APT apt-get update -y >/dev/null 2>&1
    
    local base_pkgs="curl wget unzip openssl"
    
    if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
        base_pkgs="$base_pkgs python python-json"
    else
        base_pkgs="$base_pkgs python3"
    fi
    
    if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
        apt-get install -y software-properties-common >/dev/null 2>&1
        add-apt-repository -y ppa:certbot/certbot >/dev/null 2>&1
        timeout $TIMEOUT_APT apt-get update -y >/dev/null 2>&1
        base_pkgs="$base_pkgs certbot"
    else
        base_pkgs="$base_pkgs certbot"
    fi
    
    if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
        base_pkgs="$base_pkgs iptables-persistent"
    else
        base_pkgs="$base_pkgs iptables-persistent netfilter-persistent"
    fi
    
    timeout $TIMEOUT_APT apt-get install -y $base_pkgs >/dev/null 2>&1
    
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
            timeout $TIMEOUT_APT apt-get install -y python python-json >/dev/null 2>&1
        else
            timeout $TIMEOUT_APT apt-get install -y python3 python3-json >/dev/null 2>&1
        fi
    fi
}

install_core_if_missing() {
    if [[ ! -x "$V2RAY_BIN" || ! -f "$SERVICE_FILE" ]]; then
        install_dependencies
        
        mkdir -p /usr/local/v2ray

        local total_mem
        total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        if [[ -n "$total_mem" && "$total_mem" -lt 1024 ]]; then
            if [[ $(swapon --show 2>/dev/null | wc -l) -eq 0 ]]; then
                fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 2>/dev/null
                chmod 600 /swapfile
                mkswap /swapfile >/dev/null 2>&1
                swapon /swapfile >/dev/null 2>&1
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
            fi
        fi

        local ARCH=$(uname -m)
        local V2ARCH="64"
        if [[ "$ARCH" == *"aarch64"* || "$ARCH" == *"arm64"* ]]; then
            V2ARCH="arm64-v8a"
        elif [[ "$ARCH" == *"arm"* ]]; then
            V2ARCH="arm32-v7a"
        fi

        local LATEST_TAG="v5.14.1"
        local version_json=$(timeout $TIMEOUT_CURL curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest 2>/dev/null)
        if [[ -n "$version_json" ]]; then
            LATEST_TAG=$(echo "$version_json" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            [[ -z "$LATEST_TAG" ]] && LATEST_TAG="v5.14.1"
        fi

        local V2URL="https://github.com/v2fly/v2ray-core/releases/download/${LATEST_TAG}/v2ray-linux-${V2ARCH}.zip"
        
        timeout $TIMEOUT_DOWNLOAD wget -q --timeout=$TIMEOUT_DOWNLOAD "$V2URL" -O /tmp/v2ray.zip
        if [[ $? -ne 0 ]]; then
            V2URL="https://github.com/v2fly/v2ray-core/releases/download/v5.14.1/v2ray-linux-${V2ARCH}.zip"
            timeout $TIMEOUT_DOWNLOAD wget -q --timeout=$TIMEOUT_DOWNLOAD "$V2URL" -O /tmp/v2ray.zip
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}❌ Error: No se pudo descargar V2Ray.${NC}"
                return 1
            fi
        fi
        
        unzip -o /tmp/v2ray.zip -d /usr/local/v2ray/ >/dev/null 2>&1
        chmod +x /usr/local/v2ray/v2ray
        rm -f /tmp/v2ray.zip

        if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
            cat > "$SERVICE_FILE_SYSV" <<'EOFS'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          v2ray
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: V2Ray Core Service
### END INIT INFO

V2RAY_BIN="/usr/local/v2ray/v2ray"
CONFIG_FILE="/usr/local/v2ray/config.json"
PID_FILE="/var/run/v2ray.pid"

case "$1" in
    start)
        $V2RAY_BIN run -config $CONFIG_FILE > /dev/null 2>&1 &
        echo $! > $PID_FILE
        ;;
    stop)
        kill $(cat $PID_FILE) 2>/dev/null
        rm -f $PID_FILE
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [[ -f $PID_FILE ]] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
            echo "V2Ray is running"
        else
            echo "V2Ray is stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
EOFS
            chmod +x "$SERVICE_FILE_SYSV"
            update-rc.d v2ray defaults >/dev/null 2>&1
        else
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
        fi
        sleep 1
    fi
}

manage_service() {
    local action="$1"
    if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
        case "$action" in
            start) /etc/init.d/v2ray start >/dev/null 2>&1 ;;
            stop) /etc/init.d/v2ray stop >/dev/null 2>&1 ;;
            restart) /etc/init.d/v2ray restart >/dev/null 2>&1 ;;
            enable) update-rc.d v2ray defaults >/dev/null 2>&1 ;;
            status) /etc/init.d/v2ray status >/dev/null 2>&1; return $? ;;
        esac
    else
        case "$action" in
            start) systemctl start v2ray >/dev/null 2>&1 ;;
            stop) systemctl stop v2ray >/dev/null 2>&1 ;;
            restart) systemctl restart v2ray >/dev/null 2>&1 ;;
            enable) systemctl enable v2ray >/dev/null 2>&1 ;;
            status) systemctl is-active --quiet v2ray >/dev/null 2>&1; return $? ;;
        esac
    fi
}

service_status() {
    if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
        if [[ -f /var/run/v2ray.pid ]] && kill -0 $(cat /var/run/v2ray.pid) 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        systemctl is-active --quiet v2ray >/dev/null 2>&1
        return $?
    fi
}

get_status() {
    if service_status; then
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
    echo -e "${CYAN}${BOLD}             V2RAY MANAGER PANEL (v2fly-core)             ${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e " ${PURPLE}${BOLD}▸ IP Servidor:${NC}  ${YELLOW}${SERVER_IP}${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Ubuntu:${NC}       ${YELLOW}${UBUNTU_VERSION}${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Arquitectura:${NC} ${YELLOW}$(uname -m)${NC}"
    echo -e " ${PURPLE}${BOLD}▸ Estado V2Ray:${NC} $(get_status)"
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
    [[ -z "$val" ]] && val="$def"
    printf -v "$var" '%s' "$val"
}

get_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

setup_tls_cert() {
    local domain="$1"
    mkdir -p /usr/local/v2ray

    open_port 80
    open_port 443

    if [[ "$domain" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        return 0
    fi

    header
    echo -e "${PURPLE}${BOLD}[ 🔒 CONFIGURACIÓN SSL / TLS PARA DOMINIO ]${NC}\n"
    echo -e " Dominio detectado: ${YELLOW}${domain}${NC}\n"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${GREEN}Let's Encrypt (Oficial)${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${YELLOW}Autofirmado (Rápido / Pruebas)${NC}\n"
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Selecciona una opción [1-2]: ${NC}"
    read -r cert_opt

    if [[ "$cert_opt" != "1" ]]; then
        openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
        openssl req -new -x509 -days 3650 \
            -key "${CERT_DIR}/key.pem" \
            -out "${CERT_DIR}/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain}" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        return 0
    fi

    manage_service stop 2>/dev/null
    systemctl stop nginx 2>/dev/null
    systemctl stop apache2 2>/dev/null

    local cert_output
    cert_output=$(timeout $TIMEOUT_CERTBOT certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email 2>&1)
    local cert_exit=$?

    if [[ $cert_exit -eq 0 ]] && [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        cp -f "/etc/letsencrypt/live/${domain}/fullchain.pem" "${CERT_DIR}/cert.pem"
        cp -f "/etc/letsencrypt/live/${domain}/privkey.pem" "${CERT_DIR}/key.pem"
        chmod 600 "${CERT_DIR}/key.pem"
        chmod 644 "${CERT_DIR}/cert.pem"
        return 0
    fi

    openssl genrsa -out "${CERT_DIR}/key.pem" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 3650 \
        -key "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=V2Ray/CN=${domain}" >/dev/null 2>&1
    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem"
    return 0
}

show_info() {
    header
    echo -e "${PURPLE}${BOLD}[ 📋 DATOS DE CONEXIÓN ACTUAL ]${NC}\n"
    
    local PYTHON_CMD=$(get_python)
    if [[ -z "$PYTHON_CMD" ]]; then
        echo -e "${RED}Error: Python no encontrado.${NC}"
        pause_screen
        return
    fi
    
    $PYTHON_CMD - "$CONFIG_FILE" <<'PY'
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
    print(f"\033[1;37m[Usuario {idx}]\033[0m ID/Clave: \033[1;33m{user_id}\033[0m")
    
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
    local PYTHON_CMD=$(get_python)
    if [[ -n "$PYTHON_CMD" ]]; then
        auto_user=$($PYTHON_CMD -c "import uuid; print(uuid.uuid4())" 2>/dev/null)
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
    echo -e -n "${YELLOW}➜ ${NC}${BOLD}Opción: ${NC}"
    read -r topt

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

    local PYTHON_CMD=$(get_python)
    if [[ -z "$PYTHON_CMD" ]]; then
        echo -e "${RED}Error: Python no encontrado.${NC}"
        pause_screen
        return
    fi

    $PYTHON_CMD - "$CONFIG_FILE" "$proto" "$port" "$trans" "$sec" "$user" "$extra" "$dom" "$host_header" "$CERT_DIR" <<'PY'
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

    manage_service enable
    manage_service restart
    show_info
}

modify_param() {
    local action="$1" val="$2" val2="$3"
    local PYTHON_CMD=$(get_python)
    if [[ -z "$PYTHON_CMD" ]]; then
        echo -e "${RED}Error: Python no encontrado.${NC}"
        return
    fi
    
    $PYTHON_CMD - "$CONFIG_FILE" "$action" "$val" "$val2" <<'PY'
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
    manage_service restart
}

if [[ "$1" == "run" ]] || [[ "$1" == "-config" ]] || [[ "$1" == "run-config" ]]; then
    exec /usr/local/v2ray/v2ray "$@"
fi

if [[ -f "$LOCK_FILE" ]]; then
    echo -e "${YELLOW}⚠️  El script ya está en ejecución.${NC}"
    exit 1
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT

check_root
install_core_if_missing

if [[ ! -f "$CONFIG_FILE" ]]; then
    configure_protocol
fi

while true; do
    header
    echo -e " ${YELLOW}${BOLD}⚠️  PANEL PRINCIPAL V2RAY${NC}"
    echo -e "  ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}🔄 Cambiar Protocolo / Transmisión${NC}"
    echo -e "  ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}🔌 Cambiar Puerto${NC}"
    echo -e "  ${WHITE}${BOLD}[ 3 ]${NC} ${CYAN}🛤️  Cambiar Path WS / Host Header / gRPC${NC}"
    echo -e "  ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}🔑 Cambiar ID / Contraseña Principal${NC}"
    echo -e "  ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}➕ Agregar Nuevo Usuario / ID${NC}"
    echo -e "  ${WHITE}${BOLD}[ 6 ]${NC} ${CYAN}📋 Ver Datos de Conexión / Links${NC}"
    echo -e "  ${WHITE}${BOLD}[ 7 ]${NC} ${YELLOW}🔍 Ver Logs en Vivo${NC}"
    echo -e "  ${WHITE}${BOLD}[ 8 ]${NC} ${CYAN}🔄 Reiniciar Servicio V2Ray${NC}"
    echo -e "  ${WHITE}${BOLD}[ 9 ]${NC} ${RED}🗑️  Desinstalar V2Ray por Completo${NC}"
    echo -e "  ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}🚪 Salir del Menú${NC}"
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
            echo -e "${GREEN}✔ ID/Contraseña $aid agregada.${NC}"
            pause_screen
            ;;
        6) show_info ;;
        7)
            echo -e "\n${YELLOW}Presiona CTRL + C para detener logs...${NC}\n"
            sleep 1.5
            if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
                if [[ -f /var/log/v2ray/error.log ]]; then
                    tail -f /var/log/v2ray/error.log
                else
                    echo -e "${RED}No se encontraron logs.${NC}"
                    pause_screen
                fi
            else
                journalctl -u v2ray -f
            fi
            ;;
        8)
            manage_service restart
            echo -e "${GREEN}✔ V2Ray reiniciado.${NC}"
            sleep 1.5
            ;;
        9)
            manage_service stop
            manage_service disable 2>/dev/null
            if [[ "$UBUNTU_VERSION" == "14.04" ]] || [[ "$UBUNTU_VERSION" == "16.04" ]]; then
                update-rc.d v2ray remove >/dev/null 2>&1
                rm -f "$SERVICE_FILE_SYSV"
            else
                systemctl disable v2ray >/dev/null 2>&1
                rm -f "$SERVICE_FILE"
            fi
            rm -rf /usr/local/v2ray /usr/local/bin/v2ray
            systemctl daemon-reload >/dev/null 2>&1
            rm -f "$LOCK_FILE"
            echo -e "${GREEN}✔ Desinstalación completa hecha.${NC}"
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

chmod +x /usr/local/bin/v2ray

echo -e "\n${CYAN}${BOLD}🚀 Iniciando V2Ray Manager...${NC}\n"
/usr/local/bin/v2ray
