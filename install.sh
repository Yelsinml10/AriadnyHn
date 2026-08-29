#!/bin/bash

# =======================================================
# ARIADNY MASTER PANEL - FULL PORTS SCANNER & 2-COL UI
# =======================================================

cleanup() {
    printf "\033[0m"
}
trap cleanup EXIT INT TERM

VERSION="v2.5"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"
CORE_PANEL_PATH="/etc/ariadny/menu.sh"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

clear_screen() {
    clear
}

pause_screen() {
    printf "\n  \033[0;90mPresiona \033[1;37mENTER\033[0;90m para continuar...\033[0m"
    read -r
}

info() {
    printf "  \033[0;32m✔\033[0m %s\n" "$1"
}

warn() {
    printf "  \033[1;33m⚠\033[0m %s\n" "$1"
}

error_msg() {
    printf "  \033[0;31m✖\033[0m %s\n" "$1" >&2
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error_msg "Ejecuta el panel como root: sudo bash $0"
        exit 1
    fi
}

install_dependencies() {
    if ! command_exists curl || ! command_exists python3; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y curl python3 -qq >/dev/null 2>&1 || yum install -y curl python3 -qq >/dev/null 2>&1
    fi
}

setup_terminal_banner() {
    cat << 'EOF' > /etc/profile.d/99-ariadny-banner.sh
# Banner de Bienvenida Ariadny
if [[ $- == *i* ]]; then
    IP_ADDR=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$IP_ADDR" ]] && IP_ADDR="127.0.0.1"
    RAM_INFO=$(free -h 2>/dev/null | awk 'NR==2 {print $3 "/" $2}')
    DISK_INFO=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    OS_INFO=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null | cut -d' ' -f1,2)
    [[ -z "$OS_INFO" ]] && OS_INFO="Linux"

    echo -e "\033[1;34m╔══════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;36m  █████╗ ██████╗ ██╗ █████╗ ██████╗ ███╗   ██╗██╗   ██╗\033[0m"
    echo -e "\033[1;36m ██╔══██╗██╔══██╗██║██╔══██╗██╔══██╗████╗  ██║╚██╗ ██╔╝\033[0m"
    echo -e "\033[1;36m ███████║██████╔╝██║███████║██║  ██║██╔██╗ ██║ ╚████╔╝ \033[0m"
    echo -e "\033[1;36m ██╔══██║██╔══██╗██║██╔══██║██║  ██║██║╚██╗██║  ╚██╔╝  \033[0m"
    echo -e "\033[1;36m ██║  ██║██║  ██║██║██║  ██║██████╔╝██║ ╚████║   ██║   \033[0m"
    echo -e "\033[1;36m ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═══╝   ╚═╝   \033[0m"
    echo -e "\033[1;34m╠══════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;36m  🌐 IP VPS  :\033[1;37m $IP_ADDR\033[0m"
    echo -e "\033[1;32m  🖥  SO      :\033[1;37m $OS_INFO\033[0m"
    echo -e "\033[1;33m  ⚡ RAM     :\033[1;37m $RAM_INFO\033[0m"
    echo -e "\033[1;35m  💾 DISCO   :\033[1;37m $DISK_INFO\033[0m"
    echo -e "\033[1;34m╠══════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;33m  👉 Usa el comando \033[1;32mmenu\033[1;33m para ingresar al panel de la VPS\033[0m"
    echo -e "\033[1;34m╚══════════════════════════════════════════════════════════╝\033[0m"
fi
EOF
    chmod +x /etc/profile.d/99-ariadny-banner.sh 2>/dev/null
}

