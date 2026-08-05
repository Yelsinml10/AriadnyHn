#!/bin/bash

# ==========================================
# PALETA DE COLORES ANSI Y ESTILOS
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

CONF_FILE="/etc/badvpn/panel.conf"

# ==========================================
# REGISTRO DEL COMANDO GLOBAL 'badvpn'
# ==========================================
setup_shortcut() {
    local TARGET="/usr/local/bin/badvpn"
    local LINK="/usr/bin/badvpn"
    local SRC="${BASH_SOURCE[0]:-$0}"

    if [ -f "$SRC" ]; then
        SRC=$(readlink -f "$SRC" 2>/dev/null || echo "$SRC")
    fi

    if [[ "$SRC" != "$TARGET" && -f "$SRC" ]]; then
        cp "$SRC" "$TARGET" 2>/dev/null
        chmod +x "$TARGET" 2>/dev/null
    fi

    chmod +x "$TARGET" 2>/dev/null
    ln -sf "$TARGET" "$LINK" 2>/dev/null
    grep -q "alias badvpn=" /root/.bashrc 2>/dev/null || echo "alias badvpn='/usr/local/bin/badvpn'" >> /root/.bashrc
    grep -q "alias badvpn=" /etc/bash.bashrc 2>/dev/null || echo "alias badvpn='/usr/local/bin/badvpn'" >> /etc/bash.bashrc
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n${RED}${BOLD}[ERROR] Este script debe ejecutarse como root:${NC} ${YELLOW}sudo bash $0${NC}\n"
        exit 1
    fi
}

load_conf() {
    mkdir -p /etc/badvpn
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    else
        PORTS="7300, 7200, 7100"
        MAX_CLIENTS="1000"
        MAX_CONN_PER_CLIENT="10"
    fi
}

save_conf() {
    mkdir -p /etc/badvpn
    cat > "$CONF_FILE" <<EOF
PORTS="$PORTS"
MAX_CLIENTS="$MAX_CLIENTS"
MAX_CONN_PER_CLIENT="$MAX_CONN_PER_CLIENT"
EOF
}

# ==========================================
# COMPILACIÓN / INSTALACIÓN BADVPN-UDPGW
# ==========================================
verify_binary() {
    if [ -x "/usr/local/bin/badvpn-udpgw" ]; then
        if /usr/local/bin/badvpn-udpgw --help >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

compile_from_source() {
    echo -e "${YELLOW}[*] Compilando BadVPN-UDPGW desde código fuente para esta arquitectura...${NC}"
    apt-get update -qq >/dev/null 2>&1 || yum update -y >/dev/null 2>&1
    apt-get install -y cmake git gcc g++ make build-essential -qq >/dev/null 2>&1
    
    rm -rf /tmp/badvpn-source
    git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn-source >/dev/null 2>&1
    mkdir -p /tmp/badvpn-source/badvpn-build
    cd /tmp/badvpn-source/badvpn-build 2>/dev/null || return 1
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make >/dev/null 2>&1

    if [ -f "udpgw/badvpn-udpgw" ]; then
        cp udpgw/badvpn-udpgw /usr/local/bin/badvpn-udpgw
        chmod +x /usr/local/bin/badvpn-udpgw
        rm -rf /tmp/badvpn-source
        echo -e "${GREEN}✔ BadVPN-UDPGW compilado con éxito.${NC}"
        return 0
    fi
    rm -rf /tmp/badvpn-source
    return 1
}

install_badvpn_bin() {
    if verify_binary; then
        return 0
    fi

    echo -e "${CYAN}[*] Instalando binario BadVPN-UDPGW...${NC}"
    apt-get update -qq >/dev/null 2>&1 || yum update -y >/dev/null 2>&1
    apt-get install -y curl wget gcc cmake make build-essential psmisc -qq >/dev/null 2>&1

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) B_ARCH="amd64" ;;
        aarch64|arm64|armv8*) B_ARCH="arm64" ;;
        arm*|aarch32|armv7l) B_ARCH="arm" ;;
        *) B_ARCH="amd64" ;;
    esac

    URLS=(
        "https://raw.githubusercontent.com/daybreaker/badvpn-udpgw-binaries/main/badvpn-udpgw-${B_ARCH}"
        "https://raw.githubusercontent.com/Afnan-99/badvpn-udpgw/main/badvpn-udpgw"
    )

    SUCCESS=0
    for url in "${URLS[@]}"; do
        echo -e "${YELLOW}  ➔ Probando descarga binaria (${B_ARCH})...${NC}"
        curl -sSL -o /usr/local/bin/badvpn-udpgw "$url" 2>/dev/null
        if [ ! -s "/usr/local/bin/badvpn-udpgw" ]; then
            wget -qO /usr/local/bin/badvpn-udpgw --no-check-certificate "$url" 2>/dev/null
        fi

        if verify_binary; then
            SUCCESS=1
            echo -e "${GREEN}✔ Binario BadVPN-UDPGW verificado correctamente.${NC}"
            break
        fi
        rm -f /usr/local/bin/badvpn-udpgw
    done

    if [ "$SUCCESS" -eq 0 ]; then
        compile_from_source
        if verify_binary; then
            SUCCESS=1
        fi
    fi

    if [ "$SUCCESS" -eq 0 ]; then
        echo -e "${RED}[!] Error fatal: No se pudo instalar ni compilar BadVPN-UDPGW.${NC}"
        return 1
    fi
    return 0
}

