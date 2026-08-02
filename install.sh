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
    printf "  %b─ %s ───────────────────────────────%b\n" \
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
    
    RAM_INFO=$(free -h 2>/dev/null | awk 'NR==2 {print $3 " / " $2}')
    [[ -z "$RAM_INFO" ]] && RAM_INFO="N/A"
    
    OS_INFO=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null | cut -d' ' -f1,2)
    [[ -z "$OS_INFO" ]] && OS_INFO="Linux"
}

get_ports_summary() {
    # Puertos SSH-Go
    SSHGO_PORTS_RAW=$(get_sshgo_ports 2>/dev/null)
    if [[ -n "$SSHGO_PORTS_RAW" ]]; then
        SSHGO_PORTS_DISPLAY=$(echo "$SSHGO_PORTS_RAW" | tr ' ' ',')
    else
        SSHGO_PORTS_DISPLAY="OFF"
    fi

    # Puertos V2Ray
    local cfg=$(get_v2ray_cfg_path)
    V2RAY_PORTS_DISPLAY="OFF"
    if [[ -f "$cfg" ]] && systemctl is-active --quiet v2ray 2>/dev/null; then
        local v_out=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: data = json.load(f)
    inbounds = data.get("inbounds", [])
    if isinstance(data, dict) and "inbounds" not in data and "inbound" in data: inbounds = [data["inbound"]]
    ports = sorted(list(set(str(inb["port"]) for inb in inbounds if "port" in inb)))
    print(",".join(ports))
except Exception: pass
' "$cfg" 2>/dev/null)
        [[ -n "$v_out" ]] && V2RAY_PORTS_DISPLAY="$v_out"
    fi

    # Puertos Caddy
    CADDY_PORTS_DISPLAY="OFF"
    if systemctl is-active --quiet caddy 2>/dev/null; then
        local c_http=$(get_caddy_ports_http 2>/dev/null)
        local c_https=$(get_caddy_ports_https 2>/dev/null)
        local all_caddy=$(echo "$c_http $c_https" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
        [[ -n "$all_caddy" ]] && CADDY_PORTS_DISPLAY="$all_caddy"
    fi

    # Puerto SSH Sistema
    SSH_PORT_DISPLAY="22"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_p=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
        [[ -n "$ssh_p" ]] && SSH_PORT_DISPLAY="$ssh_p"
    fi
}

header() {
    clear_screen
    get_sys_info
    get_ports_summary
    printf "\n"
    printf "  %b🚀 ARIADNY MASTER PANEL %s%b\n" "$BOLD$WHITE" "$VERSION" "$RESET"
    printf "  %b%s%b • %b%s%b • %bRAM: %s%b\n\n" "$CYAN" "$IP_ADDR" "$RESET" "$CYAN" "$OS_INFO" "$RESET" "$GREEN" "$RAM_INFO" "$RESET"

    section_divider "PUERTOS ACTIVOS"
    printf "  %b🌐 Caddy  :%b %-16s %b⚡ V2Ray :%b %s\n" "$CYAN" "$RESET" "$CADDY_PORTS_DISPLAY" "$CYAN" "$RESET" "$V2RAY_PORTS_DISPLAY"
    printf "  %b🚀 SSH-Go :%b %-16s %b🔐 SSH   :%b %s\n\n" "$CYAN" "$RESET" "$SSHGO_PORTS_DISPLAY" "$CYAN" "$RESET" "$SSH_PORT_DISPLAY"
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

# ==============================================================================
# VERIFICACIONES DE INSTALACIÓN
# ==============================================================================

is_sshgo_installed() {
    [[ -f /opt/vpn-proxy/vpn-proxy || -f /opt/sshgo/vpn-proxy || -f /usr/bin/vpn-proxy ]] || systemctl is-active --quiet vpn-proxy 2>/dev/null
}

is_caddy_installed() {
    command_exists caddy || [[ -f /etc/caddy/Caddyfile ]]
}

is_v2ray_installed() {
    command_exists v2ray || [[ -f /usr/local/etc/v2ray/config.json || -f /etc/v2ray/config.json ]]
}

# ==============================================================================
# FUNCIONES PARA V2RAY
# ==============================================================================

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
    with open(cfg, "r") as f:
        data = json.load(f)
    inbounds = data.get("inbounds", [])
    if isinstance(data, dict) and "inbounds" not in data and "inbound" in data:
        inbounds = [data["inbound"]]
    ports, paths, uuids = set(), set(), set()
    for inb in inbounds:
        if "port" in inb: ports.add(str(inb["port"]))
        clients = inb.get("settings", {}).get("clients", [])
        for c in clients:
            if "id" in c: uuids.add(str(c["id"]))
        p = inb.get("streamSettings", {}).get("wsSettings", {}).get("path")
        if p: paths.add(str(p))
    print("PORTS|" + " ".join(sorted(ports)))
    print("PATHS|" + " ".join(sorted(paths)))
    print("UUIDS|" + " ".join(sorted(uuids)))
except Exception:
    pass
' "$cfg" 2>/dev/null)

        local ports=$(echo "$info_out" | grep '^PORTS|' | cut -d'|' -f2)
        local paths=$(echo "$info_out" | grep '^PATHS|' | cut -d'|' -f2)
        local uuids=$(echo "$info_out" | grep '^UUIDS|' | cut -d'|' -f2)

        printf "\n  %bPuertos configurados:%b " "$BLUE" "$RESET"
        if [[ -n "$ports" ]]; then
            echo "$ports"
        else
            warn "Ninguno"
        fi

        printf "  %bPaths configurados:%b " "$GREEN" "$RESET"
        if [[ -n "$paths" ]]; then
            echo "$paths"
        else
            warn "Ninguno"
        fi

        printf "\n  %bIDs / UUIDs registrados:%b\n" "$YELLOW" "$RESET"
        if [[ -n "$uuids" ]]; then
            for u in $uuids; do
                printf "    • %s\n" "$u"
            done
        else
            warn "  No hay IDs registrados"
        fi
    else
        warn "\n  No se encontró el archivo de configuración config.json"
    fi
    echo ""
}

add_v2ray_id() {
    panel_header "AGREGAR ID / UUID V2RAY" "🔑"
    
    local cfg=$(get_v2ray_cfg_path)
    if [[ ! -f "$cfg" ]]; then
        error_msg "V2Ray no está instalado o no se encuentra config.json"
        pause_screen
        return 1
    fi

    local new_uuid
    read -r -p "  Ingresa el nuevo UUID (ENTER para auto-generar): " new_uuid
    if [[ -z "$new_uuid" ]]; then
        new_uuid=$(python3 -c "import uuid; print(uuid.uuid4())")
    fi

    cp "$cfg" "${cfg}.bak" 2>/dev/null

    python3 -c "
import json, sys
cfg_path, new_id = sys.argv[1], sys.argv[2]
try:
    with open(cfg_path, 'r') as f:
        data = json.load(f)
    inbounds = data.get('inbounds', [])
    added = False
    for inb in inbounds:
        if 'settings' in inb:
            if 'clients' not in inb['settings']:
                inb['settings']['clients'] = []
            clients = inb['settings']['clients']
            if not any(c.get('id') == new_id for c in clients):
                clients.append({'id': new_id, 'alterId': 0})
                added = True
    if added:
        with open(cfg_path, 'w') as f:
            json.dump(data, f, indent=4)
    else:
        sys.exit(0)
except Exception:
    sys.exit(1)
" "$cfg" "$new_uuid"

    if [[ $? -eq 0 ]]; then
        systemctl restart v2ray 2>/dev/null
        info "UUID registrado exitosamente: $new_uuid"
    else
        error_msg "Ocurrió un error al agregar el UUID"
    fi
    pause_screen
}

remove_v2ray_id() {
    panel_header "QUITAR ID / UUID V2RAY" "🔑"
    
    local cfg=$(get_v2ray_cfg_path)
    if [[ ! -f "$cfg" ]]; then
        error_msg "V2Ray no está instalado"
        pause_screen
        return 1
    fi

    local info_out=$(python3 -c '
import json, sys
cfg = sys.argv[1]
try:
    with open(cfg, "r") as f:
        data = json.load(f)
    uuids = []
    for inb in data.get("inbounds", []):
        for c in inb.get("settings", {}).get("clients", []):
            if "id" in c and c["id"] not in uuids:
                uuids.append(c["id"])
    print(" ".join(uuids))
except Exception:
    pass
' "$cfg" 2>/dev/null)

    local uuids=($info_out)
    if [[ ${#uuids[@]} -eq 0 ]]; then
        warn "No hay UUIDs configurados para eliminar"
        pause_screen
        return 1
    fi

    echo "  IDs / UUIDs actuales:"
    local i=1
    for u in "${uuids[@]}"; do
        printf "  %b[%d]%b %s\n" "$CYAN" "$i" "$RESET" "$u"
        ((i++))
    done
    echo ""

    read -r -p "  Selecciona el número de ID a quitar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#uuids[@]} ]]; then
        error_msg "Selección inválida"
        pause_screen
        return 1
    fi

    local rem_uuid=${uuids[$selection-1]}
    cp "$cfg" "${cfg}.bak" 2>/dev/null

    python3 -c "
import json, sys
cfg_path, rem_id = sys.argv[1], sys.argv[2]
try:
    with open(cfg_path, 'r') as f:
        data = json.load(f)
    inbounds = data.get('inbounds', [])
    for inb in inbounds:
        clients = inb.get('settings', {}).get('clients', [])
        inb['settings']['clients'] = [c for c in clients if c.get('id') != rem_id]
    with open(cfg_path, 'w') as f:
        json.dump(data, f, indent=4)
except Exception:
    sys.exit(1)
" "$cfg" "$rem_uuid"

    if [[ $? -eq 0 ]]; then
        systemctl restart v2ray 2>/dev/null
        info "ID $rem_uuid eliminado correctamente"
    else
        error_msg "Error al eliminar el ID"
    fi
    pause_screen
}

change_v2ray_path() {
    panel_header "CAMBIAR PATH V2RAY" "🔀"
    
    local cfg=$(get_v2ray_cfg_path)
    if [[ ! -f "$cfg" ]]; then
        error_msg "V2Ray no está instalado"
        pause_screen
        return 1
    fi

    read -r -p "  Ingresa el nuevo Path (ej: /v2ray o /vmess): " new_path
    if [[ -z "$new_path" ]]; then
        error_msg "El Path no puede estar vacío"
        pause_screen
        return 1
    fi

    if [[ "$new_path" != /* ]]; then
        new_path="/$new_path"
    fi

    cp "$cfg" "${cfg}.bak" 2>/dev/null

    python3 -c "
import json, sys
cfg_path, n_path = sys.argv[1], sys.argv[2]
try:
    with open(cfg_path, 'r') as f:
        data = json.load(f)
    for inb in data.get('inbounds', []):
        stream = inb.get('streamSettings', {})
        if 'wsSettings' in stream:
            stream['wsSettings']['path'] = n_path
    with open(cfg_path, 'w') as f:
        json.dump(data, f, indent=4)
except Exception:
    sys.exit(1)
" "$cfg" "$new_path"

    if [[ $? -eq 0 ]]; then
        systemctl restart v2ray 2>/dev/null
        info "Path cambiado a $new_path correctamente"
    else
        error_msg "Error al actualizar el Path"
    fi
    pause_screen
}

change_v2ray_port() {
    panel_header "CAMBIAR PUERTO V2RAY" "🔌"
    
    local cfg=$(get_v2ray_cfg_path)
    if [[ ! -f "$cfg" ]]; then
        error_msg "V2Ray no está instalado"
        pause_screen
        return 1
    fi

    read -r -p "  Ingresa el nuevo puerto (ej: 10086): " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        pause_screen
        return 1
    fi

    cp "$cfg" "${cfg}.bak" 2>/dev/null

    python3 -c "
import json, sys
cfg_path, n_port = sys.argv[1], int(sys.argv[2])
try:
    with open(cfg_path, 'r') as f:
        data = json.load(f)
    for inb in data.get('inbounds', []):
        inb['port'] = n_port
    with open(cfg_path, 'w') as f:
        json.dump(data, f, indent=4)
except Exception:
    sys.exit(1)
" "$cfg" "$new_port"

    if [[ $? -eq 0 ]]; then
        systemctl restart v2ray 2>/dev/null
        info "Puerto cambiado a $new_port correctamente"
    else
        error_msg "Error al cambiar el puerto"
    fi
    pause_screen
}

restart_v2ray() {
    panel_header "REINICIAR V2RAY" "🔄"
    systemctl restart v2ray 2>/dev/null
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        info "V2Ray reiniciado correctamente"
    else
        error_msg "Error al reiniciar V2Ray"
    fi
    pause_screen
}

uninstall_v2ray() {
    panel_header "DESINSTALAR V2RAY" "🗑️"
    
    read -r -p "  ¿Seguro que quieres desinstalar V2Ray? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop v2ray 2>/dev/null
        systemctl disable v2ray 2>/dev/null
        rm -rf /usr/local/etc/v2ray /etc/v2ray /usr/local/bin/v2ray /usr/bin/v2ray
        rm -f /etc/systemd/system/v2ray.service
        systemctl daemon-reload
        info "V2Ray desinstalado correctamente"
    else
        warn "Desinstalación cancelada"
    fi
    pause_screen
}

install_v2ray_direct() {
    panel_header "INSTALANDO V2RAY DESDE GITHUB" "⚡"
    
    if is_v2ray_installed; then
        warn "V2Ray ya está instalado"
        pause_screen
        return 0
    fi
    
    info "Ejecutando instalador oficial V2Ray..."
    download_and_execute "install-v2ray.sh"
    
    if is_v2ray_installed; then
        info "V2Ray se instaló correctamente"
    else
        error_msg "Ocurrió un inconveniente durante la instalación de V2Ray"
    fi
    
    pause_screen
}

# ==============================================================================
# FUNCIONES PARA SSH-GO
# ==============================================================================

get_sshgo_cfg_path() {
    for path in /opt/vpn-proxy/config.json /etc/vpn-proxy/config.json /etc/ssh-go/config.json /opt/sshgo/config.json; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    echo "/opt/vpn-proxy/config.json"
}

get_sshgo_ports() {
    python3 -c '
import json, glob, os, re, subprocess

ports = set()

config_files = glob.glob("/opt/**/config.json", recursive=True) + \
               glob.glob("/etc/**/config.json", recursive=True) + \
               ["/opt/vpn-proxy/config.json", "/etc/vpn-proxy/config.json", "/etc/ssh-go/config.json"]

for cfg in set(config_files):
    if os.path.isfile(cfg):
        try:
            with open(cfg, "r") as f:
                data = json.load(f)
            for key in ["port", "ports", "listen", "ListenPort", "Port"]:
                val = data.get(key)
                if isinstance(val, int):
                    ports.add(val)
                elif isinstance(val, str):
                    for num in re.findall(r"\d+", val):
                        ports.add(int(num))
                elif isinstance(val, list):
                    for item in val:
                        if isinstance(item, int):
                            ports.add(item)
                        elif isinstance(item, str):
                            for num in re.findall(r"\d+", item):
                                ports.add(int(num))
        except Exception:
            try:
                with open(cfg, "r") as f:
                    content = f.read()
                matches = re.findall(r"\"port\"\s*:\s*\[?([^\]\}]+)\]?", content, re.IGNORECASE)
                for m in matches:
                    for num in re.findall(r"\d+", m):
                        ports.add(int(num))
            except Exception:
                pass

service_files = ["/etc/systemd/system/vpn-proxy.service", "/etc/systemd/system/ssh-go.service"]
for srv in service_files:
    if os.path.isfile(srv):
        try:
            with open(srv, "r") as f:
                txt = f.read()
            for num in re.findall(r"--port\s+(\d+)|:(\d+)", txt):
                for n in num:
                    if n: ports.add(int(n))
        except Exception:
            pass

try:
    out = subprocess.check_output("ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null", shell=True).decode()
    for line in out.splitlines():
        if "vpn-proxy" in line or "ssh-go" in line or "proxy" in line:
            for m in re.findall(r":(\d+)\s", line):
                ports.add(int(m))
except Exception:
    pass

if ports:
    print(" ".join(map(str, sorted(ports))))
' 2>/dev/null
}

show_sshgo_status() {
    printf "\n  %bServicio SSH-Go:%b " "$CYAN" "$RESET"
    if systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null; then
        info "ACTIVO ✅"
    else
        warn "INACTIVO ❌"
    fi
    
    printf "\n  %bPuertos activos:%b\n" "$BLUE" "$RESET"
    local ports=($(get_sshgo_ports))
    if [[ ${#ports[@]} -gt 0 ]]; then
        for port in "${ports[@]}"; do
            printf "    • Puerto %s\n" "$port"
        done
    else
        warn "  No hay puertos configurados"
    fi
    echo ""
}

add_sshgo_port() {
    panel_header "AGREGAR PUERTO SSH-GO" "🔌"
    
    local cfg=$(get_sshgo_cfg_path)
    
    mkdir -p "$(dirname "$cfg")"
    if [[ ! -f "$cfg" ]]; then
        echo '{"port": []}' > "$cfg"
    fi

    read -r -p "  Ingresa el número de puerto (ej: 8080): " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        pause_screen
        return 1
    fi

    local current_ports=($(get_sshgo_ports))
    for p in "${current_ports[@]}"; do
        if [[ "$p" -eq "$port" ]]; then
            warn "El puerto $port ya está configurado"
            pause_screen
            return 1
        fi
    done
    
    cp "$cfg" "${cfg}.bak" 2>/dev/null
    
    python3 -c "
import json, sys
cfg_path, new_port = sys.argv[1], int(sys.argv[2])
try:
    try:
        with open(cfg_path, 'r') as f:
            data = json.load(f)
    except Exception:
        data = {}
        
    ports = data.get('port', [])
    if isinstance(ports, int):
        ports = [ports]
    elif not isinstance(ports, list):
        ports = []
        
    if new_port not in ports:
        ports.append(new_port)
        
    data['port'] = ports
    
    with open(cfg_path, 'w') as f:
        json.dump(data, f, indent=4)
except Exception:
    sys.exit(1)
" "$cfg" "$port"

    if [[ $? -eq 0 ]]; then
        systemctl restart vpn-proxy 2>/dev/null || systemctl restart ssh-go 2>/dev/null
        info "Puerto $port agregado correctamente"
    else
        error_msg "Error al modificar la configuración"
    fi
    pause_screen
}

remove_sshgo_port() {
    panel_header "QUITAR PUERTO SSH-GO" "🔌"
    
    local cfg=$(get_sshgo_cfg_path)
    local ports=($(get_sshgo_ports))
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        warn "No hay puertos configurados para quitar"
        pause_screen
        return 1
    fi
    
    echo "  Puertos activos:"
    local i=1
    for port in "${ports[@]}"; do
        printf "  %b[%d]%b Puerto %s\n" "$CYAN" "$i" "$RESET" "$port"
        ((i++))
    done
    echo ""
    
    read -r -p "  Selecciona el número de puerto a quitar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#ports[@]} ]]; then
        error_msg "Selección inválida"
        pause_screen
        return 1
    fi
    
    local port_to_remove=${ports[$selection-1]}
    
    if [[ -f "$cfg" ]]; then
        cp "$cfg" "${cfg}.bak" 2>/dev/null
    fi
    
    python3 -c "
import json, sys
cfg_path, rem_port = sys.argv[1], int(sys.argv[2])
try:
    try:
        with open(cfg_path, 'r') as f:
            data = json.load(f)
    except Exception:
        data = {}
        
    ports = data.get('port', [])
    if isinstance(ports, int):
        ports = [ports]
    elif not isinstance(ports, list):
        ports = []
        
    if rem_port in ports:
        ports.remove(rem_port)
        
    data['port'] = ports
    
    with open(cfg_path, 'w') as f:
        json.dump(data, f, indent=4)
except Exception:
    sys.exit(1)
" "$cfg" "$port_to_remove"

    if [[ $? -eq 0 ]]; then
        systemctl restart vpn-proxy 2>/dev/null || systemctl restart ssh-go 2>/dev/null
        info "Puerto $port_to_remove eliminado correctamente"
    else
        error_msg "Error al actualizar la configuración"
    fi
    pause_screen
}

restart_sshgo() {
    panel_header "REINICIAR SSH-GO" "🔄"
    systemctl restart vpn-proxy 2>/dev/null || systemctl restart ssh-go 2>/dev/null
    if systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null; then
        info "SSH-Go reiniciado correctamente"
    else
        error_msg "Error al reiniciar SSH-Go"
    fi
    pause_screen
}

uninstall_sshgo() {
    panel_header "DESINSTALAR SSH-GO" "🗑️"
    
    read -r -p "  ¿Seguro que quieres desinstalar SSH-Go? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop vpn-proxy 2>/dev/null || systemctl stop ssh-go 2>/dev/null
        systemctl disable vpn-proxy 2>/dev/null || systemctl disable ssh-go 2>/dev/null
        rm -rf /opt/vpn-proxy /opt/sshgo
        rm -f /etc/systemd/system/vpn-proxy.service /etc/systemd/system/ssh-go.service
        systemctl daemon-reload
        info "SSH-Go desinstalado correctamente"
    else
        warn "Desinstalación cancelada"
    fi
    pause_screen
}

install_sshgo_direct() {
    panel_header "INSTALANDO SSH-GO DESDE GITHUB" "🚀"
    
    if is_sshgo_installed; then
        warn "SSH-Go ya está instalado"
        pause_screen
        return 0
    fi
    
    info "Ejecutando instalador oficial SSH-Go..."
    download_and_execute "install-sshgo.sh"
    
    if is_sshgo_installed; then
        info "SSH-Go se instaló correctamente"
    else
        error_msg "Ocurrió un inconveniente durante la instalación de SSH-Go"
    fi
    
    pause_screen
}

# ==============================================================================
# FUNCIONES PARA CADDY
# ==============================================================================

get_caddy_domains() {
    python3 -c '
import os, re
caddyfile = "/etc/caddy/Caddyfile"
domains = set()
if os.path.exists(caddyfile):
    with open(caddyfile, "r") as f:
        content = f.read()
    for match in re.finditer(r"([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})", content):
        domains.add(match.group(1))
if domains:
    print("\n".join(sorted(domains)))
' 2>/dev/null
}

get_caddy_ports_http() {
    python3 -c '
import os, re
caddyfile = "/etc/caddy/Caddyfile"
ports = set()
if os.path.exists(caddyfile):
    with open(caddyfile, "r") as f:
        content = f.read()
    for match in re.finditer(r"(?<![a-zA-Z0-9.-]):([0-9]+)", content):
        ports.add(int(match.group(1)))
if ports:
    print(" ".join(str(x) for x in sorted(ports)))
' 2>/dev/null
}

get_caddy_ports_https() {
    python3 -c '
import os, re
caddyfile = "/etc/caddy/Caddyfile"
ports = set()
if os.path.exists(caddyfile):
    with open(caddyfile, "r") as f:
        content = f.read()
    for match in re.finditer(r"[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}:([0-9]+)", content):
        ports.add(int(match.group(1)))
if ports:
    print(" ".join(str(x) for x in sorted(ports)))
' 2>/dev/null
}

show_caddy_status() {
    printf "\n  %bServicio Caddy:%b " "$CYAN" "$RESET"
    if systemctl is-active --quiet caddy 2>/dev/null; then
        info "ACTIVO ✅"
    else
        warn "INACTIVO ❌"
    fi
    
    printf "\n  %bDominios configurados:%b\n" "$BLUE" "$RESET"
    local domains=$(get_caddy_domains)
    if [[ -n "$domains" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" ]] && printf "    • %s\n" "$domain"
        done <<< "$domains"
    else
        warn "  No hay dominios configurados"
    fi
    
    printf "\n  %bPuertos HTTP:%b\n" "$GREEN" "$RESET"
    local http_ports=($(get_caddy_ports_http))
    if [[ ${#http_ports[@]} -gt 0 ]]; then
        for port in "${http_ports[@]}"; do
            printf "    • Puerto %s (HTTP)\n" "$port"
        done
    else
        warn "  No hay puertos HTTP"
    fi
    
    printf "\n  %bPuertos HTTPS:%b\n" "$YELLOW" "$RESET"
    local https_ports=($(get_caddy_ports_https))
    if [[ ${#https_ports[@]} -gt 0 ]]; then
        for port in "${https_ports[@]}"; do
            printf "    • Puerto %s (HTTPS)\n" "$port"
        done
    else
        warn "  No hay puertos HTTPS"
    fi
    echo ""
}

change_caddy_domain() {
    panel_header "CAMBIAR DOMINIO CADDY" "🌐"
    
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        error_msg "Caddy no está instalado"
        pause_screen
        return 1
    fi
    
    local domains=($(get_caddy_domains))
    if [[ ${#domains[@]} -eq 0 ]]; then
        warn "No hay dominios configurados en Caddyfile"
        pause_screen
        return 1
    fi
    
    echo "  Dominios actuales:"
    local i=1
    for domain in "${domains[@]}"; do
        printf "  %b[%d]%b %s\n" "$CYAN" "$i" "$RESET" "$domain"
        ((i++))
    done
    echo ""
    
    read -r -p "  Selecciona el dominio a cambiar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#domains[@]} ]]; then
        error_msg "Selección inválida"
        pause_screen
        return 1
    fi
    
    local old_domain=${domains[$selection-1]}
    read -r -p "  Nuevo dominio (ej: ejemplo.com): " new_domain
    
    if [[ -z "$new_domain" ]]; then
        error_msg "El dominio no puede estar vacío"
        pause_screen
        return 1
    fi
    
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    sed -i "s/$old_domain/$new_domain/g" /etc/caddy/Caddyfile
    
    if command_exists caddy && ! caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
        mv /etc/caddy/Caddyfile.bak /etc/caddy/Caddyfile
        error_msg "Sintaxis inválida en Caddy. Se restauró la configuración previa."
        pause_screen
        return 1
    fi

    systemctl restart caddy
    info "Dominio cambiado de $old_domain a $new_domain correctamente"
    pause_screen
}

add_caddy_http_port() {
    panel_header "AGREGAR PUERTO HTTP CADDY" "🔌"
    
    mkdir -p /etc/caddy
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e ":80 {\n    respond \"Caddy Server\"\n}" > /etc/caddy/Caddyfile
    fi

    read -r -p "  Ingresa el puerto HTTP a agregar (ej: 8080): " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        pause_screen
        return 1
    fi
    
    local http_ports=($(get_caddy_ports_http))
    for p in "${http_ports[@]}"; do
        if [[ "$p" -eq "$port" ]]; then
            warn "El puerto HTTP $port ya está configurado"
            pause_screen
            return 1
        fi
    done

    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    
    echo -e "\n:$port {\n    respond \"Caddy Server HTTP Port $port\"\n}" >> /etc/caddy/Caddyfile
    
    if command_exists caddy && ! caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
        mv /etc/caddy/Caddyfile.bak /etc/caddy/Caddyfile
        error_msg "Error al validar la configuración de Caddy."
        pause_screen
        return 1
    fi

    systemctl restart caddy
    info "Puerto HTTP $port agregado correctamente"
    pause_screen
}

add_caddy_https_port() {
    panel_header "AGREGAR PUERTO HTTPS CADDY" "🔒"
    
    mkdir -p /etc/caddy
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e ":80 {\n    respond \"Caddy Server\"\n}" > /etc/caddy/Caddyfile
    fi

    read -r -p "  Ingresa el puerto HTTPS a agregar (ej: 8443): " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        pause_screen
        return 1
    fi

    local current_domain=$(get_caddy_domains | head -1)
    if [[ -z "$current_domain" ]]; then
        read -r -p "  Ingresa tu dominio para HTTPS (ej: ejemplo.com): " domain
        current_domain="$domain"
    fi
    
    if [[ -z "$current_domain" ]]; then
        error_msg "El dominio es requerido para HTTPS"
        pause_screen
        return 1
    fi

    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    
    echo -e "\n${current_domain}:${port} {\n    respond \"Caddy HTTPS Port $port\"\n}" >> /etc/caddy/Caddyfile
    
    if command_exists caddy && ! caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
        mv /etc/caddy/Caddyfile.bak /etc/caddy/Caddyfile
        error_msg "Error al validar la configuración de Caddy."
        pause_screen
        return 1
    fi

    systemctl restart caddy
    info "Puerto HTTPS $port agregado para $current_domain"
    pause_screen
}

remove_caddy_port() {
    panel_header "QUITAR PUERTO CADDY" "🔌"
    
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        warn "Caddy no está instalado"
        pause_screen
        return 1
    fi
    
    local http_ports=($(get_caddy_ports_http))
    local https_ports=($(get_caddy_ports_https))
    
    if [[ ${#http_ports[@]} -eq 0 && ${#https_ports[@]} -eq 0 ]]; then
        warn "No hay puertos configurados en Caddy"
        pause_screen
        return 1
    fi
    
    echo "  Puertos disponibles para eliminar:"
    local all_ports=("${http_ports[@]}" "${https_ports[@]}")
    local unique_ports=($(echo "${all_ports[@]}" | tr ' ' '\n' | sort -u))
    
    local i=1
    for port in "${unique_ports[@]}"; do
        printf "  %b[%d]%b Puerto %s\n" "$CYAN" "$i" "$RESET" "$port"
        ((i++))
    done
    echo ""
    
    read -r -p "  Selecciona el número de puerto a quitar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#unique_ports[@]} ]]; then
        error_msg "Selección inválida"
        pause_screen
        return 1
    fi
    
    local port_to_remove=${unique_ports[$selection-1]}
    
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null
    
    python3 -c "
import re, sys
caddyfile = '/etc/caddy/Caddyfile'
port = sys.argv[1]
try:
    with open(caddyfile, 'r') as f:
        content = f.read()
    
    pattern = r'(?m)^\s*(?:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})?:' + port + r'\s*\{[^}]*\}'
    content = re.sub(pattern, '', content)
    
    content = re.sub(r':' + port + r',\s*', '', content)
    content = re.sub(r',\s*:' + port, '', content)
    content = re.sub(r'\n\s*\n', '\n\n', content).strip() + '\n'
    
    with open(caddyfile, 'w') as f:
        f.write(content)
except Exception:
    sys.exit(1)
" "$port_to_remove"

    if command_exists caddy && ! caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
        mv /etc/caddy/Caddyfile.bak /etc/caddy/Caddyfile
        error_msg "Error al eliminar el puerto de Caddyfile."
        pause_screen
        return 1
    fi

    systemctl restart caddy
    info "Puerto $port_to_remove eliminado de Caddy correctamente"
    pause_screen
}

restart_caddy() {
    panel_header "REINICIAR CADDY" "🔄"
    systemctl restart caddy
    if systemctl is-active --quiet caddy; then
        info "Caddy reiniciado correctamente"
    else
        error_msg "Error al reiniciar Caddy"
    fi
    pause_screen
}

uninstall_caddy() {
    panel_header "DESINSTALAR CADDY" "🗑️"
    
    read -r -p "  ¿Seguro que quieres desinstalar Caddy? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop caddy 2>/dev/null
        systemctl disable caddy 2>/dev/null
        apt remove -y caddy 2>/dev/null || yum remove -y caddy 2>/dev/null
        rm -rf /etc/caddy
        rm -f /etc/systemd/system/caddy.service
        systemctl daemon-reload
        info "Caddy desinstalado correctamente"
    else
        warn "Desinstalación cancelada"
    fi
    pause_screen
}

install_caddy_direct() {
    panel_header "INSTALANDO CADDY DESDE GITHUB" "🌐"
    
    if is_caddy_installed; then
        warn "Caddy ya está instalado"
        pause_screen
        return 0
    fi
    
    info "Ejecutando instalador oficial Caddy..."
    download_and_execute "install-caddy.sh"
    
    if is_caddy_installed; then
        info "Caddy se instaló correctamente"
    else
        error_msg "Ocurrió un inconveniente durante la instalación de Caddy"
    fi
    
    pause_screen
}

# ==============================================================================
# MENÚS ADMINISTRATIVOS
# ==============================================================================

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
            1) install_v2ray_direct ;;
            2) add_v2ray_id ;;
            3) remove_v2ray_id ;;
            4) change_v2ray_path ;;
            5) change_v2ray_port ;;
            6) restart_v2ray ;;
            7) uninstall_v2ray ;;
            0) break ;;
            *) warn "Opción inválida"; sleep 1 ;;
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
            1) install_sshgo_direct ;;
            2) add_sshgo_port ;;
            3) remove_sshgo_port ;;
            4) restart_sshgo ;;
            5) uninstall_sshgo ;;
            0) break ;;
            *) warn "Opción inválida"; sleep 1 ;;
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
            1) install_caddy_direct ;;
            2) change_caddy_domain ;;
            3) add_caddy_http_port ;;
            4) add_caddy_https_port ;;
            5) remove_caddy_port ;;
            6) restart_caddy ;;
            7) uninstall_caddy ;;
            0) break ;;
            *) warn "Opción inválida"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# ENTRADAS PRINCIPALES DE LOS MÓDULOS
