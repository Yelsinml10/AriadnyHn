cat << '_OUTER_EOF_' > /usr/local/bin/install_caddy.sh
#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

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

# Limpiar buffer de entrada del teclado
while read -r -t 0.2 discard; do :; done 2>/dev/null

if [[ $EUID -ne 0 ]]; then
   echo -e "\n${RED}[✗] Este script debe ejecutarse como root (sudo bash $0)${NC}\n"
   exit 1
fi

sanitize_ports() {
    echo "$1" | tr ' ' ',' | tr -s ',' | sed 's/^,//;s/,$//'
}

install_caddy_if_needed() {
    if command -v caddy &>/dev/null; then
        echo -e "${GREEN}✔ Caddy ya está instalado en el sistema. No se volverá a instalar.${NC}"
        echo -e "  Versión: $(caddy version | head -n 1)"
        return 0
    fi

    echo -e "\n${BLUE}${BOLD}[ 1 / 3 ] Instalando Caddy y Repositorios Oficiales...${NC}"
    apt-get update -qq
    apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl gnupg lsb-release >/dev/null 2>&1

    mkdir -p /usr/share/keyrings
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
    chmod 644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg

    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
    chmod 644 /etc/apt/sources.list.d/caddy-stable.list

    apt-get update -qq
    apt-get install -y -qq caddy >/dev/null 2>&1

    if ! command -v caddy &>/dev/null; then
        echo -e "${RED}${BOLD}[✗] Error durante la instalación de Caddy.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Caddy instalado correctamente.${NC}"
}

build_https_list() {
    local dom="$1" ports="$2" res=""
    [[ -z "$ports" ]] && return
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        [[ -n "$p" ]] && res="${res:+$res, }${dom}:${p}"
    done
    echo "$res"
}

build_http_list() {
    local ports="$1" res=""
    [[ -z "$ports" ]] && return
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        [[ -n "$p" ]] && res="${res:+$res, }:${p}"
    done
    echo "$res"
}

build_caddyfile() {
    local dom="$1" http_p="$2" https_p="$3"
    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$http_p")

    mkdir -p /etc/caddy

    cat > "$CADDY_CONF" << _INNER_CADDY_
{
    auto_https disable_redirects
}
_INNER_CADDY_

    if [[ -n "$HTTP_LIST" ]]; then
        cat >> "$CADDY_CONF" << _HTTP_BLOCK_

$HTTP_LIST {
    @dinamico_http path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_http {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} { flush_interval -1 }
    }
    @v2ray_http path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_http {
        reverse_proxy 127.0.0.1:9090 { flush_interval -1 }
    }
    handle {
        reverse_proxy 127.0.0.1:8888 { flush_interval -1 }
    }
}
_HTTP_BLOCK_
    fi

    if [[ -n "$HTTPS_LIST" ]]; then
        cat >> "$CADDY_CONF" << _HTTPS_BLOCK_

$HTTPS_LIST {
    @dinamico_https path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_https {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} { flush_interval -1 }
    }
    @v2ray_https path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_https {
        reverse_proxy 127.0.0.1:9090 { flush_interval -1 }
    }
    handle {
        reverse_proxy 127.0.0.1:8888 { flush_interval -1 }
    }
}
_HTTPS_BLOCK_
    fi

    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null || true

    if ! caddy validate --config "$CADDY_CONF" &>/dev/null; then
        echo -e "${RED}[!] Error de sintaxis en el Caddyfile generado.${NC}"
        caddy validate --config "$CADDY_CONF"
        return 1
    fi
    return 0
}

reload_caddy_service() {
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable caddy 2>/dev/null || true
        systemctl restart caddy
    else
        caddy reload --config "$CADDY_CONF" 2>/dev/null || caddy start --config "$CADDY_CONF" 2>/dev/null || true
    fi
}

clear
echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "${CYAN}${BOLD}      AUTOINSTALADOR CADDY PROXY + ENRUTADOR        ${NC}"
echo -e "${CYAN}${BOLD}       DINAMICO + V2RAY MULTIPROTOCOLO              ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}\n"

