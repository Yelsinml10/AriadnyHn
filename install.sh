#!/usr/bin/env bash

set -o pipefail

ESC='\033['
RESET="${ESC}0m"
BOLD="${ESC}1m"
DIM="${ESC}2m"
WHITE="${ESC}38;5;255m"
GRAY="${ESC}38;5;245m"
DARK="${ESC}38;5;238m"
PURPLE="${ESC}38;5;141m"
VIOLET="${ESC}38;5;99m"
CYAN="${ESC}38;5;51m"
BLUE="${ESC}38;5;75m"
GREEN="${ESC}38;5;48m"
YELLOW="${ESC}38;5;220m"
RED="${ESC}38;5;196m"

VERSION="PROFESSIONAL EDITION v2.1"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

clear_screen() {
    clear 2>/dev/null || printf '\033c'
}

pause_screen() {
    printf "\n  %bPresiona ENTER para continuar...%b" "$GRAY" "$RESET"
    read -r
    clear_screen
}

info() {
    printf "  %b✔%b %s\n" "$GREEN" "$RESET" "$1"
}

warn() {
    printf "  %b⚠%b %s\n" "$YELLOW" "$RESET" "$1"
}

error_msg() {
    printf "  %b✖%b %s\n" "$RED" "$RESET" "$1" >&2
}

line() {
    printf "  %b───────────────────────────────────────────%b\n" \
        "$DARK" "$RESET"
}

