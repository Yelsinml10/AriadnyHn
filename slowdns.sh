cat << '_OUTER_EOF_' > /usr/local/bin/install_slowdns.sh
#!/bin/bash

# Prevenir interrupciones interactivas de APT
export DEBIAN_FRONTEND=noninteractive

# Limpiar buffer de entrada del pegado móvil
while read -r -t 0.2 discard; do :; done 2>/dev/null

CONFIG_DIR="/etc/slowdns"
CONFIG_FILE="$CONFIG_DIR/slowdns.conf"

SYS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
SYS_OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Linux")

# Definición de Colores Estilo Caddy
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "\n${RED}[✗] Ejecutar como root: bash $0${NC}\n"
   exit 1
fi

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e "${CYAN}${BOLD}      AUTOINSTALADOR SLOWDNS / DNSTT SERVER         ${NC}"
    echo -e "${CYAN}${BOLD}       TUNEL DNS MULTI-ARCH (V2RAY / SSH)           ${NC}"
    echo -e "${CYAN}${BOLD}====================================================${NC}\n"
}

# Verificación de instalación previa
if [[ -f "$CONFIG_FILE" && -x "/usr/local/bin/slowdns" ]]; then
    print_banner
    echo -e "${GREEN}${BOLD}✔ SlowDNS ya se encuentra instalado en este servidor.${NC}"
    echo -e "${CYAN}Redirigiendo directamente al panel administrativo...${NC}\n"
    sleep 1.5
    /usr/local/bin/slowdns
    exit 0
fi

install_dependencies() {
    echo -e "\n${BLUE}${BOLD}[ 1 / 5 ] Instalando Repositorios y Dependencias (${SYS_ARCH})...${NC}"
    apt-get update -qq
    apt-get install -y -qq golang git iptables iptables-persistent net-tools curl wget >/dev/null 2>&1
    echo -e "${GREEN}✔ Dependencias de sistema instaladas.${NC}"
}

prompt_installation_data() {
    echo -e "${PURPLE}${BOLD}[ CONFIGURACION INICIAL ]${NC}\n"
    echo -e "  ${WHITE}• Sistema Detectado  :${NC} ${GREEN}${BOLD}$SYS_OS${NC}"
    echo -e "  ${WHITE}• Arquitectura CPU   :${NC} ${YELLOW}${BOLD}$SYS_ARCH${NC}\n"

    # 1. SUBDOMINIO NS
    while true; do
        echo -e "${CYAN}➜ Agrega tu Subdominio NS de SlowDNS (ejemplo: certns.freenethn.org):${NC}"
        echo -e -n "  ${WHITE}Subdominio NS:${NC} "
        read -r INPUT_NS
        INPUT_NS=$(echo "$INPUT_NS" | tr -d ' ')
        if [[ -n "$INPUT_NS" ]]; then
            NS_DOMAIN="$INPUT_NS"
            break
        else
            echo -e "  ${RED}[!] El subdominio NS no puede estar vacio.${NC}\n"
        fi
    done
    echo ""

    # 2. SUGERENCIA DE DESTINO (V2RAY VS SSH)
    echo -e "${CYAN}➜ Selecciona el Destino Interno del Túnel DNS:${NC}"
    echo -e "  ${WHITE}[ 1 ]${NC} ${GREEN}${BOLD}V2Ray Proxy (RECOMENDADO)${NC} ${CYAN}⚡ Mayor velocidad / Menos Lag con Mux${NC}"
    echo -e "  ${WHITE}[ 2 ]${NC} ${YELLOW}SSH Directo (Puerto 22)${NC} ${CYAN}Túnel tradicional SSH por DNS${NC}"
    echo -e -n "  ${WHITE}Opcion [1-2]:${NC} "
    read -r DEST_OPT

    if [[ "$DEST_OPT" == "2" ]]; then
        REDIRECT_TARGET="ssh"
        TARGET_PORT="22"
    else
        REDIRECT_TARGET="v2ray"
        echo ""
        echo -e "${CYAN}➜ Puerto donde escucha tu V2Ray (ejemplo: 8080):${NC}"
        echo -e -n "  ${WHITE}Puerto V2Ray [Default 8080]:${NC} "
        read -r INPUT_V2_PORT
        INPUT_V2_PORT=$(echo "$INPUT_V2_PORT" | tr -d ' ')
        TARGET_PORT=${INPUT_V2_PORT:-8080}
    fi

    echo -e "\n${PURPLE}${BOLD}====================================================${NC}"
    echo -e "  ${WHITE}• Sistema / ARQ       :${NC} ${GREEN}${BOLD}$SYS_OS ($SYS_ARCH)${NC}"
    echo -e "  ${WHITE}• Subdominio NS       :${NC} ${YELLOW}${BOLD}$NS_DOMAIN${NC}"
    echo -e "  ${WHITE}• Destino Configurado :${NC} ${CYAN}${BOLD}$REDIRECT_TARGET (Puerto $TARGET_PORT)${NC}"
    echo -e "${PURPLE}${BOLD}----------------------------------------------------${NC}\n"

    echo -e -n "${YELLOW}Presiona ENTER para iniciar la instalacion...${NC}"
    read -r _

    mkdir -p $CONFIG_DIR
}

