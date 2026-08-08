#!/bin/bash
# Autoinstalador Profesional Caddy Server + Enrutador DinÃ¡mico + V2Ray Multiprotocolo + Panel cadmin

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

check_root(){
    if [[ $EUID -ne 0 ]]; then
       echo -e "\n${RED}${BOLD}[âœ—] Este script debe ejecutarse como root:${NC} ${YELLOW}bash $0${NC}\n"
       exit 1
    fi
}

sanitize_ports() {
    # Convierte espacios en comas, elimina caracteres no numÃ©ricos extra
    echo "$1" | tr ' ' ',' | tr -s ',' | sed 's/^,//;s/,$//'
}

check_root

clear
echo -e "${CYAN}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
echo -e "${CYAN}${BOLD}â”‚                                                        â”‚${NC}"
echo -e "${CYAN}${BOLD}â”‚       AUTOINSTALADOR PROFESIONAL CADDY PROXY           â”‚${NC}"
echo -e "${CYAN}${BOLD}â”‚       ENRUTADOR DINÃMICO + V2RAY MULTIPROTOCOLO        â”‚${NC}"
echo -e "${CYAN}${BOLD}â”‚                                                        â”‚${NC}"
echo -e "${CYAN}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"
echo ""

echo -e "${PURPLE}${BOLD}[ CONFIGURACIÃ“N INICIAL ]${NC}\n"

# 1. Solicitar Dominio
while true; do
    echo -e "${CYAN}âžœ Agrega un dominio (ejemplo: midominio.com):${NC}"
    read -p "  Dominio: " INPUT_DOM
    INPUT_DOM=$(echo "$INPUT_DOM" | tr -d ' ')
    if [[ -n "$INPUT_DOM" ]]; then
        DOMAIN="$INPUT_DOM"
        break
    else
        echo -e "  ${RED}[!] El dominio no puede estar vacÃ­o. Intenta de nuevo.${NC}\n"
    fi
done
echo ""

# 2. Solicitar Puertos HTTP
while true; do
    echo -e "${CYAN}âžœ Agrega puertos HTTP (ejemplo: 80, 8880):${NC}"
    read -p "  Puertos HTTP: " INPUT_HTTP
    CLEAN_HTTP=$(sanitize_ports "$INPUT_HTTP")
    if [[ -n "$CLEAN_HTTP" ]]; then
        HTTP_PORTS="$CLEAN_HTTP"
        break
    else
        echo -e "  ${RED}[!] Debes agregar al menos un puerto HTTP.${NC}\n"
    fi
done
echo ""

# 3. Solicitar Puertos HTTPS
while true; do
    echo -e "${CYAN}âžœ Agrega puertos HTTPS (ejemplo: 443, 8443):${NC}"
    read -p "  Puertos HTTPS: " INPUT_HTTPS
    CLEAN_HTTPS=$(sanitize_ports "$INPUT_HTTPS")
    if [[ -n "$CLEAN_HTTPS" ]]; then
        HTTPS_PORTS="$CLEAN_HTTPS"
        break
    else
        echo -e "  ${RED}[!] Debes agregar al menos un puerto HTTPS.${NC}\n"
    fi
done

echo -e "\n${PURPLE}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
echo -e "${PURPLE}${BOLD}â”‚ RESUMEN DE PARÃMETROS SELECCIONADOS                    â”‚${NC}"
echo -e "${PURPLE}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"
echo -e "  ${WHITE}â€¢ Dominio Configurado :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
echo -e "  ${WHITE}â€¢ Puertos HTTP        :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
echo -e "  ${WHITE}â€¢ Puertos HTTPS       :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
echo -e "  ${WHITE}â€¢ Rutas V2Ray (WS)    :${NC} ${CYAN}/vmess*, /vless*, /trojan*, /ss* -> 127.0.0.1:9090${NC}"
echo -e "  ${WHITE}â€¢ Enrutador DinÃ¡mico  :${NC} ${CYAN}/puerto_XXXX -> 127.0.0.1:XXXX${NC}"
echo -e "  ${WHITE}â€¢ Puerto Fallback     :${NC} ${CYAN}127.0.0.1:8888${NC}"
echo -e "${PURPLE}${BOLD}â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${NC}\n"

