#!/bin/bash

# =======================================================
# ARIADNY MASTER PANEL - MAIN MENU SCRIPT
# =======================================================

# Definición de Colores Estándar ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

VERSION="v2.1"
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
    printf "\n  %b─ %s ───────────────────────%b\n" "$PURPLE$BOLD" "$title" "$NC"
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
                for m in re.findall(r":(\d+)", f.read()): ports.add(int(m))
        except Exception: pass
try:
    out = subprocess.check_output("ss -ulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line for x in ["udp", "hysteria", "zivpn"]):
            for m in re.findall(r":(\d+)\s", line): ports.add(int(m))
except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
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
        if isinstance(p, list): print(",".join(map(str, sorted([int(x) for x in p]))))
        elif isinstance(p, (int, str)): print(str(p))
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
        for line in f:
            line = line.strip()
            if line.startswith("#") or "reverse_proxy" in line or "handle" in line: continue
            for match in re.finditer(r"(?<![a-zA-Z0-9.-]):([0-9]+)", line):
                p = int(match.group(1))
                if p not in [9090, 8888]: ports.add(p)
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
        for line in f:
            line = line.strip()
            if line.startswith("#") or "reverse_proxy" in line or "handle" in line: continue
            for match in re.finditer(r"[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}:([0-9]+)", line):
                p = int(match.group(1))
                if p not in [9090, 8888]: ports.add(p)
if ports: print(" ".join(str(x) for x in sorted(ports)))
' 2>/dev/null
}

get_nginx_ports() {
    python3 -c '
import subprocess, re, os
ports = set()
conf_dirs = ["/etc/nginx/sites-enabled", "/etc/nginx/conf.d", "/etc/nginx"]
for d in conf_dirs:
    if os.path.exists(d):
        for root, _, files in os.walk(d):
            for file in files:
                if file.endswith(".conf") or d.endswith("sites-enabled"):
                    try:
                        with open(os.path.join(root, file), "r") as f:
                            for line in f:
                                line = line.strip()
                                if line.startswith("#"): continue
                                m = re.search(r"listen\s+(?:\[::\]:)?(\d+)", line)
                                if m:
                                    p = int(m.group(1))
                                    if p not in [9090, 8888]: ports.add(p)
                    except Exception: pass
if not ports:
    try:
        out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
        for line in out.splitlines():
            if "nginx" in line:
                for m in re.findall(r":(\d+)\s", line):
                    p = int(m)
                    if p not in [9090, 8888]: ports.add(p)
    except Exception: pass
if ports: print(" ".join(str(x) for x in sorted(ports)))
' 2>/dev/null
}

get_v2ray_cfg_path() {
    for path in /usr/local/v2ray/config.json /usr/local/etc/v2ray/config.json /etc/v2ray/config.json /etc/v2ray/config.yml; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    echo "/usr/local/v2ray/config.json"
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
            elif isinstance(p, list): ports.update([int(x) for x in p if str(x).isdigit()])
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

get_slowdns_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line for x in ["dns-server", "slowdns", "dnstt", "server-dns"]):
            for m in re.findall(r":(\d+)\s", line): ports.add(int(m))