compile_dnstt() {
    echo -e "\n${BLUE}${BOLD}[ 2 / 5 ] Instalando binario dnstt-server para ${SYS_ARCH}...${NC}"
    
    rm -f /usr/local/bin/dnstt-server

    # Selección de URL según Arquitectura
    if [[ "$SYS_ARCH" == "arm64" || "$SYS_ARCH" == "aarch64" ]]; then
        URL_BIN="https://dnstt-server-client.s3.amazonaws.com/dnstt-server-linux-arm64"
    else
        URL_BIN="https://dnstt-server-client.s3.amazonaws.com/dnstt-server-linux-amd64"
    fi

    # Intento 1: Descarga directa de binario compilado oficial
    curl -sLf "$URL_BIN" -o /usr/local/bin/dnstt-server 2>/dev/null || wget -qO /usr/local/bin/dnstt-server "$URL_BIN" 2>/dev/null
    chmod +x /usr/local/bin/dnstt-server 2>/dev/null

    # Intento 2: Si por problemas de red falló la descarga, compilar localmente con Go
    if [[ ! -f "/usr/local/bin/dnstt-server" || ! -s "/usr/local/bin/dnstt-server" ]]; then
        echo -e "${YELLOW}⚠️ Compilando desde el código fuente con Go...${NC}"
        TMP_DIR="/tmp/dnstt_build"
        rm -rf $TMP_DIR
        
        git clone https://www.bamsoftware.com/git/dnstt.git $TMP_DIR >/dev/null 2>&1 || \
        git clone https://github.com/gh4rib/dnstt.git $TMP_DIR >/dev/null 2>&1
        
        if [[ -d "$TMP_DIR/dnstt-server" ]]; then
            cd "$TMP_DIR/dnstt-server" || exit 1
            go mod init main >/dev/null 2>&1
            go mod tidy >/dev/null 2>&1
            CGO_ENABLED=0 go build -o /usr/local/bin/dnstt-server . >/dev/null 2>&1 || go build -o /usr/local/bin/dnstt-server . >/dev/null 2>&1
            chmod +x /usr/local/bin/dnstt-server 2>/dev/null
            cd /root || exit 1
            rm -rf $TMP_DIR
        fi
    fi

    # Validación
    if [[ -f "/usr/local/bin/dnstt-server" && -s "/usr/local/bin/dnstt-server" ]]; then
        echo -e "${GREEN}✔ dnstt-server instalado exitosamente.${NC}"
    else
        echo -e "${RED}[✗] Error crítico: No se pudo obtener el ejecutable dnstt-server.${NC}"
        exit 1
    fi
}

generate_keys() {
    echo -e "\n${BLUE}${BOLD}[ 3 / 5 ] Generando Llaves de Cifrado (Keys)...${NC}"
    mkdir -p $CONFIG_DIR
    
    if [[ ! -f "$CONFIG_DIR/server.key" || ! -f "$CONFIG_DIR/server.pub" ]]; then
        /usr/local/bin/dnstt-server -gen-key -privkey-file "$CONFIG_DIR/server.key" -pubkey-file "$CONFIG_DIR/server.pub" >/dev/null 2>&1
    fi

    if [[ -f "$CONFIG_DIR/server.pub" ]]; then
        PUB_KEY=$(cat "$CONFIG_DIR/server.pub")
        echo -e "${GREEN}✔ Llaves criptográficas generadas.${NC}"
    else
        echo -e "${RED}[✗] Error al generar la llave pública.${NC}"
        exit 1
    fi

    cat > "$CONFIG_FILE" << _INNER_CONF_
NS_DOMAIN="$NS_DOMAIN"
REDIRECT_TARGET="$REDIRECT_TARGET"
TARGET_PORT="$TARGET_PORT"
PUB_KEY="$PUB_KEY"
_INNER_CONF_
}