# ==========================================
# GENERAR SCRIPT RUNNER Y SERVICIO SYSTEMD
# ==========================================
generate_service() {
    load_conf

    cat > /usr/local/bin/badvpn-runner <<'RUNNER_EOF'
#!/bin/bash
CONF="/etc/badvpn/panel.conf"
[ -f "$CONF" ] && source "$CONF"

PORTS=${PORTS:-"7300"}
MAX_CLIENTS=${MAX_CLIENTS:-"1000"}
MAX_CONN=${MAX_CONN_PER_CLIENT:-"10"}

pkill -9 badvpn-udpgw 2>/dev/null

IFS=',' read -ra ADDR <<< "$PORTS"
for i in "${ADDR[@]}"; do
    p=$(echo "$i" | tr -d ' ')
    if [ -n "$p" ]; then
        fuser -k $p/udp 2>/dev/null
        /usr/local/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:$p --max-clients $MAX_CLIENTS --max-connections-for-client $MAX_CONN >/dev/null 2>&1 &
    fi
done

while pgrep -f "badvpn-udpgw" >/dev/null 2>&1; do
    sleep 5
done
RUNNER_EOF

    chmod +x /usr/local/bin/badvpn-runner

    cat > /etc/systemd/system/badvpn.service <<EOF
[Unit]
Description=BadVPN UDP Gateway Service (Multi-Port)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/badvpn-runner
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
}

# ==========================================
# FUNCIONES DE MANTENIMIENTO
# ==========================================
instalar_configurar() {
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│       CONFIGURADOR BADVPN UDPGW (MULTI-PUERTO)         │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}\n"

    install_badvpn_bin || { read -p "Presione ENTER para continuar..."; return; }

    echo -e " ${WHITE}Puertos actuales: ${GREEN}${PORTS}${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa los puertos UDPGW separados por coma [ej: 7300, 7200, 7100]: ${NC}")" INPUT_PORTS
    PORTS=${INPUT_PORTS:-"7300, 7200, 7100"}

    read -p "$(echo -e "${CYAN}❯ ${WHITE}Máximo de clientes globales [predeterminado 1000]: ${NC}")" INPUT_CLIENTS
    MAX_CLIENTS=${INPUT_CLIENTS:-"1000"}

    read -p "$(echo -e "${CYAN}❯ ${WHITE}Conexiones por cliente [predeterminado 10]: ${NC}")" INPUT_CONN
    MAX_CONN_PER_CLIENT=${INPUT_CONN:-"10"}

    save_conf
    generate_service

    echo -e "\n${CYAN}Iniciando servicio BadVPN...${NC}"
    systemctl unmask badvpn >/dev/null 2>&1
    systemctl enable badvpn >/dev/null 2>&1
    systemctl restart badvpn >/dev/null 2>&1
    sleep 2

    if pgrep -f badvpn-udpgw >/dev/null 2>&1; then
        echo -e "${GREEN}${BOLD}✔ BadVPN-UDPGW configurado e iniciado en los puertos: $PORTS${NC}\n"
    else
        echo -e "${RED}${BOLD}✘ BadVPN no pudo iniciar. Revisa la opción 6 para ver logs.${NC}\n"
    fi
    read -p "Presiona ENTER para continuar..."
}

