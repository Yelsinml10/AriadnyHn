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
    if ! command_exists curl; then
        apt-get update -qq
        apt-get install -y curl -qq
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
# FUNCIONES PARA SSH-GO
# ==============================================================================

get_sshgo_ports() {
    if [[ -f /opt/vpn-proxy/config.json ]]; then
        grep -o '"port":[^]]*' /opt/vpn-proxy/config.json 2>/dev/null | grep -oE '[0-9]+' | sort -u
    fi
}

show_sshgo_status() {
    printf "\n  %bServicio SSH-Go:%b " "$CYAN" "$RESET"
    if systemctl is-active --quiet vpn-proxy 2>/dev/null; then
        info "ACTIVO ✅"
    else
        warn "INACTIVO ❌"
    fi
    
    printf "\n  %bPuertos activos:%b\n" "$BLUE" "$RESET"
    local ports=$(get_sshgo_ports)
    if [[ -n "$ports" ]]; then
        for port in $ports; do
            printf "    • Puerto %s\n" "$port"
        done
    else
        warn "  No hay puertos configurados"
    fi
    echo ""
}

add_sshgo_port() {
    panel_header "AGREGAR PUERTO SSH-GO" "🔌"
    
    read -r -p "  Ingresa el número de puerto (ej: 8080): " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        return 1
    fi
    
    if [[ ! -f /opt/vpn-proxy/config.json ]]; then
        error_msg "SSH-Go no está instalado"
        return 1
    fi
    
    if grep -q "\"$port\"" /opt/vpn-proxy/config.json; then
        warn "El puerto $port ya está configurado"
        pause_screen
        return 1
    fi
    
    cp /opt/vpn-proxy/config.json /opt/vpn-proxy/config.json.bak
    
    sed -i "s/\"port\": \[/\"port\": \[$port, /" /opt/vpn-proxy/config.json
    
    systemctl restart vpn-proxy
    info "Puerto $port agregado correctamente"
    pause_screen
}