configure_firewall() {
    echo -e "\n${BLUE}${BOLD}[ 4 / 5 ] Configurando Reglas de Red (Puerto 53 UDP -> 5300 UDP)...${NC}"
    
    iptables -I INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5300 2>/dev/null
    
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${GREEN}✔ Reglas de cortafuegos aplicadas.${NC}"
}

setup_systemd_service() {
    echo -e "\n${BLUE}${BOLD}[ 5 / 5 ] Creando Servicio Systemd e Instalando Comando 'slowdns'...${NC}"
    
    cat > /etc/systemd/system/slowdns.service << _INNER_SERVICE_
[Unit]
Description=SlowDNS / DNSTT Tunnel Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey-file $CONFIG_DIR/server.key $NS_DOMAIN 127.0.0.1:$TARGET_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
_INNER_SERVICE_

    systemctl daemon-reload
    systemctl enable slowdns >/dev/null 2>&1
    systemctl restart slowdns

    cat > /usr/local/bin/slowdns << '_INNER_PANEL_'
#!/bin/bash
while read -r -t 0.2 discard; do :; done 2>/dev/null

CONFIG_DIR="/etc/slowdns"
CONFIG_FILE="$CONFIG_DIR/slowdns.conf"

SYS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
SYS_OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Linux")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

load_conf() { [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"; }

save_conf() {
    cat > "$CONFIG_FILE" << _SAV_CONF_
NS_DOMAIN="$NS_DOMAIN"
REDIRECT_TARGET="$REDIRECT_TARGET"
TARGET_PORT="$TARGET_PORT"
PUB_KEY="$PUB_KEY"
_SAV_CONF_
}

header() {
    load_conf
    clear
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e "${CYAN}${BOLD}       PANEL DE CONTROL SLOWDNS / DNSTT             ${NC}"
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e " ${WHITE}Sistema / ARQ   :${NC} ${GREEN}${BOLD}$SYS_OS ($SYS_ARCH)${NC}"
    echo -e " ${WHITE}Subdominio NS   :${NC} ${YELLOW}${BOLD}$NS_DOMAIN${NC}"
    echo -e " ${WHITE}Destino Actual  :${NC} ${GREEN}${BOLD}$REDIRECT_TARGET (Puerto $TARGET_PORT)${NC}"
    echo -e " ${WHITE}Public Key (PUB):${NC} ${YELLOW}${BOLD}$PUB_KEY${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
}

switch_target() {
    header
    echo -e "${PURPLE}${BOLD}[ CAMBIAR DESTINO DEL TÚNEL SLOWDNS ]${NC}\n"
    echo -e " ${WHITE}[ 1 ]${NC} ${GREEN}V2Ray Proxy${NC} ${CYAN}(Recomendado - Mayor velocidad con Mux)${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${YELLOW}SSH Directo (Puerto 22)${NC} ${CYAN}(Túnel tradicional)${NC}"
    echo -e -n "\n${YELLOW}➜ Selecciona una opcion [1-2]: ${NC}"
    read -r opt
    case $opt in
        1)
            REDIRECT_TARGET="v2ray"
            echo -e -n "\n${CYAN}Puerto donde escucha tu V2Ray [Default 8080]: ${NC}"
            read -r new_p
            new_p=$(echo "$new_p" | tr -d ' ')
            TARGET_PORT=${new_p:-8080}
            ;;
        2)
            REDIRECT_TARGET="ssh"
            TARGET_PORT="22"
            ;;
        *) return ;;
    esac
    
    save_conf
    sed -i "s|ExecStart=.*|ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey-file $CONFIG_DIR/server.key $NS_DOMAIN 127.0.0.1:$TARGET_PORT|" /etc/systemd/system/slowdns.service
    systemctl daemon-reload
    systemctl restart slowdns
    echo -e "${GREEN}✔ Redirigido hacia $REDIRECT_TARGET (Puerto $TARGET_PORT).${NC}"
    read -r _
}