agregar_puerto() {
    echo -e "\n${YELLOW}${BOLD}=== AGREGAR PUERTO BADVPN UDPGW ===${NC}"
    echo -e "Puertos activos: ${GREEN}$PORTS${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa el puerto a agregar (ej: 7400): ${NC}")" ADD_PORT
    ADD_PORT=$(echo "$ADD_PORT" | tr -d ' ')

    if [[ "$ADD_PORT" =~ ^[0-9]+$ ]] && [ "$ADD_PORT" -gt 0 ] && [ "$ADD_PORT" -le 65535 ]; then
        if [[ ",$PORTS," == *",$ADD_PORT,"* ]]; then
            echo -e "${RED}✘ El puerto $ADD_PORT ya está configurado.${NC}"
        else
            PORTS="${PORTS}, ${ADD_PORT}"
            save_conf
            generate_service
            systemctl restart badvpn
            sleep 1.5
            echo -e "${GREEN}${BOLD}✔ Puerto $ADD_PORT agregado con éxito. Puertos actuales: $PORTS${NC}"
        fi
    else
        echo -e "${RED}✘ Puerto inválido.${NC}"
    fi
    read -p "Presiona ENTER para continuar..."
}

quitar_puerto() {
    echo -e "\n${YELLOW}${BOLD}=== QUITAR PUERTO BADVPN UDPGW ===${NC}"
    echo -e "Puertos activos: ${GREEN}$PORTS${NC}\n"
    read -p "$(echo -e "${CYAN}❯ ${WHITE}Ingresa el puerto a eliminar (ej: 7200): ${NC}")" DEL_PORT
    DEL_PORT=$(echo "$DEL_PORT" | tr -d ' ')

    if [[ "$DEL_PORT" =~ ^[0-9]+$ ]]; then
        NEW_PORTS=""
        IFS=',' read -ra ADDR <<< "$PORTS"
        for i in "${ADDR[@]}"; do
            p=$(echo "$i" | tr -d ' ')
            if [ -n "$p" ] && [ "$p" != "$DEL_PORT" ]; then
                [ -n "$NEW_PORTS" ] && NEW_PORTS="${NEW_PORTS}, "
                NEW_PORTS="${NEW_PORTS}${p}"
            fi
        done

        if [ -z "$NEW_PORTS" ]; then
            echo -e "${RED}✘ Debe mantener al menos 1 puerto activo.${NC}"
        else
            PORTS="$NEW_PORTS"
            save_conf
            generate_service
            systemctl restart badvpn
            sleep 1.5
            echo -e "${GREEN}${BOLD}✔ Puerto $DEL_PORT eliminado. Puertos actuales: $PORTS${NC}"
        fi
    else
        echo -e "${RED}✘ Puerto inválido.${NC}"
    fi
    read -p "Presiona ENTER para continuar..."
}

reiniciar_servicio() {
    echo -e "\n${YELLOW}${BOLD}=== REINICIAR SERVICIO BADVPN ===${NC}"
    install_badvpn_bin || { read -p "Presione ENTER para continuar..."; return; }
    generate_service
    systemctl unmask badvpn >/dev/null 2>&1
    systemctl enable badvpn >/dev/null 2>&1
    systemctl restart badvpn >/dev/null 2>&1
    sleep 2
    if pgrep -f badvpn-udpgw >/dev/null 2>&1; then
        echo -e "${GREEN}${BOLD}✔ Servicio BadVPN reiniciado e iniciado correctamente.${NC}\n"
    else
        echo -e "${RED}${BOLD}✘ No se pudo iniciar el servicio BadVPN.${NC}\n"
    fi
    read -p "Presiona ENTER para continuar..."
}

toggle_servicio() {
    if pgrep -f badvpn-udpgw >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Deteniendo BadVPN...${NC}"
        systemctl stop badvpn 2>/dev/null
        pkill -9 badvpn-udpgw 2>/dev/null
        echo -e "${RED}✔ Servicio detenido.${NC}"
    else
        echo -e "\n${YELLOW}Iniciando BadVPN...${NC}"
        install_badvpn_bin || { read -p "Presione ENTER para continuar..."; return; }
        generate_service
        systemctl start badvpn 2>/dev/null
        sleep 2
        echo -e "${GREEN}✔ Servicio iniciado.${NC}"
    fi
    sleep 1.5
}

