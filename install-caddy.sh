#!/bin/bash
# Instalador Caddy Proxy + Panel Pro (Con opciones de agregar puertos)

CONF_FILE="/usr/local/etc/caddy_panel.conf"
CADDY_CONF="/etc/caddy/Caddyfile"
V2RAY_PORT=9090
OTHER_PORT=8888

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

check_root(){
    if [[ $EUID -ne 0 ]]; then
       echo -e "\n${RED}${BOLD}[ERROR] Este script debe ejecutarse como root:${NC} ${YELLOW}sudo bash install.sh${NC}\n"
       exit 1
    fi
}

clear
echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}${BOLD}│                                                        │${NC}"
echo -e "${CYAN}${BOLD}│       INSTALADOR PROFESIONAL DE CADDY PROXY            │${NC}"
echo -e "${CYAN}${BOLD}│                 FREENET HN CLOUD                       │${NC}"
echo -e "${CYAN}${BOLD}│                                                        │${NC}"
echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
echo ""

echo -e "${PURPLE}${BOLD}[ CONFIGURACIÓN INICIAL ]${NC}"
echo -e "${WHITE}Ingresa los datos requeridos (Presiona ${YELLOW}ENTER${WHITE} para predeterminado):${NC}\n"

echo -ne " ${CYAN}❯ Dominio${NC} [${YELLOW}arm1.freenethn.org${NC}]: "
read INPUT_DOM
DOMAIN=${INPUT_DOM:-arm1.freenethn.org}

echo -ne " ${CYAN}❯ Puertos HTTP${NC} [${GREEN}80, 8080${NC}]: "
read INPUT_HTTP
HTTP_PORTS=${INPUT_HTTP:-"80, 8080"}

echo -ne " ${CYAN}❯ Puertos HTTPS${NC} [${GREEN}443, 8443${NC}]: "
read INPUT_HTTPS
HTTPS_PORTS=${INPUT_HTTPS:-"443, 8443"}

echo -e "\n${PURPLE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${PURPLE}${BOLD}│ RESUMEN DE PARÁMETROS SELECCIONADOS                    │${NC}"
echo -e "${PURPLE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
echo -e "  ${WHITE}• Dominio        :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
echo -e "  ${WHITE}• Puertos HTTP   :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
echo -e "  ${WHITE}• Puertos HTTPS  :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
echo -e "  ${WHITE}• Backend V2Ray  :${NC} ${CYAN}127.0.0.1:9090${NC}"
echo -e "  ${WHITE}• Backend SSH WS :${NC} ${CYAN}127.0.0.1:8888${NC}"
echo -e "${PURPLE}${BOLD}──────────────────────────────────────────────────────────${NC}\n"

read -p "Presiona ENTER para iniciar el proceso de instalación..."

mkdir -p /usr/local/etc
cat > "$CONF_FILE" <<EOF
DOMAIN="$DOMAIN"
HTTP_PORTS="$HTTP_PORTS"
HTTPS_PORTS="$HTTPS_PORTS"
V2RAY_PORT=9090
OTHER_PORT=8888
EOF

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

build_caddyfile() {
    local dom="$1"
    local http_p="$2"
    local https_p="$3"

    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$dom" "$http_p")

    cat > "$CADDY_CONF" <<EOF
{
    email admin@$dom
    admin off
}

# Configuración HTTPS
$HTTPS_LIST {
    log { output discard }

    # VMess, VLESS, Trojan, Shadowsocks
    @v2ray path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray {
        reverse_proxy 127.0.0.1:$V2RAY_PORT
    }

    # Tu otro servicio (SSH WS)
    handle {
        reverse_proxy 127.0.0.1:$OTHER_PORT
    }
}

# Configuración HTTP
$HTTP_LIST {
    log { output discard }

    @v2ray path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray {
        reverse_proxy 127.0.0.1:$V2RAY_PORT
    }

    # Tu otro servicio (SSH WS)
    handle {
        reverse_proxy 127.0.0.1:$OTHER_PORT
    }
}
EOF
    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null
}

echo -e "\n${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}${BOLD}│ [ 1 / 3 ] Instalando Repositorio Oficial de Caddy...   │${NC}"
echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
apt update -y >/dev/null 2>&1
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null 2>&1

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg >/dev/null 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null 2>&1
apt update -y >/dev/null 2>&1
apt install -y caddy >/dev/null 2>&1
echo -e "${GREEN}✔ Repositorio e instalación de Caddy completados.${NC}"

echo -e "\n${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}${BOLD}│ [ 2 / 3 ] Generando Caddyfile y Enrutamiento Pro...    │${NC}"
echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
build_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
echo -e "${GREEN}✔ Caddyfile generado correctamente.${NC}"

echo -e "\n${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}${BOLD}│ [ 3 / 3 ] Instalando Panel Administrativo Pro ('panel')│${NC}"
echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"

cat > /usr/local/bin/panel <<'PANEL'
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
                
                apt purge -y caddy 2>/dev/null
                rm -rf /etc/caddy /usr/local/bin/panel "$CONF_FILE" /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg
                
                echo -e "\n${GREEN}✔ Desinstalación completa realizada con éxito.${NC}"
                exit 0
            else
                echo -e "\n${GREEN}Desinstalación cancelada.${NC}"
                sleep 1
            fi
            ;;
        0)
            echo -e "\n${GREEN}Saliendo del panel...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Opción inválida.${NC}"
            sleep 1
            ;;
    esac
done
PANEL

chmod +x /usr/local/bin/panel
echo -e "${GREEN}✔ Panel 'panel' creado e instalado en /usr/local/bin/panel.${NC}"

systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy >/dev/null 2>&1

echo -e "\n${GREEN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│       ¡INSTALACIÓN COMPLETADA CON ÉXITO!               │${NC}"
echo -e "${GREEN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
echo -e " ${PURPLE}${BOLD}Dominio        :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
echo -e " ${PURPLE}${BOLD}Puertos HTTP   :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
echo -e " ${PURPLE}${BOLD}Puertos HTTPS  :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
echo -e " ${PURPLE}${BOLD}Rutas V2Ray    :${NC} ${CYAN}/vmess*, /vless*, /trojan*, /ss*${NC}"
echo -e " ${PURPLE}${BOLD}Comando Panel  :${NC} ${YELLOW}${BOLD}panel${NC}"
echo -e "${GREEN}${BOLD}──────────────────────────────────────────────────────────${NC}\n"