except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_ssl_ports() {
    python3 -c '
import os, re, subprocess
ports = set()
conf = "/etc/stunnel/stunnel.conf"
if os.path.exists(conf):
    try:
        with open(conf, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("accept"):
                    m = re.search(r"=\s*(?:[0-9.]+:)?([0-9]+)", line)
                    if m: ports.add(int(m.group(1)))
    except Exception: pass
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "stunnel" in line or "stunnel4" in line:
            for m in re.findall(r":(\d+)\s", line): ports.add(int(m))
except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_ports_summary() {
    ACTIVE_ITEMS=()

    # 1. Caddy
    if systemctl is-active --quiet caddy 2>/dev/null; then
        local c_http=$(get_caddy_ports_http 2>/dev/null)
        local c_https=$(get_caddy_ports_https 2>/dev/null)
        local all_caddy=$(echo "$c_http $c_https" | xargs -n1 2>/dev/null | grep -v '^$' | sort -u -n | paste -sd, -)
        if [[ -n "$all_caddy" ]]; then
            ACTIVE_ITEMS+=("🌐 Caddy  : $(truncate_str "$all_caddy")")
        else
            ACTIVE_ITEMS+=("🌐 Caddy  : ACTIVO")
        fi
    fi

    # 1b. Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        local ng_ports=$(get_nginx_ports 2>/dev/null)
        local all_nginx=$(echo "$ng_ports" | tr ' ' ',' 2>/dev/null)
        if [[ -n "$all_nginx" ]]; then
            ACTIVE_ITEMS+=("🔀 Nginx  : $(truncate_str "$all_nginx")")
        else
            ACTIVE_ITEMS+=("🔀 Nginx  : ACTIVO")
        fi
    fi

    # 2. V2Ray
    local v_cfg=$(get_v2ray_cfg_path)
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        local v_out=$(python3 -c '
import json, sys, re, subprocess
ports = set()
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    inbounds = data.get("inbounds", [])
    if isinstance(data, dict) and "inbounds" not in data and "inbound" in data: inbounds = [data["inbound"]]
    for inb in inbounds:
        if "port" in inb and str(inb["port"]).isdigit(): ports.add(int(inb["port"]))
except Exception: pass

if not ports:
    try:
        out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
        for line in out.splitlines():
            if "v2ray" in line:
                for m in re.findall(r":(\d+)\s", line): ports.add(int(m))
    except Exception: pass

if ports: print(",".join(str(x) for x in sorted(ports)))
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
    if systemctl is-active --quiet xray 2>/dev/null || pgrep -x xray >/dev/null; then
        local x_out=$(python3 -c '
import json, os, re, subprocess
ports = set()
for cfg in ["/usr/local/etc/xray/config.json", "/etc/xray/config.json", "/etc/xray/config.yml"]:
    if os.path.isfile(cfg):
        try:
            with open(cfg, "r") as f: data = json.load(f)
            inbounds = data.get("inbounds", [])
            if isinstance(data, dict) and "inbounds" not in data and "inbound" in data: inbounds = [data["inbound"]]
            for inb in inbounds:
                if "port" in inb and str(inb["port"]).isdigit(): ports.add(int(inb["port"]))
        except Exception: pass
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "xray" in line:
            for m in re.findall(r":(\d+)\s", line): ports.add(int(m))
except Exception: pass
if ports: print(",".join(str(x) for x in sorted(ports)))
' 2>/dev/null)
        if [[ -n "$x_out" ]]; then
            ACTIVE_ITEMS+=("🔰 XRay   : $(truncate_str "$x_out")")
        else
            ACTIVE_ITEMS+=("🔰 XRay   : ACTIVO")
        fi
    fi

    # 5. UDP / Hysteria
    if systemctl is-active --quiet udp-custom 2>/dev/null || systemctl is-active --quiet udp-hysteria 2>/dev/null || systemctl is-active --quiet zivpn 2>/dev/null; then
        local u_p=$(get_udp_port)
        [[ -n "$u_p" ]] && ACTIVE_ITEMS+=("⚡ UDP    : $(truncate_str "$u_p")") || ACTIVE_ITEMS+=("⚡ UDP    : ON")
    fi

    # 6. BadVPN UDPGW
    if pgrep -f badvpn-udpgw >/dev/null 2>&1 || systemctl is-active --quiet badvpn 2>/dev/null; then
        local badvpn_ports=$(python3 -c '
import subprocess, re
try:
    out = subprocess.check_output("ps aux | grep badvpn-udpgw | grep -v grep", shell=True).decode()
    ports = [int(p) for p in re.findall(r"--listen-addr\s+127\.0\.0\.1:(\d+)", out)]
    if ports: print(",".join(str(x) for x in sorted(list(set(ports)))))
except Exception: pass
' 2>/dev/null)
        [[ -n "$badvpn_ports" ]] && ACTIVE_ITEMS+=("🚀 BadVPN : $(truncate_str "$badvpn_ports")") || ACTIVE_ITEMS+=("🚀 BadVPN : ON")
    fi

    # 7. Rust
    if pgrep -f "socks-rust" >/dev/null || pgrep -f "rust-proxy" >/dev/null || pgrep -x "rust" >/dev/null || systemctl is-active --quiet rust-proxy 2>/dev/null || systemctl is-active --quiet socks-rust 2>/dev/null; then
        local r_p=$(get_socks_config_port)
        [[ -n "$r_p" ]] && ACTIVE_ITEMS+=("🦀 Rust   : $(truncate_str "$r_p")") || ACTIVE_ITEMS+=("🦀 Rust   : ON")
    fi

    # 8. Python
    if pgrep -f "proxy.py" >/dev/null || systemctl is-active --quiet python-proxy 2>/dev/null || (systemctl is-active --quiet socks-proxy 2>/dev/null && ! pgrep -f "socks-rust" >/dev/null && ! pgrep -f "rust-proxy" >/dev/null && ! pgrep -x "rust" >/dev/null); then
        local p_p=$(get_socks_config_port)
        [[ -n "$p_p" ]] && ACTIVE_ITEMS+=("🐍 Python : $(truncate_str "$p_p")") || ACTIVE_ITEMS+=("🐍 Python : ON")
    fi

    # 9. SlowDNS
    if systemctl is-active --quiet slowdns 2>/dev/null || systemctl is-active --quiet dns-server 2>/dev/null || pgrep -f "dns-server" >/dev/null || pgrep -f "slowdns" >/dev/null || pgrep -f "dnstt" >/dev/null; then
        local dns_p=$(get_slowdns_ports)
        [[ -n "$dns_p" ]] && ACTIVE_ITEMS+=("🐌 SlowDNS: $(truncate_str "$dns_p")") || ACTIVE_ITEMS+=("🐌 SlowDNS: ON")
    fi

    # 10. SSL / Stunnel
    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -f "stunnel" >/dev/null; then
        local ssl_p=$(get_ssl_ports)
        [[ -n "$ssl_p" ]] && ACTIVE_ITEMS+=("🔒 SSL/TLS: $(truncate_str "$ssl_p")") || ACTIVE_ITEMS+=("🔒 SSL/TLS: ON")
    fi

    # 11. SSH Sistema
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
            printf "  %b%-28s %s%b\n" "$CYAN" "$item1" "$item2" "$NC"
            i=$((i+2))
        else
            printf "  %b%s%b\n" "$CYAN" "$item1" "$NC"
            i=$((i+1))
        fi
    done
}

header() {
    clear_screen
    get_sys_info
    get_ports_summary
    printf "          %b🚀 ARIADNY MASTER PANEL %s%b\n" "$BOLD$CYAN" "$VERSION" "$NC"
    printf "  %b%s%b • %b%s%b • %bRAM:%s%b\n" "$CYAN" "$IP_ADDR" "$NC" "$CYAN" "$OS_INFO" "$NC" "$GREEN" "$RAM_INFO" "$NC"

    print_active_ports
}

panel_header() {
    local title="$1"
    local icon="${2:-◆}"

    header
    printf "  %b─ %s %s ───────────────────────────────%b\n" "$PURPLE$BOLD" "$icon" "$title" "$NC"
}

download_to_path() {
    local script_name="$1"
    local destination="$2"

    printf "  %b⬇ Descargando %s...%b\n" "$CYAN" "$script_name" "$NC"

    if curl -fsSL --connect-timeout 15 --max-time 300 "$BASE_URL/$script_name" -o "$destination" 2>/dev/null && [[ -s "$destination" ]]; then
        chmod 700 "$destination"
        info "Archivo instalado en $destination"
        return 0
    fi

    error_msg "No se pudo descargar $script_name o el archivo está vacío."
    rm -f "$destination"
    return 1
}

download_and_execute() {
    local script_name="$1"
    local temporary="/tmp/${script_name##*/}.$$"

    if ! curl -fsSL --connect-timeout 15 --max-time 300 "$BASE_URL/$script_name" -o "$temporary" 2>/dev/null || [[ ! -s "$temporary" ]]; then
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

execute_script() {
    local primary="$1"
    local secondary="$2"
    local tertiary="$3"

    if download_and_execute "$primary"; then
        return 0
    elif [[ -n "$secondary" ]] && download_and_execute "$secondary"; then
        return 0
    elif [[ -n "$tertiary" ]] && download_and_execute "$tertiary"; then
        return 0
    else
        error_msg "No se pudo descargar ningún script ($primary). Verifica el nombre en tu GitHub."
        return 1
    fi
}

is_python_installed() {
    [[ -f /root/proxy.py ]] || [[ -f /usr/local/bin/proxy ]] || systemctl is-active --quiet python-proxy 2>/dev/null || (systemctl is-active --quiet socks-proxy 2>/dev/null && pgrep -f "proxy.py" >/dev/null)
}

caddy_menu() {
    if systemctl is-active --quiet caddy 2>/dev/null; then
        if [[ -x /usr/local/bin/cadmin ]]; then
            /usr/local/bin/cadmin
        elif [[ -x /usr/bin/cadmin ]]; then
            /usr/bin/cadmin
        else
            panel_header "INSTALANDO/EJECUTANDO CADDY PROXY (GITHUB)" "🌐"
            execute_script "install-caddy.sh" "caddy.sh" "Caddy.sh"
            pause_screen
        fi
    else
        panel_header "INSTALANDO CADDY PROXY DESDE GITHUB" "🌐"
        execute_script "install-caddy.sh" "caddy.sh" "Caddy.sh"
        pause_screen
    fi
}

nginx_menu() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        if [[ -x /usr/local/bin/MenuN ]]; then
            /usr/local/bin/MenuN
        elif [[ -x /usr/local/bin/menun ]]; then
            /usr/local/bin/menun
        else
            panel_header "EJECUTANDO NGINX PROXY (GITHUB)" "🔀"
            execute_script "nginx.sh" "Nginx.sh"
            pause_screen
        fi
    else
        panel_header "INSTALANDO NGINX PROXY DESDE GITHUB" "🔀"
        execute_script "nginx.sh" "Nginx.sh"
        pause_screen
    fi
}

multiplexacion_menu() {
    while true; do
        panel_header "MULTIPLEXACIÓN & PROXIES WEB" "🔀"
        printf "  %b[ 1]%b 🌐 %bCaddy Server%b\n" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 2]%b 🔀 %bNginx Proxy%b\n" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 0]%b ⬅️  %bVolver al Menú Principal%b\n" "$RED" "$NC" "$WHITE" "$NC"

        echo -ne "  \033[1;33m> Selecciona una opción [0-2]: \033[0m"
        read sub_m
        sub_m=$(echo "$sub_m" | tr -d '\r\n\t ')

        case "$sub_m" in
            1) caddy_menu ;;
            2) nginx_menu ;;
            0) break ;;
            *) warn "Opción inválida."; sleep 1 ;;
        esac
    done
}