if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
    echo -e "${GREEN}✔ Se detectó una configuración previa:${NC}"
    echo -e "  Dominio actual: ${YELLOW}$DOMAIN${NC}"
    echo -e "  Puertos HTTP:   ${GREEN}$HTTP_PORTS${NC}"
    echo -e "  Puertos HTTPS:  ${GREEN}$HTTPS_PORTS${NC}\n"
    echo -e -n "${CYAN}¿Deseas reutilizar esta configuración? (s/n): ${NC}"
    read -r REUSE_CONF
    if [[ "$REUSE_CONF" =~ ^[Ss]$ ]]; then
        SKIP_INPUTS=true
    fi
fi

if [[ "${SKIP_INPUTS:-false}" != "true" ]]; then
    echo -e "${PURPLE}${BOLD}[ CONFIGURACION INICIAL ]${NC}\n"

    # 1. DOMINIO
    while true; do
        echo -e "${CYAN}➜ Agrega un dominio (ejemplo: midominio.com):${NC}"
        echo -e -n "  ${WHITE}Dominio:${NC} "
        read -r INPUT_DOM
        INPUT_DOM=$(echo "$INPUT_DOM" | tr -d ' ')
        if [[ -n "$INPUT_DOM" ]]; then
            DOMAIN="$INPUT_DOM"
            break
        else
            echo -e "  ${RED}[!] El dominio no puede estar vacío.${NC}\n"
        fi
    done
    echo ""

    # 2. PUERTOS HTTP
    while true; do
        echo -e "${CYAN}➜ Agrega puertos HTTP (ejemplo: 80, 8880, 2052):${NC}"
        echo -e -n "  ${WHITE}Puertos HTTP:${NC} "
        read -r INPUT_HTTP
        CLEAN_HTTP=$(sanitize_ports "$INPUT_HTTP")
        if [[ -n "$CLEAN_HTTP" ]]; then
            HTTP_PORTS="$CLEAN_HTTP"
            break
        else
            echo -e "  ${RED}[!] Ingresa al menos un puerto HTTP.${NC}\n"
        fi
    done
    echo ""

    # 3. PUERTOS HTTPS
    while true; do
        echo -e "${CYAN}➜ Agrega puertos HTTPS (ejemplo: 443, 8443, 2053):${NC}"
        echo -e -n "  ${WHITE}Puertos HTTPS:${NC} "
        read -r INPUT_HTTPS
        CLEAN_HTTPS=$(sanitize_ports "$INPUT_HTTPS")
        if [[ -n "$CLEAN_HTTPS" ]]; then
            HTTPS_PORTS="$CLEAN_HTTPS"
            break
        else
            echo -e "  ${RED}[!] Ingresa al menos un puerto HTTPS.${NC}\n"
        fi
    done
fi

echo -e "\n${PURPLE}${BOLD}====================================================${NC}"
echo -e "  ${WHITE}• Dominio Configurado :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
echo -e "  ${WHITE}• Puertos HTTP        :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
echo -e "  ${WHITE}• Puertos HTTPS       :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
echo -e "  ${WHITE}• Rutas V2Ray (WS)    :${NC} ${CYAN}/vmess*, /vless* -> 127.0.0.1:9090${NC}"
echo -e "  ${WHITE}• Enrutador Dinámico  :${NC} ${CYAN}/puerto_XXXX -> 127.0.0.1:XXXX${NC}"
echo -e "  ${WHITE}• SSH WebSocket       :${NC} ${CYAN}127.0.0.1:8888${NC}"
echo -e "${PURPLE}${BOLD}----------------------------------------------------${NC}\n"

echo -e -n "${YELLOW}Presiona ENTER para iniciar la instalación...${NC}"
read -r _