read -p "Presiona ENTER para iniciar la instalaciÃ³n..."

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
    local ports="$1"
    local res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        if [ -n "$p" ]; then
            [ -n "$res" ] && res="${res}, "
            res="${res}:${p}"
        fi
    done
    echo "$res"
}

build_caddyfile() {
    local dom="$1"
    local http_p="$2"
    local https_p="$3"

    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$http_p")

    cat > "$CADDY_CONF" << EOF
{
    auto_https disable_redirects
}

# ========================================================
# ENRUTADOR DINÃMICO + V2RAY MULTIPROTOCOLO - HTTP
# ========================================================
$HTTP_LIST {
    
    # Enrutador dinÃ¡mico por URL (/puerto_XXXX) - Restringido a puertos > 1024 para evitar SSRF en SSH/BBDD
    @dinamico_http path_regexp puerto ^/puerto_(?P<target>[1-9][0-9]{3,4})(/.*)?$
    handle @dinamico_http {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} {
            flush_interval -1
        }
    }

    # V2Ray Multiprotocolo (VMess, VLESS, Trojan, Shadowsocks, Xray)
    @v2ray_http path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_http {
        reverse_proxy 127.0.0.1:9090 {
            flush_interval -1
        }
    }

    # Fallback predeterminado
    handle {
        reverse_proxy 127.0.0.1:8888 {
            flush_interval -1
        }
    }
}

# ========================================================
# ENRUTADOR DINÃMICO + V2RAY MULTIPROTOCOLO - HTTPS
# ========================================================
$HTTPS_LIST {
    
    # Enrutador dinÃ¡mico por URL (/puerto_XXXX) - Restringido a puertos > 1024
    @dinamico_https path_regexp puerto ^/puerto_(?P<target>[1-9][0-9]{3,4})(/.*)?$
    handle @dinamico_https {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} {
            flush_interval -1
        }
    }

    # V2Ray Multiprotocolo (VMess, VLESS, Trojan, Shadowsocks, Xray)
    @v2ray_https path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_https {
        reverse_proxy 127.0.0.1:9090 {
            flush_interval -1
        }
    }

    # Fallback predeterminado
    handle {
        reverse_proxy 127.0.0.1:8888 {
            flush_interval -1
        }
    }
}
EOF
    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null
}

echo -e "\n${BLUE}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
echo -e "${BLUE}${BOLD}â”‚ [ 1 / 3 ] Instalando Repositorio Oficial de Caddy...   â”‚${NC}"
echo -e "${BLUE}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"
apt update -qq
apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null 2>&1

# CorrecciÃ³n: Eliminado 'sudo'
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

apt update -qq
apt install -y -qq caddy >/dev/null 2>&1

if ! command -v caddy &>/dev/null; then
    echo -e "${RED}${BOLD}[âœ—] Hubo un problema instalando Caddy.${NC}"
    exit 1
fi
echo -e "${GREEN}âœ” Caddy instalado correctamente: $(caddy version | awk '{print $1}')${NC}"

echo -e "\n${BLUE}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
echo -e "${BLUE}${BOLD}â”‚ [ 2 / 3 ] Generando Caddyfile con Enrutador y V2Ray...  â”‚${NC}"
echo -e "${BLUE}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"
build_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
echo -e "${GREEN}âœ” Caddyfile generado correctamente en /etc/caddy/Caddyfile.${NC}"

echo -e "\n${BLUE}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
echo -e "${BLUE}${BOLD}â”‚ [ 3 / 3 ] Instalando Panel Administrativo ('cadmin')   â”‚${NC}"
echo -e "${BLUE}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"

cat > /usr/local/bin/cadmin <<'PANEL'
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

sanitize_ports() {
    echo "$1" | tr ' ' ',' | tr -s ',' | sed 's/^,//;s/,$//'
}

load_conf(){
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    else
        DOMAIN="arm1.freenethn.org"
        HTTP_PORTS="80, 8880"
        HTTPS_PORTS="443, 8443"
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
    local ports="$1"
    local res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        if [ -n "$p" ]; then
            [ -n "$res" ] && res="${res}, "
            res="${res}:${p}"
        fi
    done
    echo "$res"
}