v2ray_menu() {
    panel_header "INSTALANDO/EJECUTANDO V2RAY (GITHUB)" "⚡"
    execute_script "install-v2ray.sh" "v2ray.sh" "V2ray.sh"
    pause_screen
}

xray_menu() {
    if command_exists menuV2; then
        menuV2
    elif systemctl is-active --quiet xray 2>/dev/null; then
        if [[ -x /usr/local/bin/xray ]]; then
            /usr/local/bin/xray
        elif [[ -x /usr/bin/xray ]]; then
            /usr/bin/xray
        else
            panel_header "EJECUTANDO XRAY PANEL" "🔰"
            execute_script "install-xray.sh" "xray.sh" "Xray.sh"
            pause_screen
        fi
    else
        panel_header "INSTALANDO XRAY PANEL DESDE GITHUB" "🔰"
        execute_script "install-xray.sh" "xray.sh" "Xray.sh"
        pause_screen
    fi
}

sshgo_menu() {
    panel_header "SSH-GO PROXY (GITHUB)" "🚀"
    execute_script "install-sshgo.sh" "sshgo.sh" "Sshgo.sh"
    pause_screen
}

badvpn_menu() {
    panel_header "BADVPN UDPGW (GITHUB)" "🚀"
    execute_script "badvpn-udpgw.sh" "badvpn.sh" "Badvpn.sh"
    pause_screen
}