mkdir -p /usr/local/etc
cat > "$CONF_FILE" << _INNER_CONF_
DOMAIN="$DOMAIN"
HTTP_PORTS="$HTTP_PORTS"
HTTPS_PORTS="$HTTPS_PORTS"
V2RAY_PORT=9090
OTHER_PORT=8888
_INNER_CONF_

install_caddy_if_needed

echo -e "\n${BLUE}${BOLD}[ 2 / 3 ] Generando Caddyfile...${NC}"
if build_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"; then
    echo -e "${GREEN}✔ Caddyfile generado y validado correctamente.${NC}"
else
    echo -e "${RED}[✗] Falla al construir Caddyfile.${NC}"
    exit 1
fi

echo -e "\n${BLUE}${BOLD}[ 3 / 3 ] Instalando Panel cadmin...${NC}"

cat > /usr/local/bin/cadmin << '_INNER_PANEL_'
#!/usr/bin/env bash

CONF_FILE="/usr/local/etc/caddy_panel.conf"
CADDY_CONF="/etc/caddy/Caddyfile"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

while read -r -t 0.2 discard; do :; done 2>/dev/null

if [[ $EUID -ne 0 ]]; then
   echo -e "\n${RED}[✗] Ejecutar como root: sudo cadmin${NC}\n"
   exit 1
fi