view_info() {
    header
    echo -e "${PURPLE}${BOLD}[ CLAVE PÚBLICA Y DATOS DE CONEXIÓN ]${NC}\n"
    echo -e " ${WHITE}• Subdominio NS   :${NC} ${YELLOW}${BOLD}$NS_DOMAIN${NC}"
    echo -e " ${WHITE}• Public Key      :${NC} ${GREEN}${BOLD}$PUB_KEY${NC}"
    echo -e " ${WHITE}• Destino Interno :${NC} ${CYAN}${BOLD}$REDIRECT_TARGET (Puerto $TARGET_PORT)${NC}"
    echo -e "\n${CYAN}${BOLD}── Configuración en Apps (HTTP Custom, DNSTT Plugin, etc) ──${NC}"
    echo -e " ${WHITE}• Nameserver (NS) :${NC} ${YELLOW}$NS_DOMAIN${NC}"
    echo -e " ${WHITE}• Public Key (DNS):${NC} ${GREEN}$PUB_KEY${NC}"
    echo -e " ${WHITE}• DNS Server      :${NC} ${CYAN}1.1.1.1 o 8.8.8.8${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
    read -r _
}

while true; do
    header
    echo -e " ${WHITE}[ 1 ]${NC} ${CYAN}Ver Clave Pública (Public Key) y Datos de Conexión${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${GREEN}Cambiar Destino (V2Ray <-> SSH 22)${NC}"
    echo -e " ${WHITE}[ 3 ]${NC} ${CYAN}Ver Registros / Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}[ 4 ]${NC} ${GREEN}Reiniciar Servicio SlowDNS${NC}"
    echo -e " ${WHITE}[ 5 ]${NC} ${RED}Desinstalar SlowDNS${NC}"
    echo -e " ${WHITE}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
    echo -e -n "${YELLOW}➜ ${NC}Selecciona una opcion [0-5]: "
    read -r op

    case $op in
        1) view_info ;;
        2) switch_target ;;
        3) journalctl -u slowdns -f -n 30 ;;
        4) systemctl restart slowdns; echo -e "${GREEN}✔ Servicio SlowDNS reiniciado.${NC}"; sleep 1 ;;
        5)
            echo -e -n "\n${RED}¿Esta SEGURO de eliminar SlowDNS? (s/n): ${NC}"
            read -r confirm
            if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                systemctl stop slowdns 2>/dev/null
                systemctl disable slowdns 2>/dev/null
                rm -f /etc/systemd/system/slowdns.service /usr/local/bin/dnstt-server /usr/local/bin/slowdns
                rm -rf $CONFIG_DIR
                systemctl daemon-reload
                echo -e "${GREEN}✔ SlowDNS desinstalado por completo.${NC}"; exit 0
            fi ;;
        0) exit 0 ;;
    esac
done
_INNER_PANEL_

    chmod +x /usr/local/bin/slowdns
}

# -------------------------------------------------------------------
# EJECUCIÓN PRINCIPAL
# -------------------------------------------------------------------

print_banner
install_dependencies
prompt_installation_data
compile_dnstt
generate_keys
configure_firewall
setup_systemd_service

sleep 2

if systemctl is-active --quiet slowdns; then
    echo -e "\n${GREEN}${BOLD}====================================================${NC}"
    echo -e "${GREEN}${BOLD}       ¡SLOWDNS INSTALADO CON EXITO!                ${NC}"
    echo -e "${GREEN}${BOLD}====================================================${NC}"
    echo -e " ${PURPLE}${BOLD}Sistema / ARQ  :${NC} ${GREEN}${BOLD}$SYS_OS ($SYS_ARCH)${NC}"
    echo -e " ${PURPLE}${BOLD}Subdominio NS  :${NC} ${YELLOW}${BOLD}$NS_DOMAIN${NC}"
    echo -e " ${PURPLE}${BOLD}Destino        :${NC} ${CYAN}${BOLD}$REDIRECT_TARGET (Puerto $TARGET_PORT)${NC}"
    echo -e " ${PURPLE}${BOLD}Public Key     :${NC} ${GREEN}${BOLD}$PUB_KEY${NC}"
    echo -e " ${PURPLE}${BOLD}Comando Panel  :${NC} ${YELLOW}${BOLD}slowdns${NC}"
    echo -e "${GREEN}${BOLD}----------------------------------------------------${NC}\n"
    sleep 2
    /usr/local/bin/slowdns
else
    echo -e "\n${RED}${BOLD}[✗] SlowDNS fallo al arrancar. Revisa los logs con: journalctl -u slowdns -n 20${NC}\n"
fi
_OUTER_EOF_

chmod +x /usr/local/bin/install_slowdns.sh
/usr/local/bin/install_slowdns.sh