setup_menu_shortcut() {
    mkdir -p /etc/ariadny 2>/dev/null

    local current_script
    current_script="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

    if [[ -f "$current_script" && "$current_script" != *"/dev/fd/"* && "$current_script" != *"bash"* ]]; then
        cp -f "$current_script" "$CORE_PANEL_PATH" 2>/dev/null
    fi

    chmod 755 "$CORE_PANEL_PATH" 2>/dev/null

    for bindir in /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
        if [[ -d "$bindir" ]]; then
            cat << 'EOF' > "$bindir/menu"
#!/bin/bash
if [[ -f /etc/ariadny/menu.sh ]]; then
    bash /etc/ariadny/menu.sh "$@"
else
    curl -fsSL https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main/menu.sh -o /etc/ariadny/menu.sh 2>/dev/null
    chmod 755 /etc/ariadny/menu.sh 2>/dev/null
    bash /etc/ariadny/menu.sh "$@"
fi
EOF
            chmod 755 "$bindir/menu" 2>/dev/null
        fi
    done

    cat << 'EOF' > /etc/profile.d/00-ariadny-menu.sh
alias menu='bash /etc/ariadny/menu.sh'
EOF
    chmod +x /etc/profile.d/00-ariadny-menu.sh 2>/dev/null

    for rc in /root/.bashrc /etc/bash.bashrc /etc/profile; do
        if [[ -f "$rc" ]]; then
            sed -i '/alias menu=/d' "$rc" 2>/dev/null
            echo "alias menu='bash /etc/ariadny/menu.sh'" >> "$rc"
        fi
    done

    setup_terminal_banner
}

get_sys_info() {
    IP_ADDR=$(curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$IP_ADDR" ]] && IP_ADDR="127.0.0.1"
    
    RAM_INFO=$(free -h 2>/dev/null | awk 'NR==2 {print $3 "/" $2}')
    [[ -z "$RAM_INFO" ]] && RAM_INFO="N/A"
    
    DISK_INFO=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    [[ -z "$DISK_INFO" ]] && DISK_INFO="N/A"

    OS_INFO=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null | cut -d' ' -f1,2)
    [[ -z "$OS_INFO" ]] && OS_INFO="Linux"
}

truncate_str() {
    local str="$1"
    local max_len=18
    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$max_len}..."
    else
        echo "$str"
    fi
}

# ==================== DETECTORES DE PUERTOS ====================

get_caddy_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "caddy" in line.lower():
            for m in re.findall(r":(\d+)\s", line):
                p = int(m)
                if p not in [2019]: ports.add(p)