sanitize_ports() { echo "$1" | tr ' ' ',' | tr -s ',' | sed 's/^,//;s/,$//'; }
load_conf() { [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"; }
save_conf() { cat > "$CONF_FILE" << _SAV_CONF_
DOMAIN="$DOMAIN"
HTTP_PORTS="$HTTP_PORTS"
HTTPS_PORTS="$HTTPS_PORTS"
V2RAY_PORT=9090
OTHER_PORT=8888
_SAV_CONF_
}

remove_port() {
    local list="$1" remove="$2" res=""
    IFS=',' read -ra ADDR <<< "$list"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        [[ -n "$p" && "$p" != "$remove" ]] && res="${res:+$res, }${p}"
    done
    echo "$res"
}

build_https_list() {
    local dom="$1" ports="$2" res=""
    [[ -z "$ports" ]] && return
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do p=$(echo "$i" | tr -d ' '); [[ -n "$p" ]] && res="${res:+$res, }${dom}:${p}"; done
    echo "$res"
}

build_http_list() {
    local ports="$1" res=""
    [[ -z "$ports" ]] && return
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do p=$(echo "$i" | tr -d ' '); [[ -n "$p" ]] && res="${res:+$res, }:${p}"; done
    echo "$res"
}

generate_caddyfile() {
    local dom="$1" http_p="$2" https_p="$3"
    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$http_p")

    cat > "$CADDY_CONF" << _CAD_FILE_
{
    auto_https disable_redirects
}
_CAD_FILE_

    if [[ -n "$HTTP_LIST" ]]; then
        cat >> "$CADDY_CONF" << _H_BL_
$HTTP_LIST {
    @dinamico_http path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_http { uri strip_prefix /puerto_{re.puerto.target}; reverse_proxy 127.0.0.1:{re.puerto.target} { flush_interval -1 } }
    @v2ray_http path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_http { reverse_proxy 127.0.0.1:9090 { flush_interval -1 } }
    handle { reverse_proxy 127.0.0.1:8888 { flush_interval -1 } }
}
_H_BL_
    fi

    if [[ -n "$HTTPS_LIST" ]]; then
        cat >> "$CADDY_CONF" << _HS_BL_
$HTTPS_LIST {
    @dinamico_https path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_https { uri strip_prefix /puerto_{re.puerto.target}; reverse_proxy 127.0.0.1:{re.puerto.target} { flush_interval -1 } }
    @v2ray_https path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_https { reverse_proxy 127.0.0.1:9090 { flush_interval -1 } }
    handle { reverse_proxy 127.0.0.1:8888 { flush_interval -1 } }
}
_HS_BL_
    fi

    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null || true

    if ! caddy validate --config "$CADDY_CONF" &>/dev/null; then
        echo -e "${RED}[!] Error en la sintaxis del Caddyfile.${NC}"
        caddy validate --config "$CADDY_CONF"
        return 1
    fi
    return 0
}

reload_service() {
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        systemctl restart caddy
    else
        caddy reload --config "$CADDY_CONF" 2>/dev/null || true
    fi
}

header() {
    load_conf
    clear
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e "${CYAN}${BOLD}       PANEL DE CONTROL CADDY - CADMIN PRO          ${NC}"
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e " ${WHITE}Dominio Actual  :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${WHITE}Puertos HTTP    :${NC} ${GREEN}${BOLD}${HTTP_PORTS:-Ninguno}${NC}"
    echo -e " ${WHITE}Puertos HTTPS   :${NC} ${GREEN}${BOLD}${HTTPS_PORTS:-Ninguno}${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
}

while true; do
    header
    echo -e " ${WHITE}[ 1 ]${NC} ${CYAN}Cambiar Dominio${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${GREEN}Agregar Puerto HTTP${NC}"
    echo -e " ${WHITE}[ 3 ]${NC} ${RED}Quitar Puerto HTTP${NC}"
    echo -e " ${WHITE}[ 4 ]${NC} ${GREEN}Agregar Puerto HTTPS${NC}"
    echo -e " ${WHITE}[ 5 ]${NC} ${RED}Quitar Puerto HTTPS${NC}"
    echo -e " ${WHITE}[ 6 ]${NC} ${CYAN}Estado de Caddy${NC}"
    echo -e " ${WHITE}[ 7 ]${NC} ${GREEN}Reiniciar Caddy${NC}"
    echo -e " ${WHITE}[ 8 ]${NC} ${RED}Desinstalar Caddy${NC}"
    echo -e " ${WHITE}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
    echo -e -n "${YELLOW}➜ ${NC}Selecciona una opción [0-8]: "
    read -r op

    case $op in
        1)
            echo -e -n "\nNuevo dominio: "
            read -r new_dom
            new_dom=$(echo "$new_dom" | tr -d ' ')
            if [ -n "$new_dom" ]; then
                DOMAIN="$new_dom"; save_conf
                if generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"; then
                    reload_service
                    echo -e "${GREEN}✔ Dominio actualizado correctamente.${NC}"
                fi
            fi
            read -p "Presiona ENTER para continuar..." -r ;;
        2)
            echo -e -n "\nPuerto HTTP a agregar: "
            read -r add_http
            add_http=$(echo "$add_http" | tr -d ' ')
            if [ -n "$add_http" ]; then
                HTTP_PORTS=$(sanitize_ports "${HTTP_PORTS}, ${add_http}")
                save_conf
                if generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"; then
                    reload_service
                    echo -e "${GREEN}✔ Puerto HTTP agregado.${NC}"
                fi
            fi
            read -p "Presiona ENTER para continuar..." -r ;;
        3)
            if [ -z "$HTTP_PORTS" ]; then
                echo -e "\n${YELLOW}[!] No hay puertos HTTP configurados para quitar.${NC}"
            else
                echo -e "\nPuertos HTTP actuales: ${GREEN}${HTTP_PORTS}${NC}"
                echo -e -n "Puerto HTTP a quitar: "
                read -r rem_http
                rem_http=$(echo "$rem_http" | tr -d ' ')
                if [ -n "$rem_http" ]; then
                    NEW_PORTS=$(remove_port "$HTTP_PORTS" "$rem_http")
                    if [[ "$NEW_PORTS" == "$HTTP_PORTS" ]]; then
                        echo -e "${YELLOW}[!] El puerto $rem_http no está en la lista.${NC}"
                    else
                        HTTP_PORTS="$NEW_PORTS"
                        save_conf
                        if generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"; then
                            reload_service
                            echo -e "${GREEN}✔ Puerto HTTP $rem_http eliminado.${NC}"
                        fi
                    fi
                fi
            fi
            read -p "Presiona ENTER para continuar..." -r ;;
        4)
            echo -e -n "\nPuerto HTTPS a agregar: "
            read -r add_https
            add_https=$(echo "$add_https" | tr -d ' ')
            if [ -n "$add_https" ]; then
                HTTPS_PORTS=$(sanitize_ports "${HTTPS_PORTS}, ${add_https}")
                save_conf
                if generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"; then
                    reload_service
                    echo -e "${GREEN}✔ Puerto HTTPS agregado.${NC}"
                fi
            fi
            read -p "Presiona ENTER para continuar..." -r ;;
        5)
            if [ -z "$HTTPS_PORTS" ]; then
                echo -e "\n${YELLOW}[!] No hay puertos HTTPS configurados para quitar.${NC}"
            else
                echo -e "\nPuertos HTTPS actuales: ${GREEN}${HTTPS_PORTS}${NC}"
                echo -e -n "Puerto HTTPS a quitar: "
                read -r rem_https
                rem_https=$(echo "$rem_https" | tr -d ' ')
                if [ -n "$rem_https" ]; then
                    NEW_PORTS=$(remove_port "$HTTPS_PORTS" "$rem_https")
                    if [[ "$NEW_PORTS" == "$HTTPS_PORTS" ]]; then
                        echo -e "${YELLOW}[!] El puerto $rem_https no está en la lista.${NC}"
                    else
                        HTTPS_PORTS="$NEW_PORTS"
                        save_conf
                        if generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"; then
                            reload_service
                            echo -e "${GREEN}✔ Puerto HTTPS $rem_https eliminado.${NC}"
                        fi
                    fi
                fi
            fi
            read -p "Presiona ENTER para continuar..." -r ;;
        6)
            echo ""
            if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
                systemctl status caddy --no-pager -n 12
            else
                caddy version
            fi
            echo ""
            read -p "Presiona ENTER para continuar..." -r ;;
        7)
            reload_service
            echo -e "${GREEN}✔ Caddy reiniciado.${NC}"
            sleep 1 ;;
        8)
            echo -e -n "¿Está SEGURO de desinstalar Caddy y cadmin? (s/n): "
            read -r confirm
            if [[ "$confirm" =~ ^[Ss]$ ]]; then
                systemctl stop caddy 2>/dev/null || true
                apt-get purge -y caddy 2>/dev/null || true
                apt-get autoremove -y >/dev/null 2>&1 || true
                rm -rf /etc/caddy /usr/local/bin/cadmin /usr/local/bin/panel "$CONF_FILE" /usr/local/bin/install_caddy.sh \
                       /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg
                echo -e "${GREEN}✔ Desinstalación completa finalizada.${NC}"
                exit 0
            fi ;;
        0) exit 0 ;;
    esac