# ==============================================================================

caddy_menu() {
    if ! is_caddy_installed; then
        warn "Caddy no está instalado. Iniciando instalación directa desde GitHub..."
        install_caddy_direct
    fi
    caddy_admin_menu
}

sshgo_menu() {
    if ! is_sshgo_installed; then
        warn "SSH-Go no está instalado. Iniciando instalación directa desde GitHub..."
        install_sshgo_direct
    fi
    sshgo_admin_menu
}

v2ray_menu() {
    if ! is_v2ray_installed; then
        warn "V2Ray no está instalado. Iniciando instalación directa desde GitHub..."
        install_v2ray_direct
    fi
    v2ray_admin_menu
}

firewall_menu() {
    local firewall="/usr/local/bin/firewall.sh"

    panel_header "FIREWALL" "🛡️"

    if [[ ! -x "$firewall" ]]; then
        warn "Firewall no instalado."
        if download_to_path "firewall.sh" "$firewall"; then
            "$firewall"
        fi
    else
        info "Firewall ya está instalado."
        "$firewall"
    fi

    pause_screen
}

xray_menu() {
    panel_header "XRAY PANEL" "🔰"

    if [[ ! -x /usr/local/bin/xray && ! -x /usr/local/bin/v2ray && ! -x /usr/bin/xray && ! -x /usr/bin/v2ray ]]; then
        warn "XRay no está instalado."
        download_and_execute "xray.sh"
    else
        info "XRay/V2Ray ya está instalado."
        if command -v menuV2 >/dev/null 2>&1; then
            menuV2
        else
            warn "El comando menuV2 no está disponible."
        fi
    fi

    pause_screen
}