remove_sshgo_port() {
    panel_header "QUITAR PUERTO SSH-GO" "🔌"
    
    local ports=($(get_sshgo_ports))
    if [[ ${#ports[@]} -eq 0 ]]; then
        warn "No hay puertos configurados"
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
        return 1
    fi
    
    local port_to_remove=${ports[$selection-1]}
    
    cp /opt/vpn-proxy/config.json /opt/vpn-proxy/config.json.bak
    
    sed -i "s/$port_to_remove, //" /opt/vpn-proxy/config.json
    sed -i "s/, $port_to_remove//" /opt/vpn-proxy/config.json
    sed -i "s/\[, /[/" /opt/vpn-proxy/config.json
    sed -i "s/, ]/]/" /opt/vpn-proxy/config.json
    
    systemctl restart vpn-proxy
    info "Puerto $port_to_remove eliminado"
    pause_screen
}

restart_sshgo() {
    panel_header "REINICIAR SSH-GO" "🔄"
    systemctl restart vpn-proxy
    if systemctl is-active --quiet vpn-proxy; then
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
        systemctl stop vpn-proxy
        systemctl disable vpn-proxy
        rm -rf /opt/vpn-proxy
        rm -f /etc/systemd/system/vpn-proxy.service
        systemctl daemon-reload
        info "SSH-Go desinstalado"
    else
        warn "Desinstalación cancelada"
    fi
    pause_screen
}

install_sshgo_direct() {
    panel_header "INSTALANDO SSH-GO" "🚀"
    
    if [[ -f /opt/vpn-proxy/vpn-proxy ]]; then
        warn "SSH-Go ya está instalado"
        pause_screen
        return 1
    fi
    
    info "Ejecutando instalador SSH-Go..."
    download_and_execute "install-sshgo.sh"
    
    if [[ -f /opt/vpn-proxy/vpn-proxy ]]; then
        info "SSH-Go instalado correctamente"
    else
        error_msg "Error al instalar SSH-Go"
    fi
    
    pause_screen
}

# ==============================================================================
# FUNCIONES PARA CADDY - CORREGIDAS
# ==============================================================================

get_caddy_domains() {
    if [[ -f /etc/caddy/Caddyfile ]]; then
        grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' /etc/caddy/Caddyfile 2>/dev/null | sed 's/:.*//' | sort -u
    fi
}

get_caddy_ports_http() {
    if [[ -f /etc/caddy/Caddyfile ]]; then
        grep -E '^:[0-9]+' /etc/caddy/Caddyfile 2>/dev/null | grep -oE '[0-9]+' | sort -u
    fi
}

get_caddy_ports_https() {
    if [[ -f /etc/caddy/Caddyfile ]]; then
        grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}:[0-9]+' /etc/caddy/Caddyfile 2>/dev/null | grep -oE ':[0-9]+' | sed 's/://' | sort -u
    fi
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
        for domain in $domains; do
            printf "    • %s\n" "$domain"
        done
    else
        warn "  No hay dominios configurados"
    fi
    
    printf "\n  %bPuertos HTTP:%b\n" "$GREEN" "$RESET"
    local http_ports=$(get_caddy_ports_http)
    if [[ -n "$http_ports" ]]; then
        for port in $http_ports; do
            printf "    • %s\n" "$port"
        done
    else
        warn "  No hay puertos HTTP"
    fi
    
    printf "\n  %bPuertos HTTPS:%b\n" "$YELLOW" "$RESET"
    local https_ports=$(get_caddy_ports_https)
    if [[ -n "$https_ports" ]]; then
        for port in $https_ports; do
            printf "    • %s\n" "$port"
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
        return 1
    fi
    
    local domains=$(get_caddy_domains)
    if [[ -z "$domains" ]]; then
        warn "No hay dominios configurados"
        pause_screen
        return 1
    fi
    
    echo "  Dominios actuales:"
    local i=1
    local domains_array=($domains)
    for domain in "${domains_array[@]}"; do
        printf "  %b[%d]%b %s\n" "$CYAN" "$i" "$RESET" "$domain"
        ((i++))
    done
    echo ""
    
    read -r -p "  Selecciona el dominio a cambiar: " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#domains_array[@]} ]]; then
        error_msg "Selección inválida"
        return 1
    fi
    
    local old_domain=${domains_array[$selection-1]}
    
    read -r -p "  Nuevo dominio (ej: ejemplo.com): " new_domain
    
    if [[ -z "$new_domain" ]]; then
        error_msg "Dominio no puede estar vacío"
        return 1
    fi
    
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
    sed -i "s/$old_domain/$new_domain/g" /etc/caddy/Caddyfile
    
    systemctl restart caddy
    info "Dominio cambiado de $old_domain a $new_domain"
    pause_screen
}

add_caddy_http_port() {
    panel_header "AGREGAR PUERTO HTTP CADDY" "🔌"
    
    read -r -p "  Ingresa el puerto HTTP (ej: 80): " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        return 1
    fi
    
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo ":80 {
    respond \"Caddy Server\"
}" > /etc/caddy/Caddyfile
    fi
    
    if grep -q ":$port" /etc/caddy/Caddyfile 2>/dev/null; then
        warn "El puerto $port ya está configurado"
        pause_screen
        return 1
    fi
    
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
    
    sed -i "/^:80,/ s/80/80, $port/" /etc/caddy/Caddyfile
    
    systemctl restart caddy
    info "Puerto HTTP $port agregado"
    pause_screen
}

add_caddy_https_port() {
    panel_header "AGREGAR PUERTO HTTPS CADDY" "🔒"
    
    read -r -p "  Ingresa el puerto HTTPS (ej: 443): " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error_msg "Puerto inválido"
        return 1
    fi
    
    local current_domain=$(get_caddy_domains | head -1)
    if [[ -z "$current_domain" ]]; then
        read -r -p "  Dominio para HTTPS (ej: ejemplo.com): " domain
        current_domain="$domain"
    fi
    
    if [[ -z "$current_domain" ]]; then
        error_msg "Dominio no puede estar vacío"
        return 1
    fi
    
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo "$current_domain:$port {
    respond \"Caddy Server HTTPS\"
}" > /etc/caddy/Caddyfile
    else
        if grep -q "$current_domain:$port" /etc/caddy/Caddyfile 2>/dev/null; then
            warn "El puerto $port ya está configurado para $current_domain"
            pause_screen
            return 1
        fi
        
        cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
        
        sed -i "/^${current_domain}:443,/ s/443/443, $port/" /etc/caddy/Caddyfile
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
    
    local http_ports=$(get_caddy_ports_http)
    local https_ports=$(get_caddy_ports_https)
    
    if [[ -z "$http_ports" && -z "$https_ports" ]]; then
        warn "No hay puertos configurados"
        pause_screen
        return 1
    fi
    
    echo "  Puertos HTTP actuales:"
    if [[ -n "$http_ports" ]]; then
        for port in $http_ports; do
            printf "    • %s (HTTP)\n" "$port"
        done
    else
        echo "    Ninguno"
    fi
    
    echo ""
    echo "  Puertos HTTPS actuales:"
    if [[ -n "$https_ports" ]]; then
        for port in $https_ports; do
            printf "    • %s (HTTPS)\n" "$port"
        done
    else
        echo "    Ninguno"
    fi
    echo ""
    
    read -r -p "  Puerto a quitar: " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        error_msg "Puerto inválido"
        return 1
    fi
    
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
    
    if echo "$http_ports" | grep -q "$port"; then
        sed -i "s/:$port, //" /etc/caddy/Caddyfile
        sed -i "s/, :$port//" /etc/caddy/Caddyfile
    elif echo "$https_ports" | grep -q "$port"; then
        sed -i "s/:$port, //" /etc/caddy/Caddyfile
        sed -i "s/, :$port//" /etc/caddy/Caddyfile
    else
        warn "Puerto $port no encontrado"
        pause_screen
        return 1
    fi
    
    systemctl restart caddy
    info "Puerto $port eliminado"
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
        systemctl stop caddy
        systemctl disable caddy
        apt remove -y caddy 2>/dev/null
        rm -rf /etc/caddy
        rm -f /etc/systemd/system/caddy.service
        systemctl daemon-reload
        info "Caddy desinstalado"
    else
        warn "Desinstalación cancelada"
    fi
    pause_screen
}

