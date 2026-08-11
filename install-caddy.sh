cat << '_OUTER_EOF_' > /usr/local/bin/install_caddy.sh
#!/bin/bash

# Limpiar buffer de entrada del pegado móvil
while read -r -t 0.2 discard; do :; done 2>/dev/null

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

if [[ $EUID -ne 0 ]]; then
   echo -e "\n${RED}[✗] Ejecutar como root: bash $0${NC}\n"
   exit 1
fi

sanitize_ports() {
    echo "$1" | tr ' ' ',' | tr -s ',' | sed 's/^,//;s/,$//'
}

clear
echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "${CYAN}${BOLD}      AUTOINSTALADOR CADDY PROXY + ENRUTADOR        ${NC}"
echo -e "${CYAN}${BOLD}       DINAMICO + V2RAY MULTIPROTOCOLO              ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}\n"

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
        echo -e "  ${RED}[!] El dominio no puede estar vacio.${NC}\n"
    fi
done
echo ""

# 2. PUERTOS HTTP
while true; do
    echo -e "${CYAN}➜ Agrega puertos HTTP (ejemplo: 80, 8880, 2052, 2082, 2086, 2095):${NC}"
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
    echo -e "${CYAN}➜ Agrega puertos HTTPS (ejemplo: 443, 8443, 2053, 2083):${NC}"
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

echo -e "\n${PURPLE}${BOLD}====================================================${NC}"
echo -e "  ${WHITE}• Dominio Configurado :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
echo -e "  ${WHITE}• Puertos HTTP        :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
echo -e "  ${WHITE}• Puertos HTTPS       :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
echo -e "  ${WHITE}• Rutas V2Ray (WS)    :${NC} ${CYAN}/vmess*, /vless* -> 127.0.0.1:9090${NC}"
echo -e "  ${WHITE}• Enrutador Dinamico  :${NC} ${CYAN}/puerto_XXXX -> 127.0.0.1:XXXX${NC}"
echo -e "  ${WHITE}• SSH WebSocket       :${NC} ${CYAN}127.0.0.1:8888${NC}"
echo -e "${PURPLE}${BOLD}----------------------------------------------------${NC}\n"

echo -e -n "${YELLOW}Presiona ENTER para iniciar la instalacion...${NC}"
read -r _

mkdir -p /usr/local/etc
cat > "$CONF_FILE" << _INNER_CONF_
DOMAIN="$DOMAIN"
HTTP_PORTS="$HTTP_PORTS"
HTTPS_PORTS="$HTTPS_PORTS"
V2RAY_PORT=9090
OTHER_PORT=8888
_INNER_CONF_

build_https_list() {
    local dom="$1" ports="$2" res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do
        p=$(echo "$i" | tr -d ' ')
        [[ -n "$p" ]] && res="${res:+$res, }${dom}:${p}"
    done
    echo "$res"
}

build_http_list() {
    local ports="$1" res=""
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

    cat > "$CADDY_CONF" << _INNER_CADDY_
{
    auto_https disable_redirects
}

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
_INNER_CADDY_
    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null
}

echo -e "\n${BLUE}${BOLD}[ 1 / 3 ] Instalando Repositorio Oficial de Caddy...${NC}"
apt update -qq
apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null 2>&1

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

apt update -qq
apt install -y -qq caddy >/dev/null 2>&1

if ! command -v caddy &>/dev/null; then
    echo -e "${RED}${BOLD}[✗] Error instalando Caddy.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Caddy instalado correctamente.${NC}"

echo -e "\n${BLUE}${BOLD}[ 2 / 3 ] Generando Caddyfile...${NC}"
build_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
echo -e "${GREEN}✔ Caddyfile generado.${NC}"

echo -e "\n${BLUE}${BOLD}[ 3 / 3 ] Instalando Panel cadmin...${NC}"

cat > /usr/local/bin/cadmin << '_INNER_PANEL_'
#!/bin/bash
while read -r -t 0.2 discard; do :; done 2>/dev/null

CONF_FILE="/usr/local/etc/caddy_panel.conf"
CADDY_CONF="/etc/caddy/Caddyfile"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

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

build_https_list() {
    local dom="$1" ports="$2" res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do p=$(echo "$i" | tr -d ' '); [[ -n "$p" ]] && res="${res:+$res, }${dom}:${p}"; done
    echo "$res"
}

build_http_list() {
    local ports="$1" res=""
    IFS=',' read -ra ADDR <<< "$ports"
    for i in "${ADDR[@]}"; do p=$(echo "$i" | tr -d ' '); [[ -n "$p" ]] && res="${res:+$res, }:${p}"; done
    echo "$res"
}

generate_caddyfile() {
    local dom="$1" http_p="$2" https_p="$3"
    local HTTPS_LIST=$(build_https_list "$dom" "$https_p")
    local HTTP_LIST=$(build_http_list "$http_p")

    cat > "$CADDY_CONF" << _CAD_FILE_
{ auto_https disable_redirects }
$HTTP_LIST {
    @dinamico_http path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_http { uri strip_prefix /puerto_{re.puerto.target}; reverse_proxy 127.0.0.1:{re.puerto.target} { flush_interval -1 } }
    @v2ray_http path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_http { reverse_proxy 127.0.0.1:9090 { flush_interval -1 } }
    handle { reverse_proxy 127.0.0.1:8888 { flush_interval -1 } }
}
$HTTPS_LIST {
    @dinamico_https path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_https { uri strip_prefix /puerto_{re.puerto.target}; reverse_proxy 127.0.0.1:{re.puerto.target} { flush_interval -1 } }
    @v2ray_https path /vmess* /vless* /trojan* /ss* /v2ray* /xray*
    handle @v2ray_https { reverse_proxy 127.0.0.1:9090 { flush_interval -1 } }
    handle { reverse_proxy 127.0.0.1:8888 { flush_interval -1 } }
}
_CAD_FILE_
    caddy fmt --overwrite "$CADDY_CONF" 2>/dev/null
}