udp_menu() {
    panel_header "UDP PANEL" "⚡"

    if [[ ! -f /usr/bin/menuUDP && ! -x /usr/local/bin/menuUDP && ! -d /etc/hysteria ]]; then
        warn "UDP no está instalado."
        download_and_execute "Udp.sh"
    else
        info "UDP ya está instalado."
        if [[ -x /usr/bin/menuUDP ]]; then
            /usr/bin/menuUDP
        elif [[ -x /usr/local/bin/menuUDP ]]; then
            /usr/local/bin/menuUDP
        else
            systemctl status udp-hysteria udp-custom zivpn --no-pager 2>/dev/null || true
        fi
    fi

    pause_screen
}

rust_menu() {
    panel_header "SOCKS PROXY RUST" "🦀"
    download_and_execute "rust.sh"
    pause_screen
}

python_menu() {
    panel_header "SOCKS PROXY PYTHON" "🐍"
    download_and_execute "Python.sh"
    pause_screen
}

ssh_panel_menu() {
    local ssh_panel="/usr/local/bin/sshpanel.sh"

    panel_header "SSH PANEL" "👥"

    printf "  %bDescargando tu panel SSH personalizado...%b\n" "$CYAN" "$RESET"

    if download_to_path "sshpanel.sh" "$ssh_panel"; then
        printf "\n  %bAbriendo sshpanel.sh...%b\n\n" "$GREEN" "$RESET"
        bash "$ssh_panel"
    else
        error_msg "No se pudo descargar sshpanel.sh."
    fi

    pause_screen
}

