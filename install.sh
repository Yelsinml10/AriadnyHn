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
    printf "  %b────────────────────────────────────────────────────────────%b\n" \
        "$DARK" "$RESET"
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

header() {
    clear_screen
    printf "\n"
    printf "  %b╔════════════════════════════════════════════════════════╗%b\n" \
        "$VIOLET" "$RESET"
    printf "  %b║%b  %b🚀 PANEL MAESTRO VPN%b  %b◆ PROFESSIONAL%b  %b║%b\n" \
        "$VIOLET" "$RESET" "$BOLD$WHITE" "$RESET" "$CYAN" "$RESET" "$VIOLET" "$RESET"
    printf "  %b║%b  %bAdministrador avanzado de servicios VPN%b             %b║%b\n" \
        "$VIOLET" "$RESET" "$DIM" "$RESET" "$VIOLET" "$RESET"
    printf "  %b╚════════════════════════════════════════════════════════╝%b\n" \
        "$VIOLET" "$RESET"
    printf "  %b%s%b\n\n" "$GRAY" "$VERSION" "$RESET"
}

panel_header() {
    local title="$1"
    local icon="${2:-◆}"

    header
    printf "  %b╭────────────────────────────────────────────────────────╮%b\n" \
        "$PURPLE" "$RESET"
    printf "  %b│%b  %b%s %s%b\n" \
        "$PURPLE" "$RESET" "$CYAN" "$icon" "$title" "$RESET"
    printf "  %b╰────────────────────────────────────────────────────────╯%b\n\n" \
        "$PURPLE" "$RESET"
}

download_to_path() {
    local script_name="$1"
    local destination="$2"

    printf "\n  %b⬇ Descargando %s...%b\n" \
        "$CYAN" "$script_name" "$RESET"

    if curl -fSL --connect-timeout 15 --max-time 300 \
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

    printf "\n  %b⬇ Descargando %s...%b\n" \
        "$CYAN" "$script_name" "$RESET"

    if ! curl -fSL --connect-timeout 15 --max-time 300 \
        "$BASE_URL/$script_name" -o "$temporary"; then
        error_msg "No se pudo descargar $script_name."
        rm -f "$temporary"
        return 1
    fi

    chmod 700 "$temporary"

    printf "  %b🚀 Ejecutando %s...%b\n\n" \
        "$GREEN" "$script_name" "$RESET"

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

sshgo_admin_menu() {
    while true; do
        panel_header "PANEL SSH-GO PROXY" "🚀"
        
        show_sshgo_status
        
        printf "\n  %b[1]%b  Instalar SSH-Go\n" "$GREEN" "$RESET"
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
        
        printf "\n  %b[1]%b  Instalar Caddy\n" "$GREEN" "$RESET"
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
# ENTRADAS PRINCIPALES: INSTALACIÓN PRIMERO Y LUEGO PANEL ADMINISTRATIVO
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
    panel_header "V2RAY / VMESS" "⚡"

    if ! command_exists v2ray && [[ ! -f /usr/local/etc/v2ray/config.json ]]; then
        warn "V2Ray no está instalado."
        download_and_execute "install-v2ray.sh"
    else
        info "V2Ray ya está instalado."
        systemctl status v2ray --no-pager 2>/dev/null || warn "No se pudo consultar el estado de V2Ray."
    fi

    pause_screen
}

install_all() {
    panel_header "INSTALACIÓN COMPLETA" "📦"

    download_and_execute "install-caddy.sh"
    download_and_execute "install-v2ray.sh"
    download_and_execute "install-sshgo.sh"

    pause_screen
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

    if curl -fSL "$BASE_URL/menu.sh" -o "$temporary"; then
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
# MENÚ PRINCIPAL
# ==============================================================================

main_menu() {
    while true; do
        header

        printf "  %b[1]%b  🌐 Caddy Server\n" "$CYAN" "$RESET"
        printf "  %b[2]%b  ⚡ V2Ray / VMess\n" "$CYAN" "$RESET"
        printf "  %b[3]%b  🚀 SSH-Go Proxy\n" "$CYAN" "$RESET"
        printf "  %b[4]%b  📦 Instalar todos los protocolos\n" "$CYAN" "$RESET"
        printf "  %b[5]%b  👥 SSH Panel personalizado\n" "$CYAN" "$RESET"
        printf "  %b[6]%b  🛡️  Firewall\n" "$CYAN" "$RESET"
        printf "  %b[7]%b  🔰 XRay Panel\n" "$CYAN" "$RESET"
        printf "  %b[8]%b  ⚡ UDP Panel\n" "$CYAN" "$RESET"

        line

        printf "  %b[9]%b  📊 Monitoreo del sistema\n" "$BLUE" "$RESET"
        printf "  %b[10]%b 💾 Backup de configuraciones\n" "$BLUE" "$RESET"
        printf "  %b[11]%b 🔐 Configurar SSH\n" "$CYAN" "$RESET"
        printf "  %b[12]%b 📋 Estado general\n" "$BLUE" "$RESET"
        printf "  %b[13]%b 🔄 Actualizar panel\n" "$BLUE" "$RESET"

        line

        printf "  %b[0]%b  🚪 Salir\n\n" "$RED" "$RESET"

        read -r -p "  ❯ Selecciona una opción: " option

        case "$option" in
            1) caddy_menu ;;
            2) v2ray_menu ;;
            3) sshgo_menu ;;
            4) install_all ;;
            5) ssh_panel_menu ;;
            6) firewall_menu ;;
            7) xray_menu ;;
            8) udp_menu ;;
            9) monitor_menu ;;
            10) backup_menu ;;
            11) configure_ssh ;;
            12) status_menu ;;
            13) update_panel ;;
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
main_menu