header() {
    load_conf
    clear
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e "${CYAN}${BOLD}       PANEL DE CONTROL CADDY - CADMIN PRO          ${NC}"
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e " ${WHITE}Dominio Actual  :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${WHITE}Puertos HTTP    :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
    echo -e " ${WHITE}Puertos HTTPS   :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
}

while true; do
    header
    echo -e " ${WHITE}[ 1 ]${NC} ${CYAN}Cambiar Dominio${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${CYAN}Reemplazar Puertos HTTP${NC}"
    echo -e " ${WHITE}[ 3 ]${NC} ${GREEN}Agregar Puerto HTTP Nuevo${NC}"
    echo -e " ${WHITE}[ 4 ]${NC} ${CYAN}Reemplazar Puertos HTTPS${NC}"
    echo -e " ${WHITE}[ 5 ]${NC} ${GREEN}Agregar Puerto HTTPS Nuevo${NC}"
    echo -e " ${WHITE}[ 6 ]${NC} ${CYAN}Estado de Caddy${NC}"
    echo -e " ${WHITE}[ 7 ]${NC} ${GREEN}Reiniciar Caddy${NC}"
    echo -e " ${WHITE}[ 8 ]${NC} ${RED}Desinstalar Caddy${NC}"
    echo -e " ${WHITE}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
    echo -e -n "${YELLOW}➜ ${NC}Selecciona una opcion [0-8]: "
    read -r op

    case $op in
        1)
            echo -e -n "\nNuevo dominio: "
            read -r new_dom
            new_dom=$(echo "$new_dom" | tr -d ' ')
            if [ -n "$new_dom" ]; then
                DOMAIN="$new_dom"; save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "${GREEN}✔ Actualizado.${NC}"
            fi
            read -r _ ;;
        2)
            echo -e -n "\nNuevos puertos HTTP (ej: 80, 8880): "
            read -r new_http
            new_http=$(sanitize_ports "$new_http")
            if [ -n "$new_http" ]; then
                HTTP_PORTS="$new_http"; save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "${GREEN}✔ Actualizado.${NC}"
            fi
            read -r _ ;;
        3)
            echo -e -n "\nPuerto HTTP a agregar: "
            read -r add_http
            add_http=$(echo "$add_http" | tr -d ' ')
            if [ -n "$add_http" ]; then
                HTTP_PORTS=$(sanitize_ports "${HTTP_PORTS}, ${add_http}")
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "${GREEN}✔ Agregado.${NC}"
            fi
            read -r _ ;;
        4)
            echo -e -n "\nNuevos puertos HTTPS (ej: 443, 8443): "
            read -r new_https
            new_https=$(sanitize_ports "$new_https")
            if [ -n "$new_https" ]; then
                HTTPS_PORTS="$new_https"; save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "${GREEN}✔ Actualizado.${NC}"
            fi
            read -r _ ;;
        5)
            echo -e -n "\nPuerto HTTPS a agregar: "
            read -r add_https
            add_https=$(echo "$add_https" | tr -d ' ')
            if [ -n "$add_https" ]; then
                HTTPS_PORTS=$(sanitize_ports "${HTTPS_PORTS}, ${add_https}")
                save_conf
                generate_caddyfile "$DOMAIN" "$HTTP_PORTS" "$HTTPS_PORTS"
                systemctl restart caddy
                echo -e "${GREEN}✔ Agregado.${NC}"
            fi
            read -r _ ;;
        6) systemctl status caddy --no-pager -n 10; read -r _ ;;
        7) systemctl restart caddy; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1 ;;
        8)
            echo -e -n "Esta SEGURO de eliminar Caddy y cadmin? (s/n): "
            read -r confirm
            if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                systemctl stop caddy 2>/dev/null
                apt purge -y caddy 2>/dev/null
                rm -rf /etc/caddy /usr/local/bin/cadmin /usr/local/bin/panel "$CONF_FILE" /usr/local/bin/install_caddy.sh
                echo -e "${GREEN}✔ Desinstalado.${NC}"; exit 0
            fi ;;
        0) exit 0 ;;
    esac
done
_INNER_PANEL_

chmod +x /usr/local/bin/cadmin
ln -sf /usr/local/bin/cadmin /usr/local/bin/panel

systemctl daemon-reload
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy >/dev/null 2>&1

sleep 2

if systemctl is-active --quiet caddy; then
    echo -e "\n${GREEN}${BOLD}====================================================${NC}"
    echo -e "${GREEN}${BOLD}       ¡INSTALACION COMPLETADA CON EXITO!           ${NC}"
    echo -e "${GREEN}${BOLD}====================================================${NC}"
    echo -e " ${PURPLE}${BOLD}Dominio        :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTP   :${NC} ${GREEN}${BOLD}$HTTP_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Puertos HTTPS  :${NC} ${GREEN}${BOLD}$HTTPS_PORTS${NC}"
    echo -e " ${PURPLE}${BOLD}Comando Panel  :${NC} ${YELLOW}${BOLD}cadmin${NC}"
    echo -e "${GREEN}${BOLD}----------------------------------------------------${NC}\n"
else
    echo -e "\n${RED}${BOLD}[✗] Caddy fallo al arrancar. Revisa los logs.${NC}\n"
fi
_OUTER_EOF_

chmod +x /usr/local/bin/install_caddy.sh
rm -f /usr/local/etc/caddy_panel.conf
/usr/local/bin/install_caddy.sh
