#!/bin/bash

# =======================================================
# 1. DESACTIVAR MENSAJES DE RELLENO EN UBUNTU
# =======================================================
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/60-unminimize 2>/dev/null

# =======================================================
# 2. CREAR BANNER COMPACTO Y OPTIMIZADO PARA CELULAR
# =======================================================
cat > /etc/update-motd.d/99-info-vps << 'MOTD_EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2 2>/dev/null | cut -d' ' -f1,2,3)
IP=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //')
RAM_USED=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}')
RAM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')

echo ""
echo -e "${CYAN}${BOLD}┌──────────────────────────────────────┐${NC}"
echo -e "${CYAN}${BOLD}│        INFORMACIÓN DE LA VPS         │${NC}"
echo -e "${CYAN}${BOLD}├──────────────────────────────────────┤${NC}"
echo -e " • ${CYAN}Sistema:${NC}  $OS"
echo -e " • ${CYAN}IP Pub:${NC}   $IP"
echo -e " • ${CYAN}Activo:${NC}   $UPTIME"
echo -e " • ${CYAN}RAM:${NC}      ${RAM_USED} MB / ${RAM_TOTAL} MB"
echo -e " • ${CYAN}Disco:${NC}    ${DISK_USED} / ${DISK_TOTAL}"
echo -e "${CYAN}${BOLD}────────────────────────────────────────${NC}"
echo -e " ${YELLOW}➔ Escribe '${GREEN}menu${YELLOW}' para abrir el panel.${NC}"
echo -e " ${YELLOW}➔ Comandos: '${GREEN}cadmin${YELLOW}' | '${GREEN}xray${YELLOW}'${NC}"
echo -e "${CYAN}${BOLD}└──────────────────────────────────────┘${NC}"
echo ""
MOTD_EOF

chmod +x /etc/update-motd.d/99-info-vps

# =======================================================
# 3. CREAR SCRIPT ADMINISTRATIVO CADMIN (/usr/local/bin/cadmin)
# =======================================================
cat > /usr/local/bin/cadmin << 'CADMIN_EOF'
#!/bin/bash

CONF_FILE="/usr/local/etc/caddy_panel.conf"
CADDY_CONF="/etc/caddy/Caddyfile"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

load_conf(){
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    else
        DOMAIN="arm1.freenethn.org"
        HTTP_PORTS="80, 8080"
        HTTPS_PORTS="443, 8443"
        V2RAY_PORT=9090
        OTHER_PORT=8888
    fi
}

save_conf(){
    mkdir -p /usr/local/etc
    cat > "$CONF_FILE" <<EOF
DOMAIN="$DOMAIN"
HTTP_PORTS="$HTTP_PORTS"
HTTPS_PORTS="$HTTPS_PORTS"
V2RAY_PORT=9090
OTHER_PORT=8888
EOF
}

build_https_list() {
    local dom="$1"
    local ports="$2"
    local res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        if [ -n "$p" ]; then
            [ -n "$res" ] && res="${res}, "
            res="${res}${dom}:${p}"
        fi
    done
    echo "$res"
}

build_http_list() {
    local dom="$1"
    local ports="$2"
    local res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        if [ -n "$p" ]; then
            [ -n "$res" ] && res="${res}, "
            res="${res}http://${dom}:${p}"
        fi
    done
    echo "$res"
}

generate_caddyfile() {
    local dom="$1"
    local http_p="$2"
    local https_p="$3"

    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$dom" "$http_p")

    mkdir -p /etc/caddy
    cat > "$CADDY_CONF" <<EOF
{
    email admin@$dom
    admin off
}

# Configuración HTTPS
$HTTPS_LIST {
    log { output discard }

    @v2ray path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray {
        reverse_proxy 127.0.0.1:9090
    }

    handle {
        reverse_proxy 127.0.0.1:8888
    }
}

# Configuración HTTP
$HTTP_LIST {
    log { output discard }

    @v2ray path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray {
        reverse_proxy 127.0.0.1:9090
    }

    handle {
        reverse_proxy 127.0.0.1:8888
    }
}
EOF
    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null
}