done
_INNER_PANEL_

chmod +x /usr/local/bin/cadmin
ln -sf /usr/local/bin/cadmin /usr/local/bin/panel

reload_caddy_service

sleep 1

echo -e "\n${GREEN}${BOLD}====================================================${NC}"
echo -e "${GREEN}${BOLD}       ¡INSTALACIÓN COMPLETADA CON ÉXITO!           ${NC}"
echo -e "${GREEN}${BOLD}====================================================${NC}"
echo -e " ${PURPLE}${BOLD}Dominio        :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
echo -e " ${PURPLE}${BOLD}Puertos HTTP   :${NC} ${GREEN}${BOLD}${HTTP_PORTS:-Ninguno}${NC}"
echo -e " ${PURPLE}${BOLD}Puertos HTTPS  :${NC} ${GREEN}${BOLD}${HTTPS_PORTS:-Ninguno}${NC}"
echo -e " ${PURPLE}${BOLD}Comando Panel  :${NC} ${YELLOW}${BOLD}cadmin${NC} o ${YELLOW}${BOLD}panel${NC}"
echo -e "${GREEN}${BOLD}----------------------------------------------------${NC}\n"
_OUTER_EOF_

chmod +x /usr/local/bin/install_caddy.sh
/usr/local/bin/install_caddy.sh