generate_caddyfile() {
    local dom="$1"
    local http_p="$2"
    local https_p="$3"

    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$http_p")

    cat > "$CADDY_CONF" << EOF
{
    auto_https disable_redirects
}

# ========================================================
# ENRUTADOR DINÃMICO + V2RAY MULTIPROTOCOLO - HTTP
# ========================================================
$HTTP_LIST {
    
    @dinamico_http path_regexp puerto ^/puerto_(?P<target>[1-9][0-9]{3,4})(/.*)?$
    handle @dinamico_http {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} {
            flush_interval -1
        }
    }

    @v2ray_http path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_http {
        reverse_proxy 127.0.0.1:9090 {
            flush_interval -1
        }
    }

    handle {
        reverse_proxy 127.0.0.1:8888 {
            flush_interval -1
        }
    }
}

# ========================================================
# ENRUTADOR DINÃMICO + V2RAY MULTIPROTOCOLO - HTTPS
# ========================================================
$HTTPS_LIST {
    
    @dinamico_https path_regexp puerto ^/puerto_(?P<target>[1-9][0-9]{3,4})(/.*)?$
    handle @dinamico_https {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} {
            flush_interval -1
        }
    }

    @v2ray_https path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_https {
        reverse_proxy 127.0.0.1:9090 {
            flush_interval -1
        }
    }

    handle {
        reverse_proxy 127.0.0.1:8888 {
            flush_interval -1
        }
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
    echo -e "${CYAN}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
    echo -e "${CYAN}${BOLD}â”‚       PANEL DE CONTROL CADDY - CADMIN PRO              â”‚${NC}"
    echo -e "${CYAN}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"
    echo -e " ${PURPLE}${BOLD}Dominio Actual  :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTP    :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTPS   :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Estado Servicio :${NC} $(get_status)"
    echo -e "${CYAN}${BOLD}â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${NC}"
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
    echo -e "${CYAN}${BOLD}â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${NC}"
    read -p " Selecciona una opciÃ³n [0-8]: " op

    case $op in
        1)
            echo -e "\n${YELLOW}${BOLD}=== CAMBIAR DOMINIO ===${NC}"
            echo -e "Dominio actual: ${CYAN}$DOMAIN${NC}"
            read -p "Ingrese el nuevo dominio: " new_dom
            new_dom=$(echo "$new_dom" | tr -d ' ')
            if [ -n "$new_dom" ]; then
                DOMAIN="$new_dom"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}âœ” Dominio actualizado a: $DOMAIN${NC}"
            else
                echo -e "\n${RED}âœ˜ Dominio invÃ¡lido.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        2)
            echo -e "\n${YELLOW}${BOLD}=== REEMPLAZAR PUERTOS HTTP ===${NC}"
            echo -e "Puertos HTTP actuales: ${GREEN}$HTTP_PORTS${NC}"
            read -p "Nuevos puertos HTTP separados por coma (ej: 80, 8880): " new_http
            new_http=$(sanitize_ports "$new_http")
            if [ -n "$new_http" ]; then
                HTTP_PORTS="$new_http"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}âœ” Puertos HTTP reemplazados por: $HTTP_PORTS${NC}"
            else
                echo -e "\n${RED}âœ˜ Entrada invÃ¡lida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        3)
            echo -e "\n${YELLOW}${BOLD}=== AGREGAR PUERTO HTTP NUEVO ===${NC}"
            echo -e "Puertos HTTP actuales: ${GREEN}$HTTP_PORTS${NC}"
            read -p "Ingrese el puerto HTTP a agregar (ej: 8081): " add_http
            add_http=$(echo "$add_http" | tr -d ' ')
            if [ -n "$add_http" ]; then
                HTTP_PORTS="${HTTP_PORTS}, ${add_http}"
                HTTP_PORTS=$(sanitize_ports "$HTTP_PORTS")
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}âœ” Puerto HTTP $add_http agregado. Nuevos puertos: $HTTP_PORTS${NC}"
            else
                echo -e "\n${RED}âœ˜ Entrada invÃ¡lida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        4)
            echo -e "\n${YELLOW}${BOLD}=== REEMPLAZAR PUERTOS HTTPS ===${NC}"
            echo -e "Puertos HTTPS actuales: ${GREEN}$HTTPS_PORTS${NC}"
            read -p "Nuevos puertos HTTPS separados por coma (ej: 443, 8443): " new_https
            new_https=$(sanitize_ports "$new_https")
            if [ -n "$new_https" ]; then
                HTTPS_PORTS="$new_https"
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}âœ” Puertos HTTPS reemplazados por: $HTTPS_PORTS${NC}"
            else
                echo -e "\n${RED}âœ˜ Entrada invÃ¡lida.${NC}"
            fi
            read -p "Presione ENTER para continuar..."
            ;;
        5)
            echo -e "\n${YELLOW}${BOLD}=== AGREGAR PUERTO HTTPS NUEVO ===${NC}"
            echo -e "Puertos HTTPS actuales: ${GREEN}$HTTPS_PORTS${NC}"
            read -p "Ingrese el puerto HTTPS a agregar (ej: 2087): " add_https
            add_https=$(echo "$add_https" | tr -d ' ')
            if [ -n "$add_https" ]; then
                HTTPS_PORTS="${HTTPS_PORTS}, ${add_https}"
                HTTPS_PORTS=$(sanitize_ports "$HTTPS_PORTS")
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "\n${GREEN}âœ” Puerto HTTPS $add_https agregado. Nuevos puertos: $HTTPS_PORTS${NC}"
            else
                echo -e "\n${RED}âœ˜ Entrada invÃ¡lida.${NC}"
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
            echo -e "${GREEN}âœ” Caddy reiniciado correctamente.${NC}"
            sleep 2
            ;;
        8)
            echo -e "\n${RED}${BOLD}=== DESINSTALAR CADDY COMPLETAMENTE ===${NC}"
            read -p "Â¿EstÃ¡ SEGURO de eliminar Caddy y cadmin? (s/n): " confirm
            if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                echo -e "${YELLOW}Eliminando Caddy y archivos de configuraciÃ³n...${NC}"
                systemctl stop caddy 2>/dev/null
                systemctl disable caddy 2>/dev/null
                
                apt purge -y caddy 2>/dev/null
                rm -rf /etc/caddy /usr/local/bin/cadmin /usr/local/bin/panel "$CONF_FILE" /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg
                
                echo -e "\n${GREEN}âœ” DesinstalaciÃ³n completa realizada con Ã©xito.${NC}"
                exit 0
            else
                echo -e "\n${GREEN}DesinstalaciÃ³n cancelada.${NC}"
                sleep 1
            fi
            ;;
        0)
            echo -e "\n${GREEN}Saliendo del panel...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}OpciÃ³n invÃ¡lida.${NC}"
            sleep 1
            ;;
    esac