get_status(){
    if systemctl is-active --quiet caddy; then
        echo -e "${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e "${RED}[DETENIDO / STOPPED]${NC}"
    fi
}

header(){
    load_conf
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│       PANEL DE CONTROL CADDY - FREENET HN CLOUD        │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Dominio Actual  :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTP    :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTPS   :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} $(get_status)"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
}

while true; do
    header
    echo -e " ${WHITE}${BOLD}[ 1 ]${NC} ${CYAN}Cambiar Dominio${NC}"
    echo -e " ${WHITE}${BOLD}[ 2 ]${NC} ${CYAN}Reemplazar Todos los Puertos HTTP${NC}"
    echo -e " ${WHITE}${BOLD}[ 3 ]${NC} ${GREEN}Agregar un Puerto HTTP Nuevo${NC}"
    echo -e " ${WHITE}${BOLD}[ 4 ]${NC} ${CYAN}Reemplazar Todos los Puertos HTTPS${NC}"
    echo -e " ${WHITE}${BOLD}[ 5 ]${NC} ${GREEN}Agregar un Puerto HTTPS Nuevo${NC}"
    echo -e " ${WHITE}${BOLD}[ 6 ]${NC} ${CYAN}Ver Estado Detallado de Caddy${NC}"
    echo -e " ${WHITE}${BOLD}[ 7 ]${NC} ${GREEN}Reiniciar Caddy${NC}"
    echo -e " ${WHITE}${BOLD}[ 8 ]${NC} ${RED}Desinstalar Caddy Completamente${NC}"
    echo -e " ${WHITE}${BOLD}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p " Selecciona una opción [0-8]: " op

    case $op in
        1)
            echo -e "\n${YELLOW}${BOLD}=== CAMBIAR DOMINIO ===${NC}"
            echo -e "Dominio actual: ${CYAN}$DOMAIN${NC}"
            read -p "Ingrese el nuevo dominio: " new_dom
            if [ -n "$new_dom" ]; then
                DOMAIN="$new_dom"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}✔ Dominio actualizado a: $DOMAIN${NC}"
            else
                echo -e "\n${RED}✘ Dominio inválido.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        2)
            echo -e "\n${YELLOW}${BOLD}=== REEMPLAZAR PUERTOS HTTP ===${NC}"
            echo -e "Puertos HTTP actuales: ${GREEN}$HTTP_PORTS${NC}"
            read -p "Nuevos puertos HTTP separados por coma (ej: 80, 8080): " new_http
            if [ -n "$new_http" ]; then
                HTTP_PORTS="$new_http"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}✔ Puertos HTTP reemplazados por: $HTTP_PORTS${NC}"
            else
                echo -e "\n${RED}✘ Entrada inválida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        3)
            echo -e "\n${YELLOW}${BOLD}=== AGREGAR PUERTO HTTP NUEVO ===${NC}"
            echo -e "Puertos HTTP actuales: ${GREEN}$HTTP_PORTS${NC}"
            read -p "Ingrese el puerto HTTP a agregar (ej: 8888): " add_http
            add_http=$(echo "$add_http" | tr -d ' ')
            if [ -n "$add_http" ]; then
                HTTP_PORTS="${HTTP_PORTS}, ${add_http}"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}✔ Puerto HTTP $add_http agregado. Nuevos puertos: $HTTP_PORTS${NC}"
            else
                echo -e "\n${RED}✘ Entrada inválida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        4)
            echo -e "\n${YELLOW}${BOLD}=== REEMPLAZAR PUERTOS HTTPS ===${NC}"
            echo -e "Puertos HTTPS actuales: ${GREEN}$HTTPS_PORTS${NC}"
            read -p "Nuevos puertos HTTPS separados por coma (ej: 443, 8443): " new_https
            if [ -n "$new_https" ]; then
                HTTPS_PORTS="$new_https"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}✔ Puertos HTTPS reemplazados por: $HTTPS_PORTS${NC}"
            else
                echo -e "\n${RED}✘ Entrada inválida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        5)
            echo -e "\n${YELLOW}${BOLD}=== AGREGAR PUERTO HTTPS NUEVO ===${NC}"
            echo -e "Puertos HTTPS actuales: ${GREEN}$HTTPS_PORTS${NC}"
            read -p "Ingrese el puerto HTTPS a agregar (ej: 2083): " add_https
            add_https=$(echo "$add_https" | tr -d ' ')
            if [ -n "$add_https" ]; then
                HTTPS_PORTS="${HTTPS_PORTS}, ${add_https}"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}✔ Puerto HTTPS $add_https agregado. Nuevos puertos: $HTTPS_PORTS${NC}"
            else
                echo -e "\n${RED}✘ Entrada inválida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        6)
            echo -e "\n${YELLOW}${BOLD}=== ESTADO DETALLADO DEL SERVICIO ===${NC}"
            systemctl status caddy --no-pager -n 12
            read -p "Presione ENTER para continuar..."
            ;;
        7)
            echo -e "\n${YELLOW}Reiniciando Caddy...${NC}"
            systemctl restart caddy
            echo -e "${GREEN}✔ Caddy reiniciado correctamente.${NC}"
            sleep 2
            ;;
        8)
            echo -e "\n${RED}${BOLD}=== DESINSTALAR CADDY COMPLETAMENTE ===${NC}"
            read -p "¿Está SEGURO de eliminar Caddy y el Panel? (s/n): " confirm
            if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                echo -e "${YELLOW}Eliminando Caddy y archivos de configuración...${NC}"
                systemctl stop caddy 2>/dev/null
                systemctl disable caddy 2>/dev/null
                apt purge -y caddy 2>/dev/null || yum remove -y caddy 2>/dev/null
                rm -rf /etc/caddy /usr/local/bin/cadmin "$CONF_FILE" /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg
                echo -e "\n${GREEN}✔ Desinstalación completa realizada con éxito.${NC}"
                exit 0
            else
                echo -e "\n${GREEN}Desinstalación cancelada.${NC}"
                sleep 1
            fi
            ;;
        0)
            echo -e "\n${GREEN}Saliendo del panel Caddy...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Opción inválida.${NC}"
            sleep 1
            ;;
    esac