except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_nginx_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "nginx" in line.lower():
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_v2ray_ports() {
    python3 -c '
import subprocess, re, json
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "v2ray" in line.lower():
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if not ports:
    for cfg in ["/usr/local/v2ray/config.json", "/usr/local/etc/v2ray/config.json", "/etc/v2ray/config.json"]:
        try:
            with open(cfg, "r") as f:
                d = json.load(f)
                inbs = d.get("inbounds", [])
                if "inbound" in d: inbs.append(d["inbound"])
                for inb in inbs:
                    if "port" in inb and str(inb["port"]).isdigit():
                        ports.add(int(inb["port"]))
        except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_xray_ports() {
    python3 -c '
import subprocess, re, json
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "xray" in line.lower():
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if not ports:
    for cfg in ["/usr/local/etc/xray/config.json", "/etc/xray/config.json"]:
        try:
            with open(cfg, "r") as f:
                d = json.load(f)
                inbs = d.get("inbounds", [])
                if "inbound" in d: inbs.append(d["inbound"])
                for inb in inbs:
                    if "port" in inb and str(inb["port"]).isdigit():
                        ports.add(int(inb["port"]))
        except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_sshgo_ports() {
    python3 -c '
import subprocess, re, json
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line.lower() for x in ["vpn-proxy", "ssh-go"]):
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if not ports:
    for cfg in ["/opt/vpn-proxy/config.json", "/etc/vpn-proxy/config.json", "/etc/ssh-go/config.json"]:
        try:
            with open(cfg, "r") as f:
                d = json.load(f)
                p = d.get("port") or d.get("ports")
                if isinstance(p, int): ports.add(p)
                elif isinstance(p, list): ports.update([int(x) for x in p if str(x).isdigit()])
        except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_udp_ports() {
    python3 -c '
import subprocess, re, json
ports = set()
try:
    out = subprocess.check_output("ss -ulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line.lower() for x in ["udp", "hysteria", "zivpn", "udp-custom"]):
            for m in re.findall(r":(\d+)\s", line):
                p = int(m)
                if p not in [68, 123]: ports.add(p)
except Exception: pass
if not ports:
    for cfg in ["/etc/udp/config.json", "/etc/udp-custom/config.json", "/etc/hysteria/config.json", "/etc/zivpn/config.json"]:
        try:
            with open(cfg, "r") as f:
                for m in re.findall(r":(\d+)", f.read()):
                    ports.add(int(m))
        except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_badvpn_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ps aux | grep badvpn-udpgw | grep -v grep", shell=True).decode()
    for m in re.findall(r"--listen-addr\s+(?:127\.0\.0\.1:)?(\d+)", out):
        ports.add(int(m))
except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_rust_ports() {
    python3 -c '
import subprocess, re, json

ports = set()
listening_ports = set()

# 1. Obtener puertos en escucha en ss
try:
    ss_out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in ss_out.splitlines():
        if any(x in line.lower() for x in ["socks-rust", "rust-proxy", "socks_rust", "rust_proxy", "proxy-rust", "rust-socks", "socks-proxy", "ssservice"]) or ("rust" in line.lower() and not any(k in line.lower() for k in ["caddy", "nginx", "python", "sshd", "xray", "v2ray"])):
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
        if not any(k in line.lower() for k in ["sshd", "caddy", "nginx", "xray", "v2ray"]):
            for m in re.findall(r":(\d+)\s", line):
                listening_ports.add(int(m))
except Exception:
    pass

# 2. Si no lo detectó directo en ss, leer archivos de configuración y verificar si su puerto está activo
config_files = [
    "/root/socks_config.json",
    "/etc/socks-rust/config.json",
    "/etc/rust-proxy/config.json",
    "/etc/proxy-rust/config.json",
    "/etc/rust/config.json",
    "/etc/shadowsocks-rust/config.json",
    "/etc/socks/config.json"
]

for cfg in config_files:
    try:
        with open(cfg, "r") as f:
            d = json.load(f)
            p = d.get("ports") or d.get("port") or d.get("server_port") or d.get("local_port")
            candidates = []
            if isinstance(p, list):
                candidates = [int(x) for x in p if str(x).isdigit()]
            elif isinstance(p, (int, str)) and str(p).isdigit():
                candidates = [int(p)]
            for cp in candidates:
                if cp in listening_ports or not ports:
                    if cp in listening_ports:
                        ports.add(cp)
    except Exception:
        pass

if ports:
    print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_python_ports() {
    python3 -c '
import subprocess, re, json
ports = set()
listening_ports = set()
try:
    ss_out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in ss_out.splitlines():
        if "proxy.py" in line.lower() or ("python" in line.lower() and not any(k in line.lower() for k in ["rust", "caddy", "nginx", "sshd", "xray", "v2ray"])):
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
        if not any(k in line.lower() for k in ["sshd", "caddy", "nginx", "xray", "v2ray"]):
            for m in re.findall(r":(\d+)\s", line):
                listening_ports.add(int(m))
except Exception: pass

for cfg in ["/root/socks_config.json", "/etc/socks-python/config.json", "/etc/python-proxy/config.json"]:
    try:
        with open(cfg, "r") as f:
            d = json.load(f)
            p = d.get("ports") or d.get("port")
            candidates = []
            if isinstance(p, list): candidates = [int(x) for x in p if str(x).isdigit()]
            elif isinstance(p, (int, str)) and str(p).isdigit(): candidates = [int(p)]
            for cp in candidates:
                if cp in listening_ports: ports.add(cp)
    except Exception: pass

if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_slowdns_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line.lower() for x in ["dns-server", "slowdns", "dnstt", "server-dns"]):
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if not ports and (subprocess.call("pgrep -f dns-server >/dev/null 2>&1", shell=True) == 0 or subprocess.call("pgrep -f slowdns >/dev/null 2>&1", shell=True) == 0):
    ports.add(53)
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_ssl_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if any(x in line.lower() for x in ["stunnel", "stunnel4"]):
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if not ports:
    try:
        with open("/etc/stunnel/stunnel.conf", "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("accept"):
                    m = re.search(r"=\s*(?:[0-9.]+:)?([0-9]+)", line)
                    if m: ports.add(int(m.group(1)))
    except Exception: pass
if ports: print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

get_ssh_ports() {
    python3 -c '
import subprocess, re
ports = set()
try:
    out = subprocess.check_output("ss -tlpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "\"sshd\"" in line or ("sshd" in line.lower() and not any(x in line.lower() for x in ["python", "vpn-proxy", "ssh-go", "socks", "rust"])):
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception: pass
if not ports:
    try:
        with open("/etc/ssh/sshd_config", "r") as f:
            for line in f:
                if re.match(r"^\s*Port\s+\d+", line, re.I):
                    ports.add(int(line.split()[1]))
    except Exception: pass
if not ports: ports.add(22)
print(",".join(map(str, sorted(ports))))
' 2>/dev/null
}

# ==================== FILTRADO ESTRICTO DE ACTIVOS ====================

get_ports_summary() {
    ACTIVE_ITEMS=()

    # Caddy
    local caddy_p=$(get_caddy_ports)
    if [[ -n "$caddy_p" ]] && (systemctl is-active --quiet caddy 2>/dev/null || pgrep -x caddy >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("🌐 Caddy   : $(truncate_str "$caddy_p")")
    fi

    # Nginx
    local nginx_p=$(get_nginx_ports)
    if [[ -n "$nginx_p" ]] && (systemctl is-active --quiet nginx 2>/dev/null || pgrep -x nginx >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("🔀 Nginx   : $(truncate_str "$nginx_p")")
    fi

    # V2Ray
    local v2ray_p=$(get_v2ray_ports)
    if [[ -n "$v2ray_p" ]] && (systemctl is-active --quiet v2ray 2>/dev/null || pgrep -f "v2ray" >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("⚡ V2Ray   : $(truncate_str "$v2ray_p")")
    fi

    # SSH-Go
    local sshgo_p=$(get_sshgo_ports)
    if [[ -n "$sshgo_p" ]] && (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null || pgrep -f "vpn-proxy" >/dev/null 2>&1 || pgrep -f "ssh-go" >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("🚀 SSH-Go  : $(truncate_str "$sshgo_p")")
    fi

    # XRay
    local xray_p=$(get_xray_ports)
    if [[ -n "$xray_p" ]] && (systemctl is-active --quiet xray 2>/dev/null || pgrep -f "xray" >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("🔰 XRay    : $(truncate_str "$xray_p")")
    fi

    # UDP Panel
    local udp_p=$(get_udp_ports)
    if [[ -n "$udp_p" ]] && (systemctl is-active --quiet udp-custom 2>/dev/null || systemctl is-active --quiet udp-hysteria 2>/dev/null || systemctl is-active --quiet zivpn 2>/dev/null || pgrep -f "udp-custom" >/dev/null 2>&1 || pgrep -f "zivpn" >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("⚡ UDP     : $(truncate_str "$udp_p")")
    fi

    # BadVPN
    local badvpn_p=$(get_badvpn_ports)
    if [[ -n "$badvpn_p" ]] && (pgrep -f badvpn-udpgw >/dev/null 2>&1 || systemctl is-active --quiet badvpn 2>/dev/null); then
        ACTIVE_ITEMS+=("🚀 BadVPN  : $(truncate_str "$badvpn_p")")
    fi

    # Rust
    local rust_p=$(get_rust_ports)
    if [[ -n "$rust_p" ]]; then
        ACTIVE_ITEMS+=("🦀 Rust    : $(truncate_str "$rust_p")")
    elif systemctl is-active --quiet rust-proxy 2>/dev/null || systemctl is-active --quiet socks-rust 2>/dev/null || systemctl is-active --quiet rust 2>/dev/null || pgrep -f "socks-rust" >/dev/null 2>&1 || pgrep -f "rust-proxy" >/dev/null 2>&1 || pgrep -f "socks_rust" >/dev/null 2>&1; then
        ACTIVE_ITEMS+=("🦀 Rust    : ON")
    fi

    # Python
    local python_p=$(get_python_ports)
    if [[ -n "$python_p" ]] && (pgrep -f "proxy.py" >/dev/null 2>&1 || systemctl is-active --quiet python-proxy 2>/dev/null || pgrep -f "python-proxy" >/dev/null 2>&1 || pgrep -f "P-Proxy" >/dev/null 2>&1); then
        ACTIVE_ITEMS+=("🐍 Python  : $(truncate_str "$python_p")")
    fi

    # SlowDNS
    if systemctl is-active --quiet slowdns 2>/dev/null || systemctl is-active --quiet dns-server 2>/dev/null || pgrep -f "dns-server" >/dev/null 2>&1 || pgrep -f "slowdns" >/dev/null 2>&1 || pgrep -f "dnstt" >/dev/null 2>&1; then
        local slowdns_p=$(get_slowdns_ports)
        [[ -n "$slowdns_p" ]] && ACTIVE_ITEMS+=("🐌 SlowDNS : $(truncate_str "$slowdns_p")") || ACTIVE_ITEMS+=("🐌 SlowDNS : 53")
    fi

    # SSL/Stunnel
    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -f "stunnel" >/dev/null 2>&1; then
        local ssl_p=$(get_ssl_ports)
        [[ -n "$ssl_p" ]] && ACTIVE_ITEMS+=("🔒 SSL/TLS : $(truncate_str "$ssl_p")") || ACTIVE_ITEMS+=("🔒 SSL/TLS : ON")
    fi

    # SSH
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null || pgrep -x sshd >/dev/null 2>&1; then
        local ssh_p=$(get_ssh_ports)
        [[ -n "$ssh_p" ]] && ACTIVE_ITEMS+=("🔐 SSH     : $(truncate_str "$ssh_p")") || ACTIVE_ITEMS+=("🔐 SSH     : 22")
    fi
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
disk = sys.argv[5]
active_items = json.loads(sys.argv[6]) if len(sys.argv) > 6 else []
mode = sys.argv[7] if len(sys.argv) > 7 else "full"

try:
    cols = shutil.get_terminal_size().columns
except Exception:
    cols = 80

w = max(42, cols - 1 if cols > 42 else cols)

B_RED = "\033[1;31m"
B_GREEN = "\033[1;32m"
B_YELLOW = "\033[1;33m"
B_BLUE = "\033[1;34m"
B_PURPLE = "\033[1;35m"
B_CYAN = "\033[1;36m"
B_WHITE = "\033[1;37m"
WHITE = "\033[1;37m"
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

def print_centered(text, border_col=B_BLUE):
    vt = vis_len(text)
    pt = max(0, (w - 2 - vt) // 2)
    ptr = max(0, w - 2 - vt - pt)
    print(border_col + "║" + NC + (" " * pt) + text + (" " * ptr) + border_col + "║" + NC)

# 1. Cabecera Banner
print(B_BLUE + "╔" + ("═" * (w - 2)) + "╗" + NC)

banner = [
    " █████╗ ██████╗ ██╗ █████╗ ██████╗ ███╗   ██╗██╗   ██╗",
    "██╔══██╗██╔══██╗██║██╔══██╗██╔══██╗████╗  ██║╚██╗ ██╔╝",
    "███████║██████╔╝██║███████║██║  ██║██╔██╗ ██║ ╚████╔╝ ",
    "██╔══██║██╔══██╗██║██╔══██║██║  ██║██║╚██╗██║  ╚██╔╝  ",
    "██║  ██║██║  ██║██║██║  ██║██████╔╝██║ ╚████║   ██║   ",
    "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═══╝   ╚═╝   "
]

for b_line in banner:
    if vis_len(b_line) <= w - 4:
        print_centered(B_CYAN + b_line + NC)

title = B_WHITE + "🚀 ARIADNY MASTER PANEL " + version + NC + "  " + B_YELLOW + "👑 Creador: " + B_WHITE + "Yelsin Machado" + NC
print_centered(title)
print(B_BLUE + "╠" + ("═" * (w - 2)) + "╣" + NC)

c1_w = (w - 2) // 2
c2_w = (w - 2) - c1_w

f1 = "  " + B_CYAN + "🌐 IP VPS  : " + WHITE + ip + NC
f2 = "  " + B_GREEN + "🖥  SO      : " + WHITE + os_info + NC
f3 = "  " + B_YELLOW + "⚡ RAM     : " + WHITE + ram + NC
f4 = "  " + B_PURPLE + "💾 DISCO   : " + WHITE + disk + NC

for l1, l2 in [(f1, f2), (f3, f4)]:
    v1 = vis_len(l1); p1 = max(0, c1_w - v1); s1 = l1 + (" " * p1)
    v2 = vis_len(l2); p2 = max(0, c2_w - v2); s2 = l2 + (" " * p2)
    print(B_BLUE + "║" + NC + s1 + s2 + B_BLUE + "║" + NC)

print(B_BLUE + "╚" + ("═" * (w - 2)) + "╝" + NC)

# 2. Servicios Activos (Con puertos detectados)
if active_items:
    t_act = "PUERTOS Y SERVICIOS ACTIVOS"
    vt_act = vis_len(t_act)
    rem_act = max(0, w - 6 - vt_act)
    print(B_PURPLE + "┌── " + t_act + " " + ("─" * rem_act) + "┐" + NC)
    
    for i in range(0, len(active_items), 2):
        i1 = "  " + active_items[i]
        i2 = "  " + active_items[i+1] if i+1 < len(active_items) else ""
        v1 = vis_len(i1); p1 = max(0, c1_w - v1); s1 = i1 + (" " * p1)
        v2 = vis_len(i2); p2 = max(0, c2_w - v2); s2 = i2 + (" " * p2)
        print(B_PURPLE + "│" + NC + s1 + s2 + B_PURPLE + "│" + NC)
    print(B_PURPLE + "└" + ("─" * (w - 2)) + "┘" + NC)

# 3. Menú Principal (2 Columnas con Opciones a Diferentes Colores)
if mode == "full":
    t_m1 = "PROTOCOLOS & PROXIES"
    vt_m1 = vis_len(t_m1)
    rem_m1 = max(0, w - 6 - vt_m1)
    print(B_BLUE + "┌── " + t_m1 + " " + ("─" * rem_m1) + "┐" + NC)

    opts1 = [
        ("  " + B_CYAN + "[01]" + NC + " 🔀 " + B_CYAN + "Multiplexores" + NC, "  " + B_YELLOW + "[02]" + NC + " ⚡ " + B_YELLOW + "V2Ray / VMess" + NC),
        ("  " + B_GREEN + "[03]" + NC + " 🚀 " + B_GREEN + "SSH-Go Proxy" + NC, "  " + B_PURPLE + "[04]" + NC + " 🔰 " + B_PURPLE + "XRay Panel" + NC),
        ("  " + B_RED + "[05]" + NC + " ⚡ " + B_RED + "UDP Panel" + NC, "  " + B_YELLOW + "[06]" + NC + " 🦀 " + B_YELLOW + "SOCKS Proxy Rust" + NC),
        ("  " + B_GREEN + "[07]" + NC + " 🐍 " + B_GREEN + "SOCKS Proxy Python" + NC, "  " + B_CYAN + "[08]" + NC + " 👥 " + B_CYAN + "SSH Panel / User" + NC),
        ("  " + B_PURPLE + "[09]" + NC + " 🚀 " + B_PURPLE + "BadVPN UDPGW" + NC, "  " + B_YELLOW + "[10]" + NC + " 🐌 " + B_YELLOW + "SlowDNS Panel" + NC),
        ("  " + B_BLUE + "[11]" + NC + " 🔒 " + B_BLUE + "SSL / TLS Manager" + NC, "  " + B_YELLOW + "[12]" + NC + " 📁 " + B_YELLOW + "Más Opciones..." + NC),
    ]

    for c1, c2 in opts1:
        v1 = vis_len(c1); p1 = max(0, c1_w - v1); s1 = c1 + (" " * p1)
        v2 = vis_len(c2); p2 = max(0, c2_w - v2); s2 = c2 + (" " * p2)
        print(B_BLUE + "│" + NC + s1 + s2 + B_BLUE + "│" + NC)

    print(B_BLUE + "│" + NC + (" " * (w - 2)) + B_BLUE + "│" + NC)

    t_m2 = "GESTIÓN & MANTENIMIENTO"
    vt_m2 = vis_len(t_m2)
    rem_m2 = max(0, w - 6 - vt_m2)
    print(B_BLUE + "├── " + t_m2 + " " + ("─" * rem_m2) + "┤" + NC)

    opts2 = [
        ("  " + B_RED + "[13]" + NC + " 🛡 " + B_RED + "Firewall" + NC, "  " + B_GREEN + "[14]" + NC + " 🔐 " + B_GREEN + "Configurar SSH" + NC),
        ("  " + B_CYAN + "[15]" + NC + " 📊 " + B_CYAN + "Monitoreo Sistema" + NC, "  " + B_PURPLE + "[16]" + NC + " 📋 " + B_PURPLE + "Estado General" + NC),
        ("  " + B_RED + "[00]" + NC + " 🚪 " + B_RED + "Salir del Panel" + NC, ""),
    ]

    for c1, c2 in opts2:
        v1 = vis_len(c1); p1 = max(0, c1_w - v1); s1 = c1 + (" " * p1)
        v2 = vis_len(c2); p2 = max(0, c2_w - v2); s2 = c2 + (" " * p2)
        print(B_BLUE + "│" + NC + s1 + s2 + B_BLUE + "│" + NC)

    print(B_BLUE + "└" + ("─" * (w - 2)) + "┘" + NC)

elif mode == "sub_multiplexacion":
    t_sub = "MULTIPLEXACIÓN & PROXIES WEB"
    vt_sub = vis_len(t_sub)
    rem_sub = max(0, w - 6 - vt_sub)
    print(B_BLUE + "┌── " + t_sub + " " + ("─" * rem_sub) + "┐" + NC)

    sub_opts = [
        "  " + B_CYAN + "[01]" + NC + " 🌐 " + B_CYAN + "Caddy Server" + NC,
        "  " + B_GREEN + "[02]" + NC + " 🔀 " + B_GREEN + "Nginx Proxy" + NC,
        "  " + B_RED + "[00]" + NC + " ⬅️  " + B_RED + "Volver al Menú Principal" + NC
    ]

    for item in sub_opts:
        v = vis_len(item); p = max(0, w - 2 - v)
        print(B_BLUE + "│" + NC + item + (" " * p) + B_BLUE + "│" + NC)

    print(B_BLUE + "└" + ("─" * (w - 2)) + "┘" + NC)

elif mode == "sub_mas_opciones":
    t_sub = "MÁS OPCIONES & HERRAMIENTAS"
    vt_sub = vis_len(t_sub)
    rem_sub = max(0, w - 6 - vt_sub)
    print(B_BLUE + "┌── " + t_sub + " " + ("─" * rem_sub) + "┐" + NC)

    sub_opts = [
        "  " + B_CYAN + "[01]" + NC + " ⚙️  " + B_CYAN + "Nueva Función 1" + NC,
        "  " + B_GREEN + "[02]" + NC + " ⚙️  " + B_GREEN + "Nueva Función 2" + NC,
        "  " + B_RED + "[00]" + NC + " ⬅️  " + B_RED + "Volver al Menú Principal" + NC
    ]

    for item in sub_opts:
        v = vis_len(item); p = max(0, w - 2 - v)
        print(B_BLUE + "│" + NC + item + (" " * p) + B_BLUE + "│" + NC)

    print(B_BLUE + "└" + ("─" * (w - 2)) + "┘" + NC)
' "$VERSION" "$IP_ADDR" "$OS_INFO" "$RAM_INFO" "$DISK_INFO" "$json_items" "$mode" 2>/dev/null
}

prepare_for_external_script() {
    clear_screen
}

panel_header() {
    local title="$1"
    local icon="${2:-◆}"
    render_ui "header"
    printf "\n  \033[1;33m%s %s\033[0m\n\n" "$icon" "$title"
}

download_to_path() {
    local destination="$1"
    shift
    local names=("$@")

    for script_name in "${names[@]}"; do
        printf "  \033[0;36m⬇ Descargando %s...\033[0m\n" "$script_name"
        if curl -fsSL --connect-timeout 15 --max-time 300 "$BASE_URL/$script_name" -o "$destination" 2>/dev/null && [[ -s "$destination" ]]; then
            chmod 700 "$destination"
            info "Archivo instalado en $destination"
            return 0
        fi
        rm -f "$destination"
    done

    error_msg "No se pudo descargar ningún script (${names[*]})."
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
    printf "  \033[0;32m🚀 Ejecutando %s...\033[0m\n\n" "$script_name"
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
        error_msg "No se pudo descargar el script ($primary)."
        return 1
    fi
}

caddy_menu() {
    prepare_for_external_script
    if command_exists caddy && (systemctl is-active --quiet caddy 2>/dev/null || pgrep -x caddy >/dev/null 2>&1); then
        if [[ -x /usr/local/bin/cadmin ]]; then /usr/local/bin/cadmin;
        elif [[ -x /usr/bin/cadmin ]]; then /usr/bin/cadmin;
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
    if command_exists nginx && (systemctl is-active --quiet nginx 2>/dev/null || pgrep -x nginx >/dev/null 2>&1); then
        if [[ -x /usr/local/bin/MenuN ]]; then /usr/local/bin/MenuN;
        elif [[ -x /usr/local/bin/menun ]]; then /usr/local/bin/menun;
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
        local sub_m
        read -r sub_m
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
    if [[ -x /usr/local/bin/menuv2ray ]]; then
        /usr/local/bin/menuv2ray
    elif [[ -x /usr/local/bin/v2ray-panel ]]; then
        /usr/local/bin/v2ray-panel
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
        local sub_op
        read -r sub_op
        sub_op=$(echo "$sub_op" | tr -d '\r\n\t ')

        case "$sub_op" in
            1|01)
                prepare_for_external_script
                info "Función adicional 1."
                pause_screen
                ;;
            2|02)
                prepare_for_external_script
                info "Función adicional 2."
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
    panel_header "SOCKS PROXY PYTHON" "🐍"
    if [[ -x /usr/local/bin/P-Proxy ]]; then
        /usr/local/bin/P-Proxy
    elif [[ -x /usr/local/bin/python-proxy ]]; then
        /usr/local/bin/python-proxy
    else
        execute_script "Python.sh" "python.sh" "proxy.sh"
    fi
    pause_screen
}

ssh_panel_menu() {
    prepare_for_external_script
    local ssh_panel="/usr/local/bin/sshpanel.sh"
    panel_header "SSH PANEL MANAGER" "👥"
    if download_to_path "$ssh_panel" "sshpanel.sh" "Sshpanel.sh" "ssh-panel.sh"; then
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
    printf "  \033[1;37mSistema    :\033[0m %s\n" "$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)"
    printf "  \033[1;37mMemoria    :\033[0m %s\n" "$(free -h | awk 'NR==2 {print $3 " / " $2}')"
    printf "  \033[1;37mDisco      :\033[0m %s\n" "$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    printf "  \033[1;37mUptime     :\033[0m %s\n" "$(uptime -p 2>/dev/null || echo N/A)"
    pause_screen
}

status_menu() {
    prepare_for_external_script
    panel_header "ESTADO GENERAL DE SERVICIOS" "📋"
    printf "  Caddy:        "; (systemctl is-active --quiet caddy 2>/dev/null || pgrep -x caddy >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  Nginx:        "; (systemctl is-active --quiet nginx 2>/dev/null || pgrep -x nginx >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  V2Ray:        "; (systemctl is-active --quiet v2ray 2>/dev/null || pgrep -f "v2ray" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  XRay:         "; (systemctl is-active --quiet xray 2>/dev/null || pgrep -f "xray" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  SSH-Go:       "; (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null || pgrep -f "vpn-proxy" >/dev/null 2>&1 || pgrep -f "ssh-go" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  UDP Panel:    "; (systemctl is-active --quiet udp-custom 2>/dev/null || systemctl is-active --quiet udp-hysteria 2>/dev/null || systemctl is-active --quiet zivpn 2>/dev/null || pgrep -f "udp-custom" >/dev/null 2>&1 || pgrep -f "zivpn" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  Socks Rust:   "; (systemctl is-active --quiet rust-proxy 2>/dev/null || systemctl is-active --quiet socks-rust 2>/dev/null || pgrep -f "socks-rust" >/dev/null 2>&1 || pgrep -f "rust-proxy" >/dev/null 2>&1 || [[ -n "$(get_rust_ports)" ]]) && info "ACTIVO" || warn "INACTIVO"
    printf "  Socks Python: "; (systemctl is-active --quiet python-proxy 2>/dev/null || pgrep -f "proxy.py" >/dev/null 2>&1 || pgrep -f "python-proxy" >/dev/null 2>&1 || pgrep -f "P-Proxy" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  BadVPN:       "; (pgrep -f badvpn-udpgw >/dev/null 2>&1 || systemctl is-active --quiet badvpn 2>/dev/null) && info "ACTIVO" || warn "INACTIVO"
    printf "  SlowDNS:      "; (systemctl is-active --quiet slowdns 2>/dev/null || systemctl is-active --quiet dns-server 2>/dev/null || pgrep -f "dns-server" >/dev/null 2>&1 || pgrep -f "slowdns" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    printf "  SSL/Stunnel:  "; (systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -f "stunnel" >/dev/null 2>&1) && info "ACTIVO" || warn "INACTIVO"
    pause_screen
}

main_menu() {
    while true; do
        setup_menu_shortcut
        render_ui "full"

        printf "\n"
        echo -ne "  \033[1;33m> Selecciona una opción [0-16]: \033[0m"
        local option
        read -r option
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
                printf "\n  \033[0;32m¡Gracias por usar Ariadny Master Panel!\033[0m\n\n"
                exit 0
                ;;
            *)
                warn "Opción inválida."
                sleep 1
                ;;
        esac
    done
}

require_root
install_dependencies
setup_menu_shortcut
main_menu "$@"