done
PANEL

chmod +x /usr/local/bin/cadmin
ln -sf /usr/local/bin/cadmin /usr/local/bin/panel
echo -e "${GREEN}âœ” Panel 'cadmin' instalado en /usr/local/bin/cadmin.${NC}"

systemctl daemon-reload
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy >/dev/null 2>&1

sleep 2

if systemctl is-active --quiet caddy; then
    echo -e "\n${GREEN}${BOLD}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${NC}"
    echo -e "${GREEN}${BOLD}â”‚       Â¡INSTALACIÃ“N COMPLETADA CON Ã‰XITO!               â”‚${NC}"
    echo -e "${GREEN}${BOLD}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${NC}"
    echo -e " ${PURPLE}${BOLD}Dominio        :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTP   :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTPS  :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}V2Ray WS       :${NC} ${CYAN}/vmess*, /vless*, /trojan*, /ss* -> 127.0.0.1:9090${NC}"
    echo -e " ${PURPLE}${BOLD}Regla DinÃ¡mica :${NC} ${CYAN}/puerto_XXXX -> 127.0.0.1:XXXX${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto Fallback:${NC} ${CYAN}127.0.0.1:8888${NC}"
    echo -e " ${PURPLE}${BOLD}Comando Panel  :${NC} ${YELLOW}${BOLD}cadmin${NC}"
    echo -e "${GREEN}${BOLD}â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${NC}\n"
else
    echo -e "\n${RED}${BOLD}[âœ—] Caddy fallÃ³ al arrancar. Revisa los logs con: journalctl -u caddy -n 20 --no-pager${NC}\n"
fi