configure_ssh() {
    panel_header "CONFIGURAR SSH" "🔐"

    printf "  %bDescargando y ejecutando ssh.sh...%b\n" "$CYAN" "$RESET"

    download_and_execute "ssh.sh"

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

backup_menu() {
    local backup_dir="/root/backups"
    local backup_file

    mkdir -p "$backup_dir"
    backup_file="$backup_dir/backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    panel_header "BACKUP DE CONFIGURACIONES" "💾"

    tar -czf "$backup_file" \
        /etc/caddy \
        /usr/local/etc/v2ray \
        /opt/vpn-proxy \
        /etc/hysteria \
        /etc/udp-custom \
        /etc/zivpn 2>/dev/null

    info "Backup creado: $backup_file"
    pause_screen
}

status_menu() {
    panel_header "ESTADO GENERAL" "📋"

    printf "  Caddy:   "
    if systemctl is-active --quiet caddy 2>/dev/null; then
        info "ACTIVO"
    else
        warn "INACTIVO"
    fi

    printf "  V2Ray:   "
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        info "ACTIVO"
    else
        warn "INACTIVO"
    fi

    printf "  SSH-Go:  "
    if systemctl is-active --quiet vpn-proxy 2>/dev/null || systemctl is-active --quiet ssh-go 2>/dev/null; then
        info "ACTIVO"
    else
        warn "INACTIVO"
    fi

    pause_screen
}

update_panel() {
    local temporary="/tmp/menu_update.sh"

    panel_header "ACTUALIZAR PANEL" "🔄"

    if curl -fsSL "$BASE_URL/menu.sh" -o "$temporary"; then
        chmod +x "$temporary"
        mv "$temporary" /usr/local/bin/menu
        info "Panel actualizado en /usr/local/bin/menu."
    else
        error_msg "No se pudo actualizar el panel."
        rm -f "$temporary"
    fi

    pause_screen
}

# ==============================================================================
# MENÚ PRINCIPAL EN 2 COLUMNAS PARALELAS ("A LA PAR" CON ALINEACIÓN PERFECTA)
# ==============================================================================

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
        printf "  %b[11]%b 📊 Monitoreo Sistema   %b[12]%b 💾 Backup Config\n" "$BLUE" "$RESET" "$BLUE" "$RESET"
        printf "  %b[13]%b 📋 Estado General      %b[14]%b 🔄 Actualizar Panel\n" "$BLUE" "$RESET" "$BLUE" "$RESET"

        line
        printf "  %b[ 0]%b 🚪 Salir del Panel\n" "$RED" "$RESET"
        line
        printf "\n"

        read -r -p "  ❯ Selecciona una opción [0-14]: " option

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
            12) backup_menu ;;
            13) status_menu ;;
            14) update_panel ;;
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