done
CADMIN_EOF

chmod +x /usr/local/bin/cadmin
ln -sf /usr/local/bin/cadmin /usr/bin/cadmin 2>/dev/null

# =======================================================
# 4. INSTALAR EL PANEL PRINCIPAL (/usr/local/bin/menu)
# =======================================================
cat > /usr/local/bin/menu << 'MENU_EOF'
#!/bin/bash

set -o pipefail

# Definición de Colores Estándar ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'
RESET='\033[0m'

VERSION="PROFESSIONAL EDITION v2.1"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

clear_screen() {
    clear 2>/dev/null || printf '\033c'
}

pause_screen() {
    printf "\n  %bPresiona ENTER para continuar...%b" "$WHITE" "$NC"
    read -r
    clear_screen
}

info() {
    printf "  %b✔%b %s\n" "$GREEN" "$NC" "$1"
}

warn() {
    printf "  %b⚠%b %s\n" "$YELLOW" "$NC" "$1"
}

error_msg() {
    printf "  %b✖%b %s\n" "$RED" "$NC" "$1" >&2
}

section_divider() {
    local title="$1"
    printf "  %b─ %s ───────────────────────%b\n" "$PURPLE$BOLD" "$title" "$NC"
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error_msg "Ejecuta el panel como root: sudo bash $0"
        exit 1
    fi
}

install_dependencies() {
    if ! command_exists curl || ! command_exists python3; then
        apt-get update -qq
        apt-get install -y curl python3 -qq 2>/dev/null || yum install -y curl python3 -qq 2>/dev/null
    fi
}