slowdns_menu() {
    panel_header "SLOWDNS PANEL (GITHUB)" "🐌"
    execute_script "slowdns.sh" "Slowdns.sh"
    pause_screen
}

ssl_menu() {
    panel_header "CERTIFICADO SSL / STUNNEL (GITHUB)" "🔒"
    execute_script "ssl.sh" "Ssl.sh"
    pause_screen
}

mas_opciones_menu() {
    while true; do
        panel_header "MÁS OPCIONES & HERRAMIENTAS" "📁"
        printf "  %b[ 1]%b ⚙️  %bNueva Función 1 (Disponible)%b\n" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 2]%b ⚙️  %bNueva Función 2 (Disponible)%b\n" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 0]%b ⬅️  %bVolver al Menú Principal%b\n" "$RED" "$NC" "$WHITE" "$NC"

        echo -ne "  \033[1;33m> Selecciona una opción [0-2]: \033[0m"
        read sub_op
        sub_op=$(echo "$sub_op" | tr -d '\r\n\t ')

        case "$sub_op" in
            1)
                info "Aquí puedes vincular tu nueva función 1."
                pause_screen
                ;;
            2)
                info "Aquí puedes vincular tu nueva función 2."
                pause_screen
                ;;
            0) break ;;
            *) warn "Opción inválida."; sleep 1 ;;
        esac
    done
}