ver_logs() {
    echo -e "\n${YELLOW}${BOLD}=== ESTADO Y LOGS DE BADVPN ===${NC}"
    systemctl status badvpn --no-pager -n 15
    echo -e "\n${CYAN}Procesos activos de BadVPN:${NC}"
    ps aux | grep badvpn-udpgw | grep -v grep || echo -e "  ${RED}No hay procesos de BadVPN en ejecución.${NC}"
    echo ""
    read -p "Presiona ENTER para continuar..."
}

desinstalar_badvpn() {
    echo -e "\n${RED}${BOLD}=== DESINSTALAR BADVPN COMPLETAMENTE ===${NC}"
    read -p "¿Está SEGURO de eliminar BadVPN UDPGW y su servicio? (s/N): " confirm

    if [[ "$confirm" =~ ^[sS]$ ]]; then
        echo -e "${YELLOW}Deteniendo servicios...${NC}"
        systemctl stop badvpn 2>/dev/null
        systemctl disable badvpn 2>/dev/null
        pkill -9 badvpn-udpgw 2>/dev/null

        rm -f /etc/systemd/system/badvpn.service /usr/local/bin/badvpn-runner /usr/local/bin/badvpn-udpgw
        rm -rf /etc/badvpn /usr/local/bin/badvpn
        systemctl daemon-reload

        echo -e "\n${GREEN}${BOLD}✔ BadVPN desinstalado completamente con éxito.${NC}\n"
        read -p "Presiona ENTER para salir..."
        exit 0
    else
        echo -e "${GREEN}Desinstalación cancelada.${NC}\n"
        sleep 1
    fi
}

get_status() {
    if pgrep -f badvpn-udpgw >/dev/null 2>&1 || systemctl is-active --quiet badvpn 2>/dev/null; then
        echo -e "${GREEN}[ACTIVO / RUNNING]${NC}"
    else
        echo -e "${RED}[DETENIDO / STOPPED]${NC}"
    fi
}

header() {
    clear
    load_conf
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│         PANEL DE CONTROL BADVPN-UDPGW PRO              │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos UDPGW   :${NC} ${GREEN}${BOLD}${PORTS:-Sin configurar}${NC}"
    echo -e " ${PURPLE}${BOLD}Max Clientes    :${NC} ${YELLOW}${BOLD}${MAX_CLIENTS:-1000}${NC} ${WHITE}(Max por cliente: ${MAX_CONN_PER_CLIENT:-10})${NC}"
    echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} $(get_status)"
    echo -e " ${PURPLE}${BOLD}Comando Directo :${NC} ${GREEN}${BOLD}badvpn${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
}

# ==========================================
# BUCLE DEL MENÚ
# ==========================================
check_root
setup_shortcut
load_conf

while true; do
    header
    echo -e " ${WHITE}[ 1 ]${NC} ${CYAN}Instalar / Reconfigurar BadVPN UDPGW${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${GREEN}Agregar un Puerto Nuevo${NC}"
    echo -e " ${WHITE}[ 3 ]${NC} ${CYAN}Quitar un Puerto${NC}"
    echo -e " ${WHITE}[ 4 ]${NC} ${GREEN}Reiniciar Servicio BadVPN${NC}"
    echo -e " ${WHITE}[ 5 ]${NC} ${YELLOW}Iniciar / Detener Servicio${NC}"
    echo -e " ${WHITE}[ 6 ]${NC} ${CYAN}Ver Estado Detallado y Logs${NC}"
    echo -e " ${WHITE}[ 7 ]${NC} ${RED}Desinstalar BadVPN Completamente${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    echo -e " ${WHITE}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────────────${NC}"
    read -p "$(echo -e "${YELLOW}${BOLD} Selecciona una opción [0-7]: ${NC}")" op

    case $op in
        1) instalar_configurar ;;
        2) agregar_puerto ;;
        3) quitar_puerto ;;
        4) reiniciar_servicio ;;
        5) toggle_servicio ;;
        6) ver_logs ;;
        7) desinstalar_badvpn ;;
        0) echo -e "\n${GREEN}Saliendo del panel BadVPN...${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
done