section_divider() {
    local title="$1"
    printf "  %b─ %s ───────────────────────%b\n" \
        "$PURPLE" "$title" "$RESET"
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

get_ports_summary() {
    ACTIVE_ITEMS=()

    # 1. Caddy
    if systemctl is-active --quiet caddy 2>/dev/null; then
        local c_http=$(get_caddy_ports_http 2>/dev/null)
        local c_https=$(get_caddy_ports_https 2>/dev/null)
        local all_caddy=$(echo "$c_http $c_https" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$all_caddy" ]]; then
            ACTIVE_ITEMS+=("🌐 Caddy  : $(truncate_str "$all_caddy")")
        fi
    fi

    # 2. V2Ray
    local v_cfg=$(get_v2ray_cfg_path)
    if [[ -f "$v_cfg" ]] && systemctl is-active --quiet v2ray 2>/dev/null; then
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
            fi
        fi
    fi

    # 5. UDP / Hysteria
    if systemctl is-active --quiet udp-custom 2>/dev/null || systemctl is-active --quiet udp-hysteria 2>/dev/null || systemctl is-active --quiet zivpn 2>/dev/null; then
        local u_p=$(get_udp_port)
        [[ -n "$u_p" ]] && ACTIVE_ITEMS+=("⚡ UDP    : $(truncate_str "$u_p")") || ACTIVE_ITEMS+=("⚡ UDP    : ON")
    fi

    # 6. Rust
    if systemctl is-active --quiet socks-proxy 2>/dev/null || systemctl is-active --quiet rust-proxy 2>/dev/null; then
        local r_p=$(get_socks_config_port)
        [[ -n "$r_p" ]] && ACTIVE_ITEMS+=("🦀 Rust   : $(truncate_str "$r_p")") || ACTIVE_ITEMS+=("🦀 Rust   : ON")
    fi

    # 7. Python
    if systemctl is-active --quiet python-proxy 2>/dev/null; then
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
            printf "  %b%-24s %s%b\n" "$CYAN" "$item1" "$item2" "$RESET"
            i=$((i+2))
        else
            printf "  %b%s%b\n" "$CYAN" "$item1" "$RESET"
            i=$((i+1))
        fi
    done
    printf "\n"
}

header() {
    clear_screen
    get_sys_info
    get_ports_summary
    printf "  %b🚀 ARIADNY MASTER PANEL %s%b\n" "$BOLD$WHITE" "$VERSION" "$RESET"
    printf "  %b%s%b • %b%s%b • %bRAM:%s%b\n\n" "$CYAN" "$IP_ADDR" "$RESET" "$CYAN" "$OS_INFO" "$RESET" "$GREEN" "$RAM_INFO" "$RESET"

    print_active_ports
}

panel_header() {
    local title="$1"
    local icon="${2:-◆}"

    header
    printf "  %b─ %s %s ───────────────────────────────%b\n\n" \
        "$PURPLE" "$icon" "$title" "$RESET"
}

download_to_path() {
    local script_name="$1"
    local destination="$2"

    printf "\n  %b⬇ Descargando %s...%b\n" "$CYAN" "$script_name" "$RESET"

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

    printf "\n  %b⬇ Descargando %s...%b\n" "$CYAN" "$script_name" "$RESET"

    if ! curl -fsSL --connect-timeout 15 --max-time 300 \
        "$BASE_URL/$script_name" -o "$temporary"; then
        error_msg "No se pudo descargar $script_name."
        rm -f "$temporary"
        return 1
    fi

    chmod 700 "$temporary"

    printf "  %b🚀 Ejecutando %s...%b\n\n" "$GREEN" "$script_name" "$RESET"

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

is_sshgo_installed() {
    [[ -f /opt/vpn-proxy/vpn-proxy || -f /opt/sshgo/vpn-proxy || -f /usr/bin/vpn-proxy ]] || systemctl is-active --quiet vpn-proxy 2>/dev/null
}

is_caddy_installed() {
    command_exists caddy || [[ -f /etc/caddy/Caddyfile ]]
}

is_v2ray_installed() {
    command_exists v2ray || [[ -f /usr/local/etc/v2ray/config.json || -f /etc/v2ray/config.json ]]
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

show_v2ray_status() {
    printf "\n  %bServicio V2Ray:%b " "$CYAN" "$RESET"
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        info "ACTIVO ✅"
    else
        warn "INACTIVO ❌"
    fi

    local cfg=$(get_v2ray_cfg_path)
    if [[ -f "$cfg" ]]; then
        local info_out=$(python3 -c '
import json, sys
cfg = sys.argv[1]
try:
    with open(cfg, "r") as f: data = json.load(f)
    inbounds = data.get("inbounds", [])
    if isinstance(data, dict) and "inbounds" not in data and "inbound" in data: inbounds = [data["inbound"]]
    ports, paths, uuids = set(), set(), set()
    for inb in inbounds:
        if "port" in inb: ports.add(str(inb["port"]))
        for c in inb.get("settings", {}).get("clients", []):
            if "id" in c: uuids.add(str(c["id"]))
        p = inb.get("streamSettings", {}).get("wsSettings", {}).get("path")
        if p: paths.add(str(p))
    print("PORTS|" + " ".join(sorted(ports)))
    print("PATHS|" + " ".join(sorted(paths)))
    print("UUIDS|" + " ".join(sorted(uuids)))
except Exception: pass
' "$cfg" 2>/dev/null)

        local ports=$(echo "$info_out" | grep '^PORTS|' | cut -d'|' -f2)
        local paths=$(echo "$info_out" | grep '^PATHS|' | cut -d'|' -f2)
        local uuids=$(echo "$info_out" | grep '^UUIDS|' | cut -d'|' -f2)

        printf "\n  %bPuertos configurados:%b " "$BLUE" "$RESET"
        [[ -n "$ports" ]] && echo "$ports" || warn "Ninguno"

        printf "  %bPaths configurados:%b " "$GREEN" "$RESET"
        [[ -n "$paths" ]] && echo "$paths" || warn "Ninguno"

        printf "\n  %bIDs / UUIDs registrados:%b\n" "$YELLOW" "$RESET"
        if [[ -n "$uuids" ]]; then
            for u in $uuids; do printf "    • %s\n" "$u"; done
        else
            warn "  No hay IDs registrados"
        fi
    else
        warn "\n  No se encontró config.json"
    fi
    echo ""
}

add_v2ray_id() {
    panel_header "AGREGAR ID / UUID V2RAY" "🔑"
    local cfg=$(get_v2ray_cfg_path)
    [[ ! -f "$cfg" ]] && { error_msg "V2Ray no está instalado"; pause_screen; return 1; }

    read -r -p "  Ingresa el nuevo UUID (ENTER para auto-generar): " new_uuid
    [[ -z "$new_uuid" ]] && new_uuid=$(python3 -c "import uuid; print(uuid.uuid4())")

    cp "$cfg" "${cfg}.bak" 2>/dev/null
    python3 -c '
import json, sys
cfg_path, new_id = sys.argv[1], sys.argv[2]
try:
    with open(cfg_path, "r") as f: data = json.load(f)
    for inb in data.get("inbounds", []):
        clients = inb.setdefault("settings", {}).setdefault("clients", [])
        if not any(c.get("id") == new_id for c in clients): clients.append({"id": new_id, "alterId": 0})
    with open(cfg_path, "w") as f: json.dump(data, f, indent=4)
except Exception: sys.exit(1)
' "$cfg" "$new_uuid"

    [[ $? -eq 0 ]] && { systemctl restart v2ray 2>/dev/null; info "UUID registrado: $new_uuid"; } || error_msg "Error al agregar UUID"
    pause_screen
}

remove_v2ray_id() {
    panel_header "QUITAR ID / UUID V2RAY" "🔑"
    local cfg=$(get_v2ray_cfg_path)
    [[ ! -f "$cfg" ]] && { error_msg "V2Ray no está instalado"; pause_screen; return 1; }

    local info_out=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    uuids = set()
    for inb in data.get("inbounds", []):
        for c in inb.get("settings", {}).get("clients", []):
            if "id" in c: uuids.add(c["id"])
    print(" ".join(uuids))
except Exception: pass
' "$cfg" 2>/dev/null)

    local uuids=($info_out)
    [[ ${#uuids[@]} -eq 0 ]] && { warn "No hay UUIDs configurados"; pause_screen; return 1; }

    echo "  IDs actuales:"
    local i=1
    for u in "${uuids[@]}"; do printf "  %b[%d]%b %s\n" "$CYAN" "$i" "$RESET" "$u"; ((i++)); done
    echo ""

    read -r -p "  Selecciona número a quitar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#uuids[@]} ]]; then
        error_msg "Selección inválida"; pause_screen; return 1
    fi

    local rem_uuid=${uuids[$selection-1]}
    cp "$cfg" "${cfg}.bak" 2>/dev/null
    python3 -c '
import json, sys
cfg_path, rem_id = sys.argv[1], sys.argv[2]
try:
    with open(cfg_path, "r") as f: data = json.load(f)
    for inb in data.get("inbounds", []):
        inb["settings"]["clients"] = [c for c in inb.get("settings", {}).get("clients", []) if c.get("id") != rem_id]
    with open(cfg_path, "w") as f: json.dump(data, f, indent=4)
except Exception: sys.exit(1)
' "$cfg" "$rem_uuid"

    [[ $? -eq 0 ]] && { systemctl restart v2ray 2>/dev/null; info "ID $rem_uuid eliminado"; } || error_msg "Error al eliminar"
    pause_screen
}

change_v2ray_path() {
    panel_header "CAMBIAR PATH V2RAY" "🔀"
    local cfg=$(get_v2ray_cfg_path)
    [[ ! -f "$cfg" ]] && { error_msg "V2Ray no está instalado"; pause_screen; return 1; }

    read -r -p "  Ingresa el nuevo Path (ej: /v2ray): " new_path
    [[ -z "$new_path" ]] && { error_msg "Path no puede estar vacío"; pause_screen; return 1; }
    [[ "$new_path" != /* ]] && new_path="/$new_path"

    cp "$cfg" "${cfg}.bak" 2>/dev/null
    python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    for inb in data.get("inbounds", []):
        if "wsSettings" in inb.get("streamSettings", {}):
            inb["streamSettings"]["wsSettings"]["path"] = sys.argv[2]
    with open(sys.argv[1], "w") as f: json.dump(data, f, indent=4)
except Exception: sys.exit(1)
' "$cfg" "$new_path"

    [[ $? -eq 0 ]] && { systemctl restart v2ray 2>/dev/null; info "Path cambiado a $new_path"; } || error_msg "Error al actualizar"
    pause_screen
}

change_v2ray_port() {
    panel_header "CAMBIAR PUERTO V2RAY" "🔌"
    local cfg=$(get_v2ray_cfg_path)
    [[ ! -f "$cfg" ]] && { error_msg "V2Ray no está instalado"; pause_screen; return 1; }

    read -r -p "  Nuevo puerto: " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        error_msg "Puerto inválido"; pause_screen; return 1
    fi

    cp "$cfg" "${cfg}.bak" 2>/dev/null
    python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    for inb in data.get("inbounds", []): inb["port"] = int(sys.argv[2])
    with open(sys.argv[1], "w") as f: json.dump(data, f, indent=4)
except Exception: sys.exit(1)
' "$cfg" "$new_port"

    [[ $? -eq 0 ]] && { systemctl restart v2ray 2>/dev/null; info "Puerto cambiado a $new_port"; } || error_msg "Error al cambiar puerto"
    pause_screen
}

restart_v2ray() {
    panel_header "REINICIAR V2RAY" "🔄"
    systemctl restart v2ray 2>/dev/null
    systemctl is-active --quiet v2ray 2>/dev/null && info "V2Ray reiniciado" || error_msg "Error al reiniciar"
    pause_screen
}

uninstall_v2ray() {
    panel_header "DESINSTALAR V2RAY" "🗑️"
    read -r -p "  ¿Seguro desinstalar V2Ray? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop v2ray 2>/dev/null; systemctl disable v2ray 2>/dev/null
        rm -rf /usr/local/etc/v2ray /etc/v2ray /usr/local/bin/v2ray /usr/bin/v2ray /etc/systemd/system/v2ray.service
        systemctl daemon-reload
        info "V2Ray desinstalado"
    else warn "Cancelado"; fi
    pause_screen
}

install_v2ray_direct() {
    panel_header "INSTALANDO V2RAY DESDE GITHUB" "⚡"
    is_v2ray_installed && { warn "V2Ray ya está instalado"; pause_screen; return 0; }
    download_and_execute "install-v2ray.sh"
    is_v2ray_installed && info "V2Ray instalado correctamente" || error_msg "Error en instalación"
    pause_screen
}

get_sshgo_cfg_path() {
    for path in /opt/vpn-proxy/config.json /etc/vpn-proxy/config.json /etc/ssh-go/config.json /opt/sshgo/config.json; do
        [[ -f "$path" ]] && { echo "$path"; return 0; }
    done
    echo "/opt/vpn-proxy/config.json"
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

show_sshgo_status() {
    printf "\n  %bServicio SSH-Go:%b " "$CYAN" "$RESET"
    systemctl is-active --quiet vpn-proxy 2>/dev/null && info "ACTIVO ✅" || warn "INACTIVO ❌"
    printf "\n  %bPuertos activos:%b\n" "$BLUE" "$RESET"
    local ports=($(get_sshgo_ports))
    if [[ ${#ports[@]} -gt 0 ]]; then
        for port in "${ports[@]}"; do printf "    • Puerto %s\n" "$port"; done
    else warn "  No hay puertos configurados"; fi
    echo ""
}

add_sshgo_port() {
    panel_header "AGREGAR PUERTO SSH-GO" "🔌"
    local cfg=$(get_sshgo_cfg_path)
    mkdir -p "$(dirname "$cfg")"
    [[ ! -f "$cfg" ]] && echo '{"port": []}' > "$cfg"

    read -r -p "  Ingresa el número de puerto: " port
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"; pause_screen; return 1
    fi

    cp "$cfg" "${cfg}.bak" 2>/dev/null
    python3 -c '
import json, sys
cfg_path, new_port = sys.argv[1], int(sys.argv[2])
try:
    try:
        with open(cfg_path, "r") as f: data = json.load(f)
    except Exception: data = {}
    ports = data.get("port", [])
    if isinstance(ports, int): ports = [ports]
    if new_port not in ports: ports.append(new_port)
    data["port"] = ports
    with open(cfg_path, "w") as f: json.dump(data, f, indent=4)
except Exception: sys.exit(1)
' "$cfg" "$port"

    [[ $? -eq 0 ]] && { systemctl restart vpn-proxy 2>/dev/null; info "Puerto $port agregado"; } || error_msg "Error al modificar"
    pause_screen
}

remove_sshgo_port() {
    panel_header "QUITAR PUERTO SSH-GO" "🔌"
    local cfg=$(get_sshgo_cfg_path)
    local ports=($(get_sshgo_ports))
    [[ ${#ports[@]} -eq 0 ]] && { warn "No hay puertos configurados"; pause_screen; return 1; }

    echo "  Puertos activos:"
    local i=1
    for port in "${ports[@]}"; do printf "  %b[%d]%b Puerto %s\n" "$CYAN" "$i" "$RESET" "$port"; ((i++)); done
    echo ""

    read -r -p "  Selecciona número a quitar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#ports[@]} ]]; then
        error_msg "Selección inválida"; pause_screen; return 1
    fi

    local port_to_remove=${ports[$selection-1]}
    cp "$cfg" "${cfg}.bak" 2>/dev/null
    python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    p = data.get("port", [])
    if isinstance(p, list) and int(sys.argv[2]) in p: p.remove(int(sys.argv[2]))
    data["port"] = p
    with open(sys.argv[1], "w") as f: json.dump(data, f, indent=4)
except Exception: sys.exit(1)
' "$cfg" "$port_to_remove"

    [[ $? -eq 0 ]] && { systemctl restart vpn-proxy 2>/dev/null; info "Puerto $port_to_remove eliminado"; } || error_msg "Error al actualizar"
    pause_screen
}

restart_sshgo() {
    panel_header "REINICIAR SSH-GO" "🔄"
    systemctl restart vpn-proxy 2>/dev/null || systemctl restart ssh-go 2>/dev/null
    systemctl is-active --quiet vpn-proxy 2>/dev/null && info "SSH-Go reiniciado" || error_msg "Error al reiniciar"
    pause_screen
}

uninstall_sshgo() {
    panel_header "DESINSTALAR SSH-GO" "🗑️"
    read -r -p "  ¿Seguro desinstalar SSH-Go? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop vpn-proxy 2>/dev/null; systemctl disable vpn-proxy 2>/dev/null
        rm -rf /opt/vpn-proxy /opt/sshgo /etc/systemd/system/vpn-proxy.service
        systemctl daemon-reload
        info "SSH-Go desinstalado"
    else warn "Cancelado"; fi
    pause_screen
}

install_sshgo_direct() {
    panel_header "INSTALANDO SSH-GO DESDE GITHUB" "🚀"
    is_sshgo_installed && { warn "SSH-Go ya está instalado"; pause_screen; return 0; }
    download_and_execute "install-sshgo.sh"
    is_sshgo_installed && info "SSH-Go instalado correctamente" || error_msg "Error en instalación"
    pause_screen
}

get_caddy_domains() {
    python3 -c '
import os, re
caddyfile = "/etc/caddy/Caddyfile"
domains = set()
if os.path.exists(caddyfile):
    with open(caddyfile, "r") as f:
        for match in re.finditer(r"([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})", f.read()):
            domains.add(match.group(1))
if domains: print("\n".join(sorted(domains)))
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

show_caddy_status() {
    printf "\n  %bServicio Caddy:%b " "$CYAN" "$RESET"
    systemctl is-active --quiet caddy 2>/dev/null && info "ACTIVO ✅" || warn "INACTIVO ❌"
    printf "\n  %bDominios configurados:%b\n" "$BLUE" "$RESET"
    local domains=$(get_caddy_domains)
    if [[ -n "$domains" ]]; then
        while IFS= read -r domain; do [[ -n "$domain" ]] && printf "    • %s\n" "$domain"; done <<< "$domains"
    else warn "  No hay dominios configurados"; fi
    echo ""
}

change_caddy_domain() {
    panel_header "CAMBIAR DOMINIO CADDY" "🌐"
    [[ ! -f /etc/caddy/Caddyfile ]] && { error_msg "Caddy no está instalado"; pause_screen; return 1; }
    local domains=($(get_caddy_domains))
    [[ ${#domains[@]} -eq 0 ]] && { warn "No hay dominios configurados"; pause_screen; return 1; }

    echo "  Dominios actuales:"
    local i=1
    for domain in "${domains[@]}"; do printf "  %b[%d]%b %s\n" "$CYAN" "$i" "$RESET" "$domain"; ((i++)); done
    echo ""

    read -r -p "  Selecciona el dominio a cambiar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#domains[@]} ]]; then
        error_msg "Selección inválida"; pause_screen; return 1
    fi

    local old_domain=${domains[$selection-1]}
    read -r -p "  Nuevo dominio: " new_domain
    [[ -z "$new_domain" ]] && { error_msg "Dominio vacío"; pause_screen; return 1; }

    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    sed -i "s/$old_domain/$new_domain/g" /etc/caddy/Caddyfile
    systemctl restart caddy
    info "Dominio cambiado a $new_domain"
    pause_screen
}

add_caddy_http_port() {
    panel_header "AGREGAR PUERTO HTTP CADDY" "🔌"
    mkdir -p /etc/caddy
    [[ ! -f /etc/caddy/Caddyfile ]] && echo -e ":80 {\n    respond \"Caddy\"\n}" > /etc/caddy/Caddyfile

    read -r -p "  Puerto HTTP: " port
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"; pause_screen; return 1
    fi

    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    echo -e "\n:$port {\n    respond \"Caddy HTTP Port $port\"\n}" >> /etc/caddy/Caddyfile
    systemctl restart caddy
    info "Puerto HTTP $port agregado"
    pause_screen
}

add_caddy_https_port() {
    panel_header "AGREGAR PUERTO HTTPS CADDY" "🔒"
    mkdir -p /etc/caddy
    [[ ! -f /etc/caddy/Caddyfile ]] && echo -e ":80 {\n    respond \"Caddy\"\n}" > /etc/caddy/Caddyfile

    read -r -p "  Puerto HTTPS: " port
    local current_domain=$(get_caddy_domains | head -1)
    [[ -z "$current_domain" ]] && read -r -p "  Dominio: " current_domain
    [[ -z "$current_domain" ]] && { error_msg "Dominio requerido"; pause_screen; return 1; }

    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    echo -e "\n${current_domain}:${port} {\n    respond \"Caddy HTTPS Port $port\"\n}" >> /etc/caddy/Caddyfile
    systemctl restart caddy
    info "Puerto HTTPS $port agregado para $current_domain"
    pause_screen
}

remove_caddy_port() {
    panel_header "QUITAR PUERTO CADDY" "🔌"
    [[ ! -f /etc/caddy/Caddyfile ]] && { warn "Caddy no está instalado"; pause_screen; return 1; }
    local http_ports=($(get_caddy_ports_http))
    local https_ports=($(get_caddy_ports_https))
    local all_ports=("${http_ports[@]}" "${https_ports[@]}")
    local unique_ports=($(echo "${all_ports[@]}" | tr ' ' '\n' | sort -u))
    [[ ${#unique_ports[@]} -eq 0 ]] && { warn "No hay puertos configurados"; pause_screen; return 1; }

    echo "  Puertos disponibles:"
    local i=1
    for port in "${unique_ports[@]}"; do printf "  %b[%d]%b Puerto %s\n" "$CYAN" "$i" "$RESET" "$port"; ((i++)); done
    echo ""

    read -r -p "  Selecciona número a quitar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#unique_ports[@]} ]]; then
        error_msg "Selección inválida"; pause_screen; return 1
    fi

    local port_to_remove=${unique_ports[$selection-1]}
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    python3 -c '
import re, sys
caddyfile = "/etc/caddy/Caddyfile"
port = sys.argv[1]
try:
    with open(caddyfile, "r") as f: content = f.read()
    pattern = r"(?m)^\s*(?:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})?:" + port + r"\s*\{[^}]*\}"
    content = re.sub(pattern, "", content)
    with open(caddyfile, "w") as f: f.write(content)
except Exception: sys.exit(1)
' "$port_to_remove"

    systemctl restart caddy
    info "Puerto $port_to_remove eliminado"
    pause_screen
}

restart_caddy() {
    panel_header "REINICIAR CADDY" "🔄"
    systemctl restart caddy
    systemctl is-active --quiet caddy && info "Caddy reiniciado" || error_msg "Error al reiniciar"
    pause_screen
}

uninstall_caddy() {
    panel_header "DESINSTALAR CADDY" "🗑️"
    read -r -p "  ¿Seguro desinstalar Caddy? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop caddy 2>/dev/null; systemctl disable caddy 2>/dev/null
        apt remove -y caddy 2>/dev/null || yum remove -y caddy 2>/dev/null
        rm -rf /etc/caddy /etc/systemd/system/caddy.service
        systemctl daemon-reload
        info "Caddy desinstalado"
    else warn "Cancelado"; fi
    pause_screen
}

install_caddy_direct() {
    panel_header "INSTALANDO CADDY DESDE GITHUB" "🌐"
    is_caddy_installed && { warn "Caddy ya está instalado"; pause_screen; return 0; }
    download_and_execute "install-caddy.sh"
    is_caddy_installed && info "Caddy instalado correctamente" || error_msg "Error en instalación"
    pause_screen
}

v2ray_admin_menu() {
    while true; do
        panel_header "PANEL V2RAY / VMESS" "⚡"
        show_v2ray_status
        printf "  %b[1]%b  Instalar V2Ray\n" "$GREEN" "$RESET"
        printf "  %b[2]%b  Agregar ID (UUID)\n" "$CYAN" "$RESET"
        printf "  %b[3]%b  Quitar ID (UUID)\n" "$CYAN" "$RESET"
        printf "  %b[4]%b  Cambiar Path\n" "$CYAN" "$RESET"
        printf "  %b[5]%b  Cambiar Puerto\n" "$CYAN" "$RESET"
        printf "  %b[6]%b  Reiniciar V2Ray\n" "$CYAN" "$RESET"
        printf "  %b[7]%b  Desinstalar V2Ray\n" "$RED" "$RESET"
        printf "  %b[0]%b  Volver\n\n" "$GRAY" "$RESET"
        read -r -p "  ❯ Selecciona una opción: " option
        case "$option" in
            1) install_v2ray_direct ;; 2) add_v2ray_id ;; 3) remove_v2ray_id ;;
            4) change_v2ray_path ;; 5) change_v2ray_port ;; 6) restart_v2ray ;;
            7) uninstall_v2ray ;; 0) clear_screen; break ;; *) warn "Opción inválida"; sleep 1 ;;
        esac
    done
}

sshgo_admin_menu() {
    while true; do
        panel_header "PANEL SSH-GO PROXY" "🚀"
        show_sshgo_status
        printf "  %b[1]%b  Instalar SSH-Go\n" "$GREEN" "$RESET"
        printf "  %b[2]%b  Agregar puerto\n" "$CYAN" "$RESET"
        printf "  %b[3]%b  Quitar puerto\n" "$CYAN" "$RESET"
        printf "  %b[4]%b  Reiniciar SSH-Go\n" "$CYAN" "$RESET"
        printf "  %b[5]%b  Desinstalar SSH-Go\n" "$RED" "$RESET"
        printf "  %b[0]%b  Volver\n\n" "$GRAY" "$RESET"
        read -r -p "  ❯ Selecciona una opción: " option
        case "$option" in
            1) install_sshgo_direct ;; 2) add_sshgo_port ;; 3) remove_sshgo_port ;;
            4) restart_sshgo ;; 5) uninstall_sshgo ;; 0) clear_screen; break ;; *) warn "Opción inválida"; sleep 1 ;;
        esac
    done
}

caddy_admin_menu() {
    while true; do
        panel_header "PANEL CADDY SERVER" "🌐"
        show_caddy_status
        printf "  %b[1]%b  Instalar Caddy\n" "$GREEN" "$RESET"
        printf "  %b[2]%b  Cambiar dominio\n" "$CYAN" "$RESET"
        printf "  %b[3]%b  Agregar puerto HTTP\n" "$CYAN" "$RESET"
        printf "  %b[4]%b  Agregar puerto HTTPS\n" "$CYAN" "$RESET"
        printf "  %b[5]%b  Quitar puerto\n" "$CYAN" "$RESET"
        printf "  %b[6]%b  Reiniciar Caddy\n" "$CYAN" "$RESET"
        printf "  %b[7]%b  Desinstalar Caddy\n" "$RED" "$RESET"
        printf "  %b[0]%b  Volver\n\n" "$GRAY" "$RESET"
        read -r -p "  ❯ Selecciona una opción: " option
        case "$option" in
            1) install_caddy_direct ;; 2) change_caddy_domain ;; 3) add_caddy_http_port ;;
            4) add_caddy_https_port ;; 5) remove_caddy_port ;; 6) restart_caddy ;;
            7) uninstall_caddy ;; 0) clear_screen; break ;; *) warn "Opción inválida"; sleep 1 ;;
        esac
    done
}

caddy_menu() { is_caddy_installed || install_caddy_direct; caddy_admin_menu; }
sshgo_menu() { is_sshgo_installed || install_sshgo_direct; sshgo_admin_menu; }
v2ray_menu() { is_v2ray_installed || install_v2ray_direct; v2ray_admin_menu; }

firewall_menu() {
    local firewall="/usr/local/bin/firewall.sh"
    panel_header "FIREWALL" "🛡️"
    if [[ ! -x "$firewall" ]]; then
        warn "Firewall no instalado."
        download_to_path "firewall.sh" "$firewall" && "$firewall"
    else info "Firewall ya instalado."; "$firewall"; fi
    pause_screen
}

xray_menu() {
    panel_header "XRAY PANEL" "🔰"
    if [[ ! -x /usr/local/bin/xray && ! -x /usr/local/bin/v2ray && ! -x /usr/bin/xray && ! -x /usr/bin/v2ray ]]; then
        warn "XRay no instalado."
        download_and_execute "xray.sh"
    else
        info "XRay/V2Ray ya instalado."
        command -v menuV2 >/dev/null 2>&1 && menuV2 || warn "menuV2 no disponible"
    fi
    pause_screen
}

udp_menu() {
    panel_header "UDP PANEL" "⚡"
    if [[ ! -f /usr/bin/menuUDP && ! -x /usr/local/bin/menuUDP && ! -d /etc/hysteria ]]; then
        warn "UDP no instalado."
        download_and_execute "Udp.sh"
    else
        info "UDP ya instalado."
        if [[ -x /usr/bin/menuUDP ]]; then /usr/bin/menuUDP;
        elif [[ -x /usr/local/bin/menuUDP ]]; then /usr/local/bin/menuUDP;
        else systemctl status udp-hysteria udp-custom zivpn --no-pager 2>/dev/null || true; fi
    fi
    pause_screen
}

rust_menu() { panel_header "SOCKS PROXY RUST" "🦀"; download_and_execute "rust.sh"; pause_screen; }
python_menu() { panel_header "SOCKS PROXY PYTHON" "🐍"; download_and_execute "Python.sh"; pause_screen; }

ssh_panel_menu() {
    local ssh_panel="/usr/local/bin/sshpanel.sh"
    panel_header "SSH PANEL" "👥"
    printf "  %bDescargando panel SSH...%b\n" "$CYAN" "$RESET"
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
    printf "  Caddy:   "; systemctl is-active --quiet caddy 2>/dev/null && info "ACTIVO" || warn "INACTIVO"
    printf "  V2Ray:   "; systemctl is-active --quiet v2ray 2>/dev/null && info "ACTIVO" || warn "INACTIVO"
    printf "  SSH-Go:  "; (systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null) && info "ACTIVO" || warn "INACTIVO"
    pause_screen
}

main_menu() {
    while true; do
        header

        section_divider "PROTOCOLOS & PROXIES"
        printf "  %b[ 1]%b 🌐 Caddy Server       %b[ 2]%b ⚡ V2Ray / VMess\n" "$CYAN" "$RESET" "$CYAN" "$RESET"
        printf "  %b[ 3]%b 🚀 SSH-Go Proxy       %b[ 4]%b 🔰 XRay Panel\n" "$CYAN" "$RESET" "$CYAN" "$RESET"
        printf "  %b[ 5]%b ⚡ UDP Panel          %b[ 6]%b 🦀 SOCKS Proxy Rust\n" "$CYAN" "$RESET" "$CYAN" "$RESET"
        printf "  %b[ 7]%b 🐍 SOCKS Proxy Python %b[ 8]%b 👥 SSH Panel / User\n\n" "$CYAN" "$RESET" "$CYAN" "$RESET"

        section_divider "GESTIÓN & MANTENIMIENTO"
        printf "  %b[ 9]%b 🛡️  Firewall           %b[10]%b 🔐 Configurar SSH\n" "$CYAN" "$RESET" "$CYAN" "$RESET"
        printf "  %b[11]%b 📊 Monitoreo Sistema   %b[12]%b 📋 Estado General\n" "$BLUE" "$RESET" "$BLUE" "$RESET"
        printf "  %b[ 0]%b 🚪 Salir del Panel\n" "$RED" "$RESET"

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
                printf "\n  %b¡Gracias por usar el panel VPN!%b\n\n" "$GREEN" "$RESET"
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
EOF

chmod +x /usr/local/bin/menu
cp /usr/local/bin/menu /usr/bin/menu 2>/dev/null
chmod +x /usr/bin/menu 2>/dev/null