firewall_menu() {
    panel_header "FIREWALL (GITHUB)" "🛡️"
    execute_script "firewall.sh" "Firewall.sh"
    pause_screen
}

udp_menu() {
    panel_header "UDP PANEL (GITHUB)" "⚡"
    execute_script "Udp.sh" "udp.sh" "install-udp.sh"
    pause_screen
}

rust_menu() {
    panel_header "SOCKS PROXY RUST (GITHUB)" "🦀"
    execute_script "rust.sh" "Rust.sh"
    pause_screen
}

python_menu() {
    if is_python_installed; then
        if [[ -x /usr/local/bin/proxy ]]; then
            /usr/local/bin/proxy
        elif [[ -f /root/proxy.py ]]; then
            python3 /root/proxy.py
        else
            panel_header "SOCKS PROXY PYTHON" "🐍"
            execute_script "Python.sh" "python.sh" "proxy.sh"
            pause_screen
        fi
    else
        panel_header "SOCKS PROXY PYTHON" "🐍"
        execute_script "Python.sh" "python.sh" "proxy.sh"
        pause_screen
    fi
}

ssh_panel_menu() {
    local ssh_panel="/usr/local/bin/sshpanel.sh"
    panel_header "SSH PANEL" "👥"
    printf "  %bDescargando panel SSH...%b\n" "$CYAN" "$NC"
    if download_to_path "sshpanel.sh" "$ssh_panel" || download_to_path "Sshpanel.sh" "$ssh_panel"; then
        bash "$ssh_panel"
    fi
    pause_screen
}

