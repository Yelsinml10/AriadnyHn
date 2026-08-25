#!/bin/bash

# =======================================================
# ARIADNY MASTER PANEL - MAIN MENU SCRIPT (COLORFUL UI)
# =======================================================

cleanup() {
    printf "\033[0m"
}
trap cleanup EXIT INT TERM

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

VERSION="v2.5"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Limpieza de pantalla estándar sin romper el historial
clear_screen() {
    clear
}

pause_screen() {
    printf "\n  %bPresiona %bENTER%b para continuar...%b" "$GRAY" "$WHITE" "$GRAY" "$NC"
    read -r
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

# Configuración permanente del comando menu (Auto-reparable)
setup_menu_shortcut() {
    local current_script
    current_script="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

    # Si se ejecuta desde un archivo físico existente
    if [[ -f "$current_script" && "$current_script" != *"/dev/fd/"* && "$current_script" != *"bash"* ]]; then
        cp -f "$current_script" /usr/local/bin/menu 2>/dev/null
        cp -f "$current_script" /usr/bin/menu 2>/dev/null
    else
        # Si se ejecutó por pipe/curl directo, descargar el archivo base
        curl -fsSL "$BASE_URL/menu.sh" -o /usr/local/bin/menu 2>/dev/null || \
        curl -fsSL "$BASE_URL/Menu.sh" -o /usr/local/bin/menu 2>/dev/null
        cp -f /usr/local/bin/menu /usr/bin/menu 2>/dev/null
    fi

    chmod 755 /usr/local/bin/menu 2>/dev/null
    chmod 755 /usr/bin/menu 2>/dev/null

    # Asegurar persistencia en .bashrc y bash.bashrc
    if ! grep -q "alias menu=" ~/.bashrc 2>/dev/null; then
        echo "alias menu='/usr/local/bin/menu'" >> ~/.bashrc
    fi
    if ! grep -q "alias menu=" /etc/bash.bashrc 2>/dev/null; then
        echo "alias menu='/usr/local/bin/menu'" >> /etc/bash.bashrc
    fi
}

# Banner adaptativo al 100% del ancho de la terminal SSH
setup_login_banner() {
    cat << 'EOF' > /etc/profile.d/00-ariadny-banner.sh
#!/bin/bash
if [[ $- == *i* ]] && command -v python3 >/dev/null 2>&1; then
python3 -c '
import sys, os, shutil, re, unicodedata, subprocess

try:
    cols = shutil.get_terminal_size().columns
except Exception:
    cols = 80

w = max(36, cols)

# Colores ANSI Brillantes
B_BLUE = "\033[1;34m"
B_CYAN = "\033[1;36m"
B_GREEN = "\033[1;32m"
B_YELLOW = "\033[1;33m"
B_WHITE = "\033[1;37m"
B_PURPLE = "\033[1;35m"
NC = "\033[0m"

def vis_len(text):
    clean = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", text)
    l = 0
    for ch in clean:
        ord_c = ord(ch)
        if ord_c in (0xFE0F, 0xFE0E):
            continue
        if (0x1F000 <= ord_c <= 0x1FAFF) or \
           (0x2600 <= ord_c <= 0x27BF) or \
           (0x2300 <= ord_c <= 0x23FF) or \
           (0x2B50 <= ord_c <= 0x2B55) or \
           unicodedata.east_asian_width(ch) in ("F", "W"):
            l += 2
        else:
            l += 1
    return l

# Datos dinámicos del sistema
try:
    ip = subprocess.check_output("hostname -I 2>/dev/null", shell=True).decode().split()[0]
except Exception:
    ip = "127.0.0.1"

try:
    out = subprocess.check_output("free -h 2>/dev/null", shell=True).decode().splitlines()
    ram = out[1].split()[2] + " / " + out[1].split()[1]
except Exception:
    ram = "N/A"

try:
    os_info = "Linux"
    with open("/etc/os-release") as f:
        for line in f:
            if line.startswith("PRETTY_NAME="):
                os_info = line.split("=")[1].strip().strip("\"")
                break
except Exception:
    os_info = "Linux"

try:
    uptime_raw = subprocess.check_output("uptime -p 2>/dev/null", shell=True).decode().strip()
    uptime_info = uptime_raw.replace("up ", "") if uptime_raw else "N/A"
except Exception:
    uptime_info = "N/A"

# 1. Cabecera
print(B_BLUE + "╔" + ("═" * (w - 2)) + "╗" + NC)

title = B_WHITE + "🚀 ARIADNY MASTER PANEL v2.5" + NC
vt = vis_len(title)
pt = max(0, (w - 2 - vt) // 2)
ptr = max(0, w - 2 - vt - pt)
print(B_BLUE + "║" + NC + (" " * pt) + title + (" " * ptr) + B_BLUE + "║" + NC)

print(B_BLUE + "╠" + ("═" * (w - 2)) + "╣" + NC)

# 2. Filas de Información
fields = [
    ("🌐 IP VPS", ip, B_CYAN),
    ("🖥  SO", os_info, B_GREEN),
    ("⚡ RAM", ram, B_YELLOW),
    ("⏱  Uptime", uptime_info, B_PURPLE),
]

for label, val, val_col in fields:
    left_str = "  " + label + " : "
    vl = vis_len(left_str)
    rem_len = max(1, w - 2 - vl)
    val_display = val[:rem_len-1] + "…" if vis_len(val) > rem_len else val
    val_str = val_col + val_display + NC
    full_vis = vl + vis_len(val_display)
    pad = max(0, w - 2 - full_vis)
    print(B_BLUE + "║" + NC + left_str + val_str + (" " * pad) + B_BLUE + "║" + NC)

print(B_BLUE + "╠" + ("═" * (w - 2)) + "╣" + NC)

# 3. Pie con comando menu
footer = "  " + B_WHITE + "👉 Para abrir el panel escribe: " + B_YELLOW + "menu" + NC
vf = vis_len(footer)
pad_f = max(0, w - 2 - vf)
print(B_BLUE + "║" + NC + footer + (" " * pad_f) + B_BLUE + "║" + NC)

print(B_BLUE + "╚" + ("═" * (w - 2)) + "╝" + NC)
' 2>/dev/null
fi
EOF
    chmod +x /etc/profile.d/00-ariadny-banner.sh 2>/dev/null
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
    local max_len=14
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

    if systemctl is-active --quiet caddy 2>/dev/null; then
        local c_http=$(get_caddy_ports_http 2>/dev/null)
        local c_https=$(get_caddy_ports_https 2>/dev/null)
        local all_caddy=$(echo "$c_http $c_https" | xargs -n1 2>/dev/null | grep -v '^$' | sort -u -n | paste -sd, -)
        [[ -n "$all_caddy" ]] && ACTIVE_ITEMS+=("🌐 Caddy  : $(truncate_str "$all_caddy")") || ACTIVE_ITEMS+=("🌐 Caddy  : ACTIVO")
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
        local ng_ports=$(get_nginx_ports 2>/dev/null)
        local all_nginx=$(echo "$ng_ports" | tr ' ' ',' 2>/dev/null)
        [[ -n "$all_nginx" ]] && ACTIVE_ITEMS+=("🔀 Nginx  : $(truncate_str "$all_nginx")") || ACTIVE_ITEMS+=("🔀 Nginx  : ACTIVO")
    fi

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
        [[ -n "$v_out" ]] && ACTIVE_ITEMS+=("⚡ V2Ray  : $(truncate_str "$v_out")") || ACTIVE_ITEMS+=("⚡ V2Ray  : ACTIVO")
    fi

    SSHGO_PORTS_RAW=$(get_sshgo_ports 2>/dev/null)
    if [[ -n "$SSHGO_PORTS_RAW" ]] && (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null); then
        ACTIVE_ITEMS+=("🚀 SSH-Go : $(truncate_str "$(echo "$SSHGO_PORTS_RAW" | tr ' ' ',')")")
    fi

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
        [[ -n "$x_out" ]] && ACTIVE_ITEMS+=("🔰 XRay   : $(truncate_str "$x_out")") || ACTIVE_ITEMS+=("🔰 XRay   : ACTIVO")
    fi

    if systemctl is-active --quiet udp-custom 2>/dev/null || systemctl is-active --quiet udp-hysteria 2>/dev/null || systemctl is-active --quiet zivpn 2>/dev/null; then
        local u_p=$(get_udp_port)
        [[ -n "$u_p" ]] && ACTIVE_ITEMS+=("⚡ UDP    : $(truncate_str "$u_p")") || ACTIVE_ITEMS+=("⚡ UDP    : ON")
    fi

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

    if pgrep -f "socks-rust" >/dev/null || pgrep -f "rust-proxy" >/dev/null || pgrep -x "rust" >/dev/null || systemctl is-active --quiet rust-proxy 2>/dev/null || systemctl is-active --quiet socks-rust 2>/dev/null; then
        local r_p=$(get_socks_config_port)
        [[ -n "$r_p" ]] && ACTIVE_ITEMS+=("🦀 Rust   : $(truncate_str "$r_p")") || ACTIVE_ITEMS+=("🦀 Rust   : ON")
    fi

    if pgrep -f "proxy.py" >/dev/null || systemctl is-active --quiet python-proxy 2>/dev/null || (systemctl is-active --quiet socks-proxy 2>/dev/null && ! pgrep -f "socks-rust" >/dev/null && ! pgrep -f "rust-proxy" >/dev/null && ! pgrep -x "rust" >/dev/null); then
        local p_p=$(get_socks_config_port)
        [[ -n "$p_p" ]] && ACTIVE_ITEMS+=("🐍 Python : $(truncate_str "$p_p")") || ACTIVE_ITEMS+=("🐍 Python : ON")
    fi

    if systemctl is-active --quiet slowdns 2>/dev/null || systemctl is-active --quiet dns-server 2>/dev/null || pgrep -f "dns-server" >/dev/null || pgrep -f "slowdns" >/dev/null || pgrep -f "dnstt" >/dev/null; then
        local dns_p=$(get_slowdns_ports)
        [[ -n "$dns_p" ]] && ACTIVE_ITEMS+=("🐌 SlowDNS: $(truncate_str "$dns_p")") || ACTIVE_ITEMS+=("🐌 SlowDNS: ON")
    fi

    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -f "stunnel" >/dev/null; then
        local ssl_p=$(get_ssl_ports)
        [[ -n "$ssl_p" ]] && ACTIVE_ITEMS+=("🔒 SSL/TLS: $(truncate_str "$ssl_p")") || ACTIVE_ITEMS+=("🔒 SSL/TLS: ON")
    fi

    SSH_PORT_DISPLAY="22"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_p=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
        [[ -n "$ssh_p" ]] && SSH_PORT_DISPLAY="$ssh_p"
    fi
    ACTIVE_ITEMS+=("🔐 SSH    : $SSH_PORT_DISPLAY")
}

render_ui() {
    local mode="${1:-full}"
    
    clear_screen
    
    get_sys_info
    get_ports_summary

    local json_items="[]"
    if [[ ${#ACTIVE_ITEMS[@]} -gt 0 ]]; then
        json_items=$(python3 -c 'import sys, json; print(json.dumps(sys.argv[1:]))' "${ACTIVE_ITEMS[@]}" 2>/dev/null)
    fi

    python3 -c '
import sys, os, shutil, re, unicodedata, json

version = sys.argv[1]
ip = sys.argv[2]
os_info = sys.argv[3]
ram = sys.argv[4]
active_items = json.loads(sys.argv[5]) if len(sys.argv) > 5 else []
mode = sys.argv[6] if len(sys.argv) > 6 else "full"

try:
    cols = shutil.get_terminal_size().columns
except Exception:
    cols = 80

w = max(36, cols)

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
PURPLE = "\033[0;35m"
CYAN = "\033[0;36m"
WHITE = "\033[1;37m"
BOLD = "\033[1m"
NC = "\033[0m"

B_RED = "\033[1;31m"
B_GREEN = "\033[1;32m"
B_YELLOW = "\033[1;33m"
B_BLUE = "\033[1;34m"
B_PURPLE = "\033[1;35m"
B_CYAN = "\033[1;36m"
B_WHITE = "\033[1;37m"

def vis_len(text):
    clean = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", text)
    l = 0
    for ch in clean:
        ord_c = ord(ch)
        if ord_c in (0xFE0F, 0xFE0E):
            continue
        if (0x1F000 <= ord_c <= 0x1FAFF) or \
           (0x2600 <= ord_c <= 0x27BF) or \
           (0x2300 <= ord_c <= 0x23FF) or \
           (0x2B50 <= ord_c <= 0x2B55) or \
           unicodedata.east_asian_width(ch) in ("F", "W"):
            l += 2
        else:
            l += 1
    return l

def empty_row(color):
    print(color + "│" + NC + (" " * (w - 2)) + color + "│" + NC)

# 1. Cabecera Superior
print(B_BLUE + "╔" + ("═" * (w - 2)) + "╗" + NC)

title = B_WHITE + "🚀 ARIADNY MASTER PANEL " + version + NC
vt = vis_len(title)
pt = max(0, (w - 2 - vt) // 2)
ptr = max(0, w - 2 - vt - pt)
print(B_BLUE + "║" + NC + (" " * pt) + title + (" " * ptr) + B_BLUE + "║" + NC)

info_str = B_CYAN + "IP: " + ip + NC + "   " + B_CYAN + "OS: " + os_info + NC + "   " + B_GREEN + "RAM: " + ram + NC
vi = vis_len(info_str)
pi = max(0, (w - 2 - vi) // 2)
pir = max(0, w - 2 - vi - pi)
print(B_BLUE + "║" + NC + (" " * pi) + info_str + (" " * pir) + B_BLUE + "║" + NC)

creator_str = B_YELLOW + "Creador: " + NC + B_WHITE + "Yelsin Machado" + NC
vc = vis_len(creator_str)
pc = max(0, (w - 2 - vc) // 2)
pcr = max(0, w - 2 - vc - pc)
print(B_BLUE + "║" + NC + (" " * pc) + creator_str + (" " * pcr) + B_BLUE + "║" + NC)

print(B_BLUE + "╚" + ("═" * (w - 2)) + "╝" + NC)

# 2. Cuadro de Puertos Activos
if active_items:
    t_act = "PUERTOS Y SERVICIOS ACTIVOS"
    vt_act = vis_len(t_act)
    rem_act = max(0, w - 6 - vt_act)
    top_p = "┌── " + t_act + " " + ("─" * rem_act) + "┐"
    bot_p = "└" + ("─" * (w - 2)) + "┘"
    print(B_PURPLE + top_p + NC)
    
    half_w = (w - 4) // 2
    for i in range(0, len(active_items), 2):
        it1 = active_items[i]
        it2 = active_items[i+1] if i+1 < len(active_items) else ""
        v1 = vis_len(it1)
        p1 = max(0, half_w - v1)
        s1 = it1 + (" " * p1)
        v2 = vis_len(it2)
        p2 = max(0, (w - 2 - half_w) - v2)
        s2 = it2 + (" " * p2)
        print(B_PURPLE + "│" + NC + s1 + s2 + B_PURPLE + "│" + NC)
    print(B_PURPLE + bot_p + NC)

# 3. Menú según el modo de pantalla
if mode == "full":
    t_m1 = "PROTOCOLOS & PROXIES"
    vt_m1 = vis_len(t_m1)
    rem_m1 = max(0, w - 6 - vt_m1)
    top_m1 = "┌── " + t_m1 + " " + ("─" * rem_m1) + "┐"
    print(B_BLUE + top_m1 + NC)

    opts1 = [
        (B_CYAN + "[01]" + NC + " 🔀 " + WHITE + "Multiplexores" + NC, B_YELLOW + "[02]" + NC + " ⚡ " + WHITE + "V2Ray / VMess" + NC),
        (B_GREEN + "[03]" + NC + " 🚀 " + WHITE + "SSH-Go Proxy" + NC, B_PURPLE + "[04]" + NC + " 🔰 " + WHITE + "XRay Panel" + NC),
        (B_RED + "[05]" + NC + " ⚡ " + WHITE + "UDP Panel" + NC, B_YELLOW + "[06]" + NC + " 🦀 " + WHITE + "SOCKS Proxy Rust" + NC),
        (B_GREEN + "[07]" + NC + " 🐍 " + WHITE + "SOCKS Proxy Python" + NC, B_CYAN + "[08]" + NC + " 👥 " + WHITE + "SSH Panel / User" + NC),
        (B_PURPLE + "[09]" + NC + " 🚀 " + WHITE + "BadVPN UDPGW" + NC, B_YELLOW + "[10]" + NC + " 🐌 " + WHITE + "SlowDNS Panel" + NC),
        (B_BLUE + "[11]" + NC + " 🔒 " + WHITE + "SSL / TLS Manager" + NC, B_YELLOW + "[12]" + NC + " 📁 " + B_YELLOW + "Más Opciones..." + NC),
    ]

    half_w = (w - 4) // 2
    for c1, c2 in opts1:
        v1 = vis_len(c1)
        p1 = max(0, half_w - v1)
        s1 = c1 + (" " * p1)
        v2 = vis_len(c2)
        p2 = max(0, (w - 2 - half_w) - v2)
        s2 = c2 + (" " * p2)
        print(B_BLUE + "│" + NC + s1 + s2 + B_BLUE + "│" + NC)

    empty_row(B_BLUE)

    t_m2 = "GESTIÓN & MANTENIMIENTO"
    vt_m2 = vis_len(t_m2)
    rem_m2 = max(0, w - 6 - vt_m2)
    mid_m2 = "├── " + t_m2 + " " + ("─" * rem_m2) + "┤"
    print(B_BLUE + mid_m2 + NC)

    opts2 = [
        (B_RED + "[13]" + NC + " 🛡 " + WHITE + "Firewall" + NC, B_GREEN + "[14]" + NC + " 🔐 " + WHITE + "Configurar SSH" + NC),
        (B_CYAN + "[15]" + NC + " 📊 " + WHITE + "Monitoreo Sistema" + NC, B_PURPLE + "[16]" + NC + " 📋 " + WHITE + "Estado General" + NC),
        (B_RED + "[00]" + NC + " 🚪 " + B_RED + "Salir del Panel" + NC, ""),
    ]

    for c1, c2 in opts2:
        v1 = vis_len(c1)
        p1 = max(0, half_w - v1)
        s1 = c1 + (" " * p1)
        v2 = vis_len(c2)
        p2 = max(0, (w - 2 - half_w) - v2)
        s2 = c2 + (" " * p2)
        print(B_BLUE + "│" + NC + s1 + s2 + B_BLUE + "│" + NC)

    bot_m = "└" + ("─" * (w - 2)) + "┘"
    print(B_BLUE + bot_m + NC)

elif mode == "sub_multiplexacion":
    t_sub = "MULTIPLEXACIÓN & PROXIES WEB"
    vt_sub = vis_len(t_sub)
    rem_sub = max(0, w - 6 - vt_sub)
    top_sub = "┌── " + t_sub + " " + ("─" * rem_sub) + "┐"
    print(B_BLUE + top_sub + NC)

    sub_opts = [
        B_CYAN + "[01]" + NC + " 🌐 " + WHITE + "Caddy Server" + NC,
        B_CYAN + "[02]" + NC + " 🔀 " + WHITE + "Nginx Proxy" + NC,
        B_RED + "[00]" + NC + " ⬅️  " + B_RED + "Volver al Menú Principal" + NC
    ]

    for item in sub_opts:
        v = vis_len(item)
        p = max(0, w - 2 - v)
        print(B_BLUE + "│" + NC + item + (" " * p) + B_BLUE + "│" + NC)

    print(B_BLUE + "└" + ("─" * (w - 2)) + "┘" + NC)

elif mode == "sub_mas_opciones":
    t_sub = "MÁS OPCIONES & HERRAMIENTAS"
    vt_sub = vis_len(t_sub)
    rem_sub = max(0, w - 6 - vt_sub)
    top_sub = "┌── " + t_sub + " " + ("─" * rem_sub) + "┐"
    print(B_BLUE + top_sub + NC)

    sub_opts = [
        B_CYAN + "[01]" + NC + " ⚙️  " + WHITE + "Nueva Función 1 (Disponible)" + NC,
        B_CYAN + "[02]" + NC + " ⚙️  " + WHITE + "Nueva Función 2 (Disponible)" + NC,
        B_RED + "[00]" + NC + " ⬅️  " + B_RED + "Volver al Menú Principal" + NC
    ]

    for item in sub_opts:
        v = vis_len(item)
        p = max(0, w - 2 - v)
        print(B_BLUE + "│" + NC + item + (" " * p) + B_BLUE + "│" + NC)

    print(B_BLUE + "└" + ("─" * (w - 2)) + "┘" + NC)
' "$VERSION" "$IP_ADDR" "$OS_INFO" "$RAM_INFO" "$json_items" "$mode" 2>/dev/null
}

prepare_for_external_script() {
    clear_screen
}

header() {
    render_ui "full"
}

panel_header() {
    local title="$1"
    local icon="${2:-◆}"
    render_ui "header"
    printf "\n  %b%s %s%b\n\n" "$YELLOW$BOLD" "$icon" "$title" "$NC"
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
    prepare_for_external_script
    if systemctl is-active --quiet caddy 2>/dev/null; then
        if [[ -x /usr/local/bin/cadmin ]]; then
            /usr/local/bin/cadmin
        elif [[ -x /usr/bin/cadmin ]]; then
            /usr/bin/cadmin
        else
            panel_header "INSTALANDO/EJECUTANDO CADDY PROXY" "🌐"
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
    prepare_for_external_script
    if systemctl is-active --quiet nginx 2>/dev/null; then
        if [[ -x /usr/local/bin/MenuN ]]; then
            /usr/local/bin/MenuN
        elif [[ -x /usr/local/bin/menun ]]; then
            /usr/local/bin/menun
        else
            panel_header "EJECUTANDO NGINX PROXY" "🔀"
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
        render_ui "sub_multiplexacion"

        printf "\n"
        echo -ne "  \033[1;33m> Selecciona una opción [0-2]: \033[0m"
        read sub_m
        sub_m=$(echo "$sub_m" | tr -d '\r\n\t ')

        case "$sub_m" in
            1|01) caddy_menu ;;
            2|02) nginx_menu ;;
            0|00) break ;;
            *) warn "Opción inválida."; sleep 1 ;;
        esac
    done
}

v2ray_menu() {
    prepare_for_external_script
    panel_header "INSTALANDO/EJECUTANDO V2RAY" "⚡"
    if [[ -x /usr/local/bin/v2ray ]]; then
        /usr/local/bin/v2ray
    elif [[ -x /usr/bin/v2ray ]]; then
        /usr/bin/v2ray
    else
        execute_script "install-v2ray.sh" "v2ray.sh" "V2ray.sh"
        pause_screen
    fi
}

xray_menu() {
    prepare_for_external_script
    if [[ -x /usr/local/bin/xray-panel ]]; then
        /usr/local/bin/xray-panel
    elif command_exists menuV2; then
        menuV2
    else
        panel_header "INSTALANDO XRAY PANEL DESDE GITHUB" "🔰"
        execute_script "install-xray.sh" "xray.sh" "Xray.sh"
        pause_screen
    fi
}

sshgo_menu() {
    prepare_for_external_script
    panel_header "SSH-GO PROXY" "🚀"
    execute_script "install-sshgo.sh" "sshgo.sh" "Sshgo.sh"
    pause_screen
}

badvpn_menu() {
    prepare_for_external_script
    panel_header "BADVPN UDPGW" "🚀"
    execute_script "badvpn-udpgw.sh" "badvpn.sh" "Badvpn.sh"
    pause_screen
}

slowdns_menu() {
    prepare_for_external_script
    panel_header "SLOWDNS PANEL" "🐌"
    execute_script "slowdns.sh" "Slowdns.sh"
    pause_screen
}

ssl_menu() {
    prepare_for_external_script
    panel_header "CERTIFICADO SSL / STUNNEL" "🔒"
    execute_script "ssl.sh" "Ssl.sh"
    pause_screen
}

mas_opciones_menu() {
    while true; do
        render_ui "sub_mas_opciones"

        printf "\n"
        echo -ne "  \033[1;33m> Selecciona una opción [0-2]: \033[0m"
        read sub_op
        sub_op=$(echo "$sub_op" | tr -d '\r\n\t ')

        case "$sub_op" in
            1|01)
                prepare_for_external_script
                info "Aquí puedes vincular tu nueva función 1."
                pause_screen
                ;;
            2|02)
                prepare_for_external_script
                info "Aquí puedes vincular tu nueva función 2."
                pause_screen
                ;;
            0|00) break ;;
            *) warn "Opción inválida."; sleep 1 ;;
        esac
    done
}