setup_menu_shortcut() {
    local current_script
    current_script="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

    if [[ -f "$current_script" ]]; then
        if [[ "$current_script" != "/usr/local/bin/menu" ]]; then
            cp "$current_script" /usr/local/bin/menu 2>/dev/null
            chmod +x /usr/local/bin/menu 2>/dev/null
        fi
        if [[ "$current_script" != "/usr/bin/menu" ]]; then
            cp "$current_script" /usr/bin/menu 2>/dev/null
            chmod +x /usr/bin/menu 2>/dev/null
        fi
    fi
}

get_sys_info() {
    IP_ADDR=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$IP_ADDR" ]] && IP_ADDR="127.0.0.1"
    
    RAM_INFO=$(free -h 2>/dev/null | awk 'NR==2 {print $3 "/" $2}')
    [[ -z "$RAM_INFO" ]] && RAM_INFO="N/A"
    
    OS_INFO=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null | cut -d' ' -f1,2)
    [[ -z "$OS_INFO" ]] && OS_INFO="Linux"
}

truncate_str() {
    local str="$1"
    local max_len=11
    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$max_len}..."
    else
        echo "$str"
    fi
}

get_udp_port() {
    python3 -c '
import json, glob, os, re, subprocess
ports = set()
for cfg in ["/etc/udp/config.json", "/etc/udp-custom/config.json", "/etc/hysteria/config.json", "/etc/zivpn/config.json"]:
    if os.path.isfile(cfg):
        try:
            with open(cfg, "r") as f:
                for m in re.findall(r":(\d+)", f.read()): ports.add(m)
        except Exception: pass
try:
    out = subprocess.check_output("ss -ulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line for x in ["udp", "hysteria", "zivpn"]):
            for m in re.findall(r":(\d+)\s", line): ports.add(m)
except Exception: pass
if ports: print(",".join(sorted(ports)))
' 2>/dev/null
}

get_socks_config_port() {
    python3 -c '
import json, os
cfg = "/root/socks_config.json"
if os.path.isfile(cfg):
    try:
        with open(cfg, "r") as f: data = json.load(f)
        p = data.get("ports") or data.get("port")
        if isinstance(p, list): print(",".join(map(str, p)))
        elif isinstance(p, int): print(str(p))
    except Exception: pass
' 2>/dev/null
}

get_caddy_ports_http() {
    python3 -c '
import os, re
caddyfile = "/etc/caddy/Caddyfile"
ports = set()
if os.path.exists(caddyfile):
    with open(caddyfile, "r") as f:
        for match in re.finditer(r"(?<![a-zA-Z0-9.-]):([0-9]+)", f.read()):
            ports.add(int(match.group(1)))
if ports: print(" ".join(str(x) for x in sorted(ports)))
' 2>/dev/null
}

get_caddy_ports_https() {
    python3 -c '
import os, re
caddyfile = "/etc/caddy/Caddyfile"
ports = set()
if os.path.exists(caddyfile):
    with open(caddyfile, "r") as f:
        for match in re.finditer(r"[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}:([0-9]+)", f.read()):
            ports.add(int(match.group(1)))
if ports: print(" ".join(str(x) for x in sorted(ports)))
' 2>/dev/null
}

get_v2ray_cfg_path() {
    for path in /usr/local/etc/v2ray/config.json /etc/v2ray/config.json /etc/v2ray/config.yml; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    echo "/usr/local/etc/v2ray/config.json"
}

get_sshgo_ports() {
    python3 -c '
import json, glob, os, re, subprocess
ports = set()
for cfg in ["/opt/vpn-proxy/config.json", "/etc/vpn-proxy/config.json", "/etc/ssh-go/config.json"]:
    if os.path.isfile(cfg):
        try:
            with open(cfg, "r") as f: data = json.load(f)
            p = data.get("port") or data.get("ports")
            if isinstance(p, int): ports.add(p)
            elif isinstance(p, list): ports.update([x for x in p if isinstance(x, int)])
        except Exception: pass
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "vpn-proxy" in line or "ssh-go" in line:
            for m in re.findall(r":(\d+)\s", line): ports.add(int(m))
except Exception: pass
if ports: print(" ".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_ports_summary() {
    ACTIVE_ITEMS=()

    # 1. Caddy
    if systemctl is-active --quiet caddy 2>/dev/null || command_exists caddy; then
        local c_http=$(get_caddy_ports_http 2>/dev/null)
        local c_https=$(get_caddy_ports_https 2>/dev/null)
        local all_caddy=$(echo "$c_http $c_https" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$all_caddy" ]]; then
            ACTIVE_ITEMS+=("🌐 Caddy  : $(truncate_str "$all_caddy")")
        else
            ACTIVE_ITEMS+=("🌐 Caddy  : ACTIVO")
        fi
    fi

    # 2. V2Ray
    local v_cfg=$(get_v2ray_cfg_path)
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        local v_out=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    inbounds = data.get("inbounds", [])
    if isinstance(data, dict) and "inbounds" not in data and "inbound" in data: inbounds = [data["inbound"]]
    ports = sorted(list(set(str(inb["port"]) for inb in inbounds if "port" in inb)))
    print(",".join(ports))
except Exception: pass
' "$v_cfg" 2>/dev/null)
        if [[ -n "$v_out" ]]; then
            ACTIVE_ITEMS+=("⚡ V2Ray  : $(truncate_str "$v_out")")
        else
            ACTIVE_ITEMS+=("⚡ V2Ray  : ACTIVO")
        fi
    fi

    # 3. SSH-Go
    SSHGO_PORTS_RAW=$(get_sshgo_ports 2>/dev/null)
    if [[ -n "$SSHGO_PORTS_RAW" ]] && (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null); then
        ACTIVE_ITEMS+=("🚀 SSH-Go : $(truncate_str "$(echo "$SSHGO_PORTS_RAW" | tr ' ' ',')")")
    fi

    # 4. XRay
    if systemctl is-active --quiet xray 2>/dev/null; then
        local x_cfg=""
        [[ -f /usr/local/etc/xray/config.json ]] && x_cfg="/usr/local/etc/xray/config.json"
        [[ -f /etc/xray/config.json ]] && x_cfg="/etc/xray/config.json"
        if [[ -n "$x_cfg" ]]; then
            local x_out=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    inbounds = data.get("inbounds", [])
    ports = sorted(list(set(str(inb["port"]) for inb in inbounds if "port" in inb)))
    print(",".join(ports))
except Exception: pass
' "$x_cfg" 2>/dev/null)
            if [[ -n "$x_out" ]]; then
                ACTIVE_ITEMS+=("🔰 XRay   : $(truncate_str "$x_out")")
            else
                ACTIVE_ITEMS+=("🔰 XRay   : ACTIVO")
            fi
        else
            ACTIVE_ITEMS+=("🔰 XRay   : ACTIVO")
        fi
    fi

    # 5. UDP / Hysteria
    if systemctl is-active --quiet udp-custom 2>/dev/null || systemctl is-active --quiet udp-hysteria 2>/dev/null || systemctl is-active --quiet zivpn 2>/dev/null; then
        local u_p=$(get_udp_port)
        [[ -n "$u_p" ]] && ACTIVE_ITEMS+=("⚡ UDP    : $(truncate_str "$u_p")") || ACTIVE_ITEMS+=("⚡ UDP    : ON")
    fi

    # 6. Rust
    if pgrep -f "socks-rust" >/dev/null || pgrep -f "rust-proxy" >/dev/null || pgrep -x "rust" >/dev/null || systemctl is-active --quiet rust-proxy 2>/dev/null || systemctl is-active --quiet socks-rust 2>/dev/null; then
        local r_p=$(get_socks_config_port)
        [[ -n "$r_p" ]] && ACTIVE_ITEMS+=("🦀 Rust   : $(truncate_str "$r_p")") || ACTIVE_ITEMS+=("🦀 Rust   : ON")
    fi

    # 7. Python
    if pgrep -f "proxy.py" >/dev/null || systemctl is-active --quiet python-proxy 2>/dev/null || (systemctl is-active --quiet socks-proxy 2>/dev/null && ! pgrep -f "socks-rust" >/dev/null && ! pgrep -f "rust-proxy" >/dev/null && ! pgrep -x "rust" >/dev/null); then
        local p_p=$(get_socks_config_port)
        [[ -n "$p_p" ]] && ACTIVE_ITEMS+=("🐍 Python : $(truncate_str "$p_p")") || ACTIVE_ITEMS+=("🐍 Python : ON")
    fi

    # 8. SSH Sistema
    SSH_PORT_DISPLAY="22"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_p=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
        [[ -n "$ssh_p" ]] && SSH_PORT_DISPLAY="$ssh_p"
    fi
    ACTIVE_ITEMS+=("🔐 SSH    : $SSH_PORT_DISPLAY")
}

print_active_ports() {
    local count=${#ACTIVE_ITEMS[@]}
    if [[ $count -eq 0 ]]; then
        return
    fi

    section_divider "PUERTOS ACTIVOS"
    local i=0
    while [[ $i -lt $count ]]; do
        local item1="${ACTIVE_ITEMS[$i]}"
        local item2="${ACTIVE_ITEMS[$((i+1))]}"
        if [[ -n "$item2" ]]; then
            printf "  %b%-24s %s%b\n" "$CYAN" "$item1" "$item2" "$NC"
            i=$((i+2))
        else
            printf "  %b%s%b\n" "$CYAN" "$item1" "$NC"
            i=$((i+1))
        fi
    done
    printf "\n"
}

header() {
    clear_screen
    get_sys_info
    get_ports_summary
    printf "  %b🚀 ARIADNY MASTER PANEL %s%b\n" "$BOLD$WHITE" "$VERSION" "$NC"
    printf "  %b%s%b • %b%s%b • %bRAM:%s%b\n\n" "$CYAN" "$IP_ADDR" "$NC" "$CYAN" "$OS_INFO" "$NC" "$GREEN" "$RAM_INFO" "$NC"

    print_active_ports
}

panel_header() {
    local title="$1"
    local icon="${2:-◆}"

    header
    printf "  %b─ %s %s ───────────────────────────────%b\n\n" "$PURPLE$BOLD" "$icon" "$title" "$NC"
}

download_to_path() {
    local script_name="$1"
    local destination="$2"

    printf "\n  %b⬇ Descargando %s...%b\n" "$CYAN" "$script_name" "$NC"

    if curl -fsSL --connect-timeout 15 --max-time 300 \
        "$BASE_URL/$script_name" -o "$destination"; then
        chmod 700 "$destination"
        info "Archivo instalado en $destination"
        return 0
    fi

    error_msg "No se pudo descargar $script_name."
    rm -f "$destination"
    return 1
}

download_and_execute() {
    local script_name="$1"
    local temporary="/tmp/${script_name##*/}.$$"

    printf "\n  %b⬇ Descargando %s...%b\n" "$CYAN" "$script_name" "$NC"

    if ! curl -fsSL --connect-timeout 15 --max-time 300 \
        "$BASE_URL/$script_name" -o "$temporary"; then
        error_msg "No se pudo descargar $script_name."
        rm -f "$temporary"
        return 1
    fi

    chmod 700 "$temporary"

    printf "  %b🚀 Ejecutando %s...%b\n\n" "$GREEN" "$script_name" "$NC"

    bash "$temporary"
    local result=$?

    rm -f "$temporary"

    if ((result == 0)); then
        info "$script_name finalizó correctamente."
    else
        error_msg "$script_name terminó con errores."
    fi

    return "$result"
}

is_python_installed() {
    [[ -f /root/proxy.py ]] || systemctl is-active --quiet python-proxy 2>/dev/null || (systemctl is-active --quiet socks-proxy 2>/dev/null && pgrep -f "proxy.py" >/dev/null)
}

# =======================================================
# LÓGICA INTEGLIGENTE DE EJECUCIÓN O PANEL PRO
# =======================================================

caddy_menu() {
    if command_exists caddy || [[ -f /usr/local/bin/cadmin || -f /etc/caddy/Caddyfile ]]; then
        if [[ -x /usr/local/bin/cadmin ]]; then
            /usr/local/bin/cadmin
        elif [[ -x /usr/bin/cadmin ]]; then
            /usr/bin/cadmin
        else
            panel_header "INSTALANDO/EJECUTANDO CADDY PROXY (GITHUB)" "🌐"
            download_and_execute "caddy.sh" || download_and_execute "install-caddy.sh"
        fi
    else
        panel_header "INSTALANDO CADDY PROXY DESDE GITHUB" "🌐"
        download_and_execute "caddy.sh" || download_and_execute "install-caddy.sh"
    fi
}

v2ray_menu() {
    panel_header "INSTALANDO/EJECUTANDO V2RAY (GITHUB)" "⚡"
    download_and_execute "v2ray.sh" || download_and_execute "install-v2ray.sh"
    pause_screen
}

xray_menu() {
    if command_exists menuV2; then
        menuV2
    elif command_exists xray || [[ -x /usr/local/bin/xray || -x /usr/bin/xray ]]; then
        if [[ -x /usr/local/bin/xray ]]; then
            /usr/local/bin/xray
        elif [[ -x /usr/bin/xray ]]; then
            /usr/bin/xray
        else
            panel_header "EJECUTANDO XRAY PANEL" "🔰"
            download_and_execute "xray.sh" || download_and_execute "install-xray.sh"
        fi
    else
        panel_header "INSTALANDO XRAY PANEL DESDE GITHUB" "🔰"
        download_and_execute "xray.sh" || download_and_execute "install-xray.sh"
    fi
}

sshgo_menu() {
    panel_header "SSH-GO PROXY (GITHUB)" "🚀"
    download_and_execute "install-sshgo.sh" || download_and_execute "sshgo.sh"
    pause_screen
}

firewall_menu() {
    local firewall="/usr/local/bin/firewall.sh"
    panel_header "FIREWALL" "🛡️"
    if [[ ! -x "$firewall" ]]; then
        warn "Firewall no instalado."
        download_to_path "firewall.sh" "$firewall" && "$firewall"
    else info "Firewall ya instalado."; "$firewall"; fi
    pause_screen
}

udp_menu() {
    panel_header "UDP PANEL (GITHUB)" "⚡"
    download_and_execute "Udp.sh"
    pause_screen
}

rust_menu() {
    panel_header "SOCKS PROXY RUST (GITHUB)" "🦀"
    download_and_execute "rust.sh"
    pause_screen
}

python_menu() {
    if is_python_installed; then
        chmod +x /usr/local/bin/proxy 2>/dev/null
        /usr/local/bin/proxy
    else
        panel_header "SOCKS PROXY PYTHON" "🐍"
        download_and_execute "Python.sh"
    fi
}

ssh_panel_menu() {
    local ssh_panel="/usr/local/bin/sshpanel.sh"
    panel_header "SSH PANEL" "👥"
    printf "  %bDescargando panel SSH...%b\n" "$CYAN" "$NC"
    download_to_path "sshpanel.sh" "$ssh_panel" && bash "$ssh_panel" || error_msg "No se pudo descargar"
    pause_screen
}

configure_ssh() { panel_header "CONFIGURAR SSH" "🔐"; download_and_execute "ssh.sh"; pause_screen; }

monitor_menu() {
    panel_header "MONITOREO DEL SISTEMA" "📊"
    printf "  Sistema: %s\n" "$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)"
    printf "  Memoria: %s\n" "$(free -h | awk 'NR==2 {print $3 " / " $2}')"
    printf "  Disco: %s\n" "$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    printf "  Tiempo activo: %s\n" "$(uptime -p 2>/dev/null || echo N/A)"
    pause_screen
}

status_menu() {
    panel_header "ESTADO GENERAL" "📋"
    printf "  Caddy:   "; (systemctl is-active --quiet caddy 2>/dev/null || command_exists caddy) && info "ACTIVO" || warn "INACTIVO"
    printf "  V2Ray:   "; systemctl is-active --quiet v2ray 2>/dev/null && info "ACTIVO" || warn "INACTIVO"
    printf "  SSH-Go:  "; (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null) && info "ACTIVO" || warn "INACTIVO"
    pause_screen
}

main_menu() {
    while true; do
        header

        section_divider "PROTOCOLOS & PROXIES"
        printf "  %b[ 1]%b 🌐 Caddy Server       %b[ 2]%b ⚡ V2Ray / VMess\n" "$CYAN" "$NC" "$CYAN" "$NC"
        printf "  %b[ 3]%b 🚀 SSH-Go Proxy       %b[ 4]%b 🔰 XRay Panel\n" "$CYAN" "$NC" "$CYAN" "$NC"
        printf "  %b[ 5]%b ⚡ UDP Panel          %b[ 6]%b 🦀 SOCKS Proxy Rust\n" "$CYAN" "$NC" "$CYAN" "$NC"
        printf "  %b[ 7]%b 🐍 SOCKS Proxy Python %b[ 8]%b 👥 SSH Panel / User\n\n" "$CYAN" "$NC" "$CYAN" "$NC"

        section_divider "GESTIÓN & MANTENIMIENTO"
        printf "  %b[ 9]%b 🛡️  Firewall           %b[10]%b 🔐 Configurar SSH\n" "$CYAN" "$NC" "$CYAN" "$NC"
        printf "  %b[11]%b 📊 Monitoreo Sistema   %b[12]%b 📋 Estado General\n" "$BLUE" "$NC" "$BLUE" "$NC"
        printf "  %b[ 0]%b 🚪 Salir del Panel\n" "$RED" "$NC"

        read -r -p "  ❯ Selecciona una opción [0-12]: " option

        case "$option" in
            1) caddy_menu ;;
            2) v2ray_menu ;;
            3) sshgo_menu ;;
            4) xray_menu ;;
            5) udp_menu ;;
            6) rust_menu ;;
            7) python_menu ;;
            8) ssh_panel_menu ;;
            9) firewall_menu ;;
            10) configure_ssh ;;
            11) monitor_menu ;;
            12) status_menu ;;
            0)
                clear_screen
                printf "\n  %b¡Gracias por usar el panel VPN!%b\n\n" "$GREEN" "$NC"
                exit 0
                ;;
            *)
                warn "Selecciona una opción válida."
                sleep 1
                ;;
        esac
    done
}