configure_ssh() {
    panel_header "CONFIGURAR SSH" "🔐"
    execute_script "ssh.sh" "Ssh.sh"
    pause_screen
}

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
    printf "  Caddy:       "; systemctl is-active --quiet caddy 2>/dev/null && info "ACTIVO" || warn "INACTIVO"
    printf "  Nginx:       "; systemctl is-active --quiet nginx 2>/dev/null && info "ACTIVO" || warn "INACTIVO"
    printf "  V2Ray:       "; systemctl is-active --quiet v2ray 2>/dev/null && info "ACTIVO" || warn "INACTIVO"
    printf "  SSH-Go:      "; (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null) && info "ACTIVO" || warn "INACTIVO"
    printf "  BadVPN:      "; pgrep -f badvpn-udpgw >/dev/null 2>&1 && info "ACTIVO" || warn "INACTIVO"
    
    local dns_p=$(get_slowdns_ports)
    printf "  SlowDNS:     "
    if (systemctl is-active --quiet slowdns 2>/dev/null || systemctl is-active --quiet dns-server 2>/dev/null || pgrep -f "dns-server" >/dev/null || pgrep -f "slowdns" >/dev/null); then
        [[ -n "$dns_p" ]] && info "ACTIVO (Puerto: $dns_p)" || info "ACTIVO"
    else
        warn "INACTIVO"
    fi

    local ssl_p=$(get_ssl_ports)
    printf "  SSL/Stunnel: "
    if (systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -f "stunnel" >/dev/null); then
        [[ -n "$ssl_p" ]] && info "ACTIVO (Puerto: $ssl_p)" || info "ACTIVO"
    else
        warn "INACTIVO"
    fi
    pause_screen
}

main_menu() {
    while true; do
        header

        section_divider "PROTOCOLOS & PROXIES"
        printf "  %b[ 1]%b 🔀 %bMultiplexación%b         %b[ 2]%b ⚡ %bV2Ray / VMess%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 3]%b 🚀 %bSSH-Go Proxy%b         %b[ 4]%b 🔰 %bXRay Panel%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 5]%b ⚡ %bUDP Panel%b            %b[ 6]%b 🦀 %bSOCKS Proxy Rust%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 7]%b 🐍 %bSOCKS Proxy Python%b   %b[ 8]%b 👥 %bSSH Panel / User%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[ 9]%b 🚀 %bBadVPN UDPGW%b         %b[10]%b 🐌 %bSlowDNS Panel%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[11]%b 🔒 %bSSL / TLS Manager%b    %b[12]%b 📁 %bMás Opciones...%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$YELLOW" "$NC" "$YELLOW" "$NC"

        section_divider "GESTIÓN & MANTENIMIENTO"
        printf "  %b[13]%b 🛡️  %bFirewall%b           %b[14]%b 🔐 %bConfigurar SSH%b\n" "$CYAN" "$NC" "$WHITE" "$NC" "$CYAN" "$NC" "$WHITE" "$NC"
        printf "  %b[15]%b 📊 %bMonitoreo Sistema%b   %b[16]%b 📋 %bEstado General%b\n" "$BLUE" "$NC" "$WHITE" "$NC" "$BLUE" "$NC" "$WHITE" "$NC"
        printf "  %b[ 0]%b 🚪 %bSalir del Panel%b\n" "$RED" "$NC" "$WHITE" "$NC"

        echo -ne "  \033[1;33m> Selecciona una opción [0-16]: \033[0m"
        read option
        option=$(echo "$option" | tr -d '\r\n\t ')

        case "$option" in
            1) multiplexacion_menu ;;
            2) v2ray_menu ;;
            3) sshgo_menu ;;
            4) xray_menu ;;
            5) udp_menu ;;
            6) rust_menu ;;
            7) python_menu ;;
            8) ssh_panel_menu ;;
            9) badvpn_menu ;;
            10) slowdns_menu ;;
            11) ssl_menu ;;
            12) mas_opciones_menu ;;
            13) firewall_menu ;;
            14) configure_ssh ;;
            15) monitor_menu ;;
            16) status_menu ;;
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