firewall_menu() {
    prepare_for_external_script
    panel_header "FIREWALL SYSTEM" "🛡️"
    execute_script "firewall.sh" "Firewall.sh"
    pause_screen
}

udp_menu() {
    prepare_for_external_script
    panel_header "UDP PANEL" "⚡"
    execute_script "Udp.sh" "udp.sh" "install-udp.sh"
    pause_screen
}

rust_menu() {
    prepare_for_external_script
    panel_header "SOCKS PROXY RUST" "🦀"
    execute_script "rust.sh" "Rust.sh"
    pause_screen
}

python_menu() {
    prepare_for_external_script
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
    prepare_for_external_script
    local ssh_panel="/usr/local/bin/sshpanel.sh"
    panel_header "SSH PANEL MANAGER" "👥"
    printf "  %bDescargando panel SSH...%b\n" "$CYAN" "$NC"
    if download_to_path "sshpanel.sh" "$ssh_panel" || download_to_path "Sshpanel.sh" "$ssh_panel"; then
        bash "$ssh_panel"
    fi
    pause_screen
}

configure_ssh() {
    prepare_for_external_script
    panel_header "CONFIGURACIÓN DE SSH" "🔐"
    execute_script "ssh.sh" "Ssh.sh"
    pause_screen
}

monitor_menu() {
    prepare_for_external_script
    panel_header "MONITOREO DEL SISTEMA" "📊"
    printf "  %bSistema    :%b %s\n" "$WHITE" "$NC" "$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)"
    printf "  %bMemoria    :%b %s\n" "$WHITE" "$NC" "$(free -h | awk 'NR==2 {print $3 " / " $2}')"
    printf "  %bDisco      :%b %s\n" "$WHITE" "$NC" "$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    printf "  %bUptime     :%b %s\n" "$WHITE" "$NC" "$(uptime -p 2>/dev/null || echo N/A)"
    pause_screen
}

status_menu() {
    prepare_for_external_script
    panel_header "ESTADO GENERAL DE SERVICIOS" "📋"
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
        # Auto-reparar comando por si un sub-script lo sobreescribió
        setup_menu_shortcut
        
        render_ui "full"

        printf "\n"
        echo -ne "  \033[1;33m> Selecciona una opción [0-16]: \033[0m"
        read option
        option=$(echo "$option" | tr -d '\r\n\t ')

        case "$option" in
            1|01) multiplexacion_menu ;;
            2|02) v2ray_menu ;;
            3|03) sshgo_menu ;;
            4|04) xray_menu ;;
            5|05) udp_menu ;;
            6|06) rust_menu ;;
            7|07) python_menu ;;
            8|08) ssh_panel_menu ;;
            9|09) badvpn_menu ;;
            10) slowdns_menu ;;
            11) ssl_menu ;;
            12) mas_opciones_menu ;;
            13) firewall_menu ;;
            14) configure_ssh ;;
            15) monitor_menu ;;
            16) status_menu ;;
            0|00)
                clear_screen
                printf "\n  %b¡Gracias por usar Ariadny Master Panel!%b\n\n" "$GREEN" "$NC"
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
setup_login_banner
main_menu