require_root
install_dependencies
setup_menu_shortcut
main_menu
MENU_EOF

# =======================================================
# 5. REGISTRO Y FIXES DE ALIAS DE COMANDOS GLOBALMENTE
# =======================================================
sed -i 's/\r$//' /usr/local/bin/menu /usr/local/bin/cadmin
chmod +x /usr/local/bin/menu /usr/local/bin/cadmin
ln -sf /usr/local/bin/menu /usr/bin/menu 2>/dev/null
ln -sf /usr/local/bin/cadmin /usr/bin/cadmin 2>/dev/null

# Configuración de accesos directos
grep -q "alias menu=" /root/.bashrc 2>/dev/null || echo "alias menu='/usr/local/bin/menu'" >> /root/.bashrc
grep -q "alias cadmin=" /root/.bashrc 2>/dev/null || echo "alias cadmin='/usr/local/bin/cadmin'" >> /root/.bashrc

grep -q "alias menu=" /etc/bash.bashrc 2>/dev/null || echo "alias menu='/usr/local/bin/menu'" >> /etc/bash.bashrc
grep -q "alias cadmin=" /etc/bash.bashrc 2>/dev/null || echo "alias cadmin='/usr/local/bin/cadmin'" >> /etc/bash.bashrc

grep -q "alias menu=" /etc/profile 2>/dev/null || echo "alias menu='/usr/local/bin/menu'" >> /etc/profile
grep -q "alias cadmin=" /etc/profile 2>/dev/null || echo "alias cadmin='/usr/local/bin/cadmin'" >> /etc/profile

hash -r
source /root/.bashrc 2>/dev/null

# Abrir el menú inmediatamente
/usr/local/bin/menu