install_caddy_direct() {
    panel_header "INSTALANDO CADDY" "🌐"
    
    if command_exists caddy; then
        warn "Caddy ya está instalado"
        pause_screen
        return 1
    fi
    
    info "Ejecutando instalador Caddy..."
    download_and_execute "install-caddy.sh"
    
    if command_exists caddy; then
        info "Caddy instalado correctamente"
    else
        error_msg "Error al instalar Caddy"
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
# MENÚS PRINCIPALES - CON INSTALACIÓN AUTOMÁTICA
# ==============================================================================

caddy_menu() {
    # Si no está instalado, instalar automáticamente
    if ! command_exists caddy || [[ ! -f /etc/caddy/Caddyfile ]]; then
        warn "Caddy no está instalado. Instalando automáticamente..."
        install_caddy_direct
        # Después de instalar, abrir el panel administrativo
        if command_exists caddy; then
            caddy_admin_menu
        fi
    else
        # Si ya está instalado, abrir el panel administrativo directamente
        caddy_admin_menu
    fi
}

sshgo_menu() {
    # Si no está instalado, instalar automáticamente
    if [[ ! -f /opt/vpn-proxy/vpn-proxy ]]; then
        warn "SSH-Go no está instalado. Instalando automáticamente..."
        install_sshgo_direct
        # Después de instalar, abrir el panel administrativo
        if [[ -f /opt/vpn-proxy/vpn-proxy ]]; then
            sshgo_admin_menu
        fi
    else
        # Si ya está instalado, abrir el panel administrativo directamente
        sshgo_admin_menu
    fi
}

# ==============================================================================
# MENÚS ORIGINALES (SIN CAMBIOS)
# ==============================================================================

v2ray_menu() {
    panel_header "V2RAY / VMESS" "⚡"

    if ! command_exists v2ray &&
        [[ ! -f /usr/local/etc/v2ray/config.json ]]; then
        warn "V2Ray no está instalado."
        download_and_execute "install-v2ray.sh"
    else
        info "V2Ray ya está instalado."
        systemctl status v2ray --no-pager 2>/dev/null ||
            warn "No se pudo consultar el estado de V2Ray."
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

    if [[ ! -x /usr/local/bin/xray &&
          ! -x /usr/local/bin/v2ray &&
          ! -x /usr/bin/xray &&
          ! -x /usr/bin/v2ray ]]; then
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

    if [[ ! -f /usr/bin/menuUDP &&
          ! -x /usr/local/bin/menuUDP &&
          ! -d /etc/hysteria ]]; then
        warn "UDP no está instalado."
        download_and_execute "Udp.sh"
    else
        info "UDP ya está instalado."

        if [[ -x /usr/bin/menuUDP ]]; then
            /usr/bin/menuUDP
        elif [[ -x /usr/local/bin/menuUDP ]]; then
            /usr/local/bin/menuUDP
        else
            systemctl status udp-hysteria udp-custom zivpn \
                --no-pager 2>/dev/null || true
        fi
    fi

    pause_screen
}

ssh_panel_menu() {
    local ssh_panel="/usr/local/bin/sshpanel.sh"

    panel_header "SSH PANEL" "👥"

    printf "  %bDescargando tu panel SSH personalizado...%b\n" \
        "$CYAN" "$RESET"

    if download_to_path "sshpanel.sh" "$ssh_panel"; then
        printf "\n  %bAbriendo sshpanel.sh...%b\n\n" \
            "$GREEN" "$RESET"

        bash "$ssh_panel"
    else
        error_msg "No se pudo descargar sshpanel.sh."
    fi

    pause_screen
}

configure_ssh() {
    panel_header "CONFIGURAR SSH" "🔐"

    printf "  %bDescargando y ejecutando ssh.sh...%b\n" \
        "$CYAN" "$RESET"

    download_and_execute "ssh.sh"

    pause_screen
}

monitor_menu() {
    panel_header "MONITOREO DEL SISTEMA" "📊"

    printf "  Sistema: %s\n" \
        "$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)"
    printf "  Memoria: %s\n" \
        "$(free -h | awk 'NR==2 {print $3 " / " $2}')"
    printf "  Disco: %s\n" \
        "$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    printf "  Tiempo activo: %s\n" \
        "$(uptime -p 2>/dev/null || echo N/A)"

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
    if systemctl is-active --quiet vpn-proxy 2>/dev/null; then
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
                printf "\n  %b¡Gracias por usar el panel VPN!%b\n\n" \
                    "$GREEN" "$RESET"
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
