cat << '_OUTER_EOF_' > /usr/local/bin/install_ssh_ws.sh
#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
while read -r -t 0.2 discard; do :; done 2>/dev/null

CONFIG_DIR="/etc/ssh-ws"
CONFIG_FILE="$CONFIG_DIR/config.conf"

SYS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
SYS_OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Linux")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "\n${RED}[✗] Ejecutar como root: bash $0${NC}\n"
   exit 1
fi

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e "${CYAN}${BOLD}      AUTOINSTALADOR SSH WEBSOCKET SSL / TLS        ${NC}"
    echo -e "${CYAN}${BOLD}       ENRUTADOR + PAYLOAD + SNI PRO MULTI-ARCH     ${NC}"
    echo -e "${CYAN}${BOLD}====================================================${NC}\n"
}

install_dependencies() {
    echo -e "\n${BLUE}${BOLD}[ 1 / 5 ] Instalando Repositorios y Dependencias (${SYS_ARCH})...${NC}"
    apt-get update -qq
    apt-get install -y -qq stunnel4 stunnel certbot openssl python3 net-tools curl wget lsb-release >/dev/null 2>&1 || \
    apt-get install -y -qq stunnel certbot openssl python3 net-tools curl wget lsb-release >/dev/null 2>&1
    echo -e "${GREEN}✔ Dependencias instaladas correctamente en ${SYS_ARCH}.${NC}"
}

prompt_installation_data() {
    echo -e "${PURPLE}${BOLD}[ CONFIGURACION INICIAL ]${NC}\n"
    echo -e "  ${WHITE}• Sistema Detectado  :${NC} ${GREEN}${BOLD}$SYS_OS${NC}"
    echo -e "  ${WHITE}• Arquitectura CPU   :${NC} ${YELLOW}${BOLD}$SYS_ARCH${NC}\n"

    while true; do
        echo -e "${CYAN}➜ Agrega tu dominio (ejemplo: midominio.com):${NC}"
        echo -e -n "  ${WHITE}Dominio:${NC} "
        read -r INPUT_DOM
        INPUT_DOM=$(echo "$INPUT_DOM" | tr -d ' ')
        if [[ -n "$INPUT_DOM" ]]; then DOMAIN="$INPUT_DOM"; break; else echo -e "  ${RED}[!] El dominio no puede estar vacio.${NC}\n"; fi
    done
    echo ""

    while true; do
        echo -e "${CYAN}➜ Agrega tu email para Let's Encrypt:${NC}"
        echo -e -n "  ${WHITE}Email:${NC} "
        read -r INPUT_MAIL
        INPUT_MAIL=$(echo "$INPUT_MAIL" | tr -d ' ')
        if [[ -n "$INPUT_MAIL" ]]; then EMAIL="$INPUT_MAIL"; break; else echo -e "  ${RED}[!] El email no puede estar vacio.${NC}\n"; fi
    done
    echo ""

    echo -e "${CYAN}➜ Selecciona el tipo de Certificado SSL:${NC}"
    echo -e "  ${WHITE}[ 1 ]${NC} ${GREEN}Let's Encrypt (Oficial - Recomendado)${NC}"
    echo -e "  ${WHITE}[ 2 ]${NC} ${YELLOW}OpenSSL (Autofirmado)${NC}"
    echo -e -n "  ${WHITE}Opcion [1-2]:${NC} "
    read -r CERT_OPTION
    case $CERT_OPTION in 2) CERT_TYPE="selfsigned" ;; *) CERT_TYPE="letsencrypt" ;; esac
    echo ""

    echo -e "${CYAN}➜ Selecciona el Destino del Puerto 443 SSL:${NC}"
    echo -e "  ${WHITE}[ 1 ]${NC} ${GREEN}Python Proxy${NC} ${CYAN}(Soporta Payloads / WebSockets)${NC}"
    echo -e "  ${WHITE}[ 2 ]${NC} ${GREEN}SSH Directo (Puerto 22)${NC} ${CYAN}(SSL Directo sin Payload)${NC}"
    echo -e -n "  ${WHITE}Opcion [1-2]:${NC} "
    read -r REDIRECT_OPT

    if [[ "$REDIRECT_OPT" == "2" ]]; then
        REDIRECT_TARGET="ssh"; PYTHON_PORT="22"; HTTP_RESPONSE_CODE="N/A"
    else
        REDIRECT_TARGET="python"
        echo -e -n "\n${CYAN}Puerto Python [Default 8080]:${NC} "
        read -r INPUT_PY_PORT
        INPUT_PY_PORT=$(echo "$INPUT_PY_PORT" | tr -d ' ')
        PYTHON_PORT=${INPUT_PY_PORT:-8080}

        echo -e "\n${CYAN}➜ Codigo de Respuesta HTTP para el Payload:${NC}"
        echo -e "  ${WHITE}[ 1 ]${NC} ${GREEN}101 Switching Protocols${NC}"
        echo -e "  ${WHITE}[ 2 ]${NC} ${CYAN}200 OK${NC}"
        echo -e "  ${WHITE}[ 3 ]${NC} ${YELLOW}301 Moved Permanently${NC}"
        echo -e "  ${WHITE}[ 4 ]${NC} ${RED}404 Not Found${NC}"
        echo -e -n "  ${WHITE}Opcion [1-4]:${NC} "
        read -r HTTP_CODE_OPT
        case $HTTP_CODE_OPT in 2) HTTP_RESPONSE_CODE="200" ;; 3) HTTP_RESPONSE_CODE="301" ;; 4) HTTP_RESPONSE_CODE="404" ;; *) HTTP_RESPONSE_CODE="101" ;; esac
    fi

    echo -e "\n${PURPLE}${BOLD}====================================================${NC}"
    echo -e "  ${WHITE}• Sistema / ARQ       :${NC} ${GREEN}${BOLD}$SYS_OS ($SYS_ARCH)${NC}"
    echo -e "  ${WHITE}• Dominio Configurado :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e "  ${WHITE}• Certificado SSL     :${NC} ${GREEN}${BOLD}$CERT_TYPE${NC}"
    echo -e "  ${WHITE}• Destino Puerto 443  :${NC} ${CYAN}${BOLD}$REDIRECT_TARGET ($PYTHON_PORT)${NC}"
    echo -e "${PURPLE}${BOLD}----------------------------------------------------${NC}\n"

    echo -e -n "${YELLOW}Presiona ENTER para iniciar la instalacion...${NC}"
    read -r _

    mkdir -p $CONFIG_DIR
    cat > "$CONFIG_FILE" << _INNER_CONF_
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
CERT_TYPE="$CERT_TYPE"
REDIRECT_TARGET="$REDIRECT_TARGET"
PYTHON_PORT="$PYTHON_PORT"
HTTP_RESPONSE_CODE="$HTTP_RESPONSE_CODE"
_INNER_CONF_
}

setup_ssl_certificate() {
    echo -e "\n${BLUE}${BOLD}[ 2 / 5 ] Generando Certificado SSL/TLS...${NC}"
    systemctl stop nginx apache2 caddy lighttpd stunnel4 stunnel 2>/dev/null

    if [[ "$CERT_TYPE" == "letsencrypt" ]]; then
        certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --keep-until-expiring >/dev/null 2>&1
        if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
            CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
            echo -e "${GREEN}✔ Certificado Let's Encrypt generado correctamente.${NC}"
        else
            CERT_TYPE="selfsigned"
        fi
    fi

    if [[ "$CERT_TYPE" == "selfsigned" ]]; then
        mkdir -p /etc/stunnel/certs
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/stunnel/certs/privkey.pem -out /etc/stunnel/certs/fullchain.pem -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" >/dev/null 2>&1
        CERT_PATH="/etc/stunnel/certs"
        echo -e "${GREEN}✔ Certificado Autofirmado generado.${NC}"
    fi

    echo "CERT_PATH=\"$CERT_PATH\"" >> "$CONFIG_FILE"
}

setup_python_proxy() {
    if [[ "$REDIRECT_TARGET" == "ssh" ]]; then
        systemctl stop ws-proxy 2>/dev/null; systemctl disable ws-proxy 2>/dev/null; return
    fi

    echo -e "\n${BLUE}${BOLD}[ 3 / 5 ] Configurando Proxy Python para Payloads...${NC}"
    
    cat > /usr/local/bin/ws-proxy.py << '_INNER_PY_'
import socket, threading, select, sys, os

CONFIG_FILE = "/etc/ssh-ws/config.conf"
BUFLEN = 8192
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 22

def get_response_header():
    status_code = "101"
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            for line in f:
                if line.startswith("HTTP_RESPONSE_CODE="):
                    status_code = line.split("=")[1].strip().replace('"', '')

    responses = {
        "101": b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n",
        "200": b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: keep-alive\r\n\r\n",
        "301": b"HTTP/1.1 301 Moved Permanently\r\nLocation: https://google.com\r\n\r\n",
        "404": b"HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\n\r\n"
    }
    return responses.get(status_code, responses["101"])

class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__(); self.host = host; self.port = port

    def run(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((self.host, self.port)); sock.listen(200)
        while True:
            try:
                client_sock, _ = sock.accept()
                threading.Thread(target=self.handle_client, args=(client_sock,), daemon=True).start()
            except Exception: break

    def handle_client(self, client_sock):
        target_sock = None
        try:
            request = client_sock.recv(BUFLEN)
            if not request: client_sock.close(); return
            client_sock.sendall(get_response_header())
            target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_sock.connect((TARGET_HOST, TARGET_PORT))
            sockets = [client_sock, target_sock]
            while True:
                r, _, _ = select.select(sockets, [], [], 60)
                if not r: break
                if client_sock in r:
                    data = client_sock.recv(BUFLEN)
                    if not data: break
                    target_sock.sendall(data)
                if target_sock in r:
                    data = target_sock.recv(BUFLEN)
                    if not data: break
                    client_sock.sendall(data)
        except Exception: pass
        finally:
            client_sock.close()
            if target_sock: target_sock.close()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = Server('0.0.0.0', port); server.start()
_INNER_PY_

    chmod +x /usr/local/bin/ws-proxy.py

    cat > /etc/systemd/system/ws-proxy.service << _INNER_SERVICE_
[Unit]
Description=Python WebSocket Payload Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py $PYTHON_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
_INNER_SERVICE_

    systemctl daemon-reload
    systemctl enable ws-proxy >/dev/null 2>&1
    systemctl restart ws-proxy
    echo -e "${GREEN}✔ Proxy Python activo en puerto $PYTHON_PORT.${NC}"
}

setup_stunnel() {
    [[ "$REDIRECT_TARGET" == "ssh" ]] && DEST_PORT=22 || DEST_PORT=$PYTHON_PORT

    echo -e "\n${BLUE}${BOLD}[ 4 / 5 ] Configurando STunnel (Puerto 443 -> $DEST_PORT)...${NC}"
    
    cat > /etc/stunnel/stunnel.conf << _INNER_STUNNEL_
pid = /var/run/stunnel.pid
debug = info
output = /var/log/stunnel.log
syslog = no

cert = $CERT_PATH/fullchain.pem
key = $CERT_PATH/privkey.pem

sslVersion = TLSv1.2
ciphers = HIGH:!aNULL:!MD5

[ssh-ws-ssl]
accept = 0.0.0.0:443
connect = 127.0.0.1:$DEST_PORT
TIMEOUTclose = 0
TIMEOUTconnect = 10
TIMEOUTidle = 86400
_INNER_STUNNEL_

    echo 'ENABLED=1' > /etc/default/stunnel4 2>/dev/null
    echo 'ENABLED=1' > /etc/default/stunnel 2>/dev/null
    STUNNEL_BIN=$(which stunnel4 || which stunnel || which stunnel5 || echo "/usr/bin/stunnel4")

    cat > /etc/systemd/system/stunnel4.service << _INNER_STUNNEL_SERVICE_
[Unit]
Description=STunnel TLS/SSL Tunnel
After=network.target

[Service]
Type=forking
ExecStart=$STUNNEL_BIN /etc/stunnel/stunnel.conf
ExecStop=/bin/killall stunnel stunnel4
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
_INNER_STUNNEL_SERVICE_

    cp /etc/systemd/system/stunnel4.service /etc/systemd/system/stunnel.service 2>/dev/null
    systemctl daemon-reload
    systemctl enable stunnel4 >/dev/null 2>&1 || systemctl enable stunnel >/dev/null 2>&1
    systemctl restart stunnel4 >/dev/null 2>&1 || systemctl restart stunnel >/dev/null 2>&1
    echo -e "${GREEN}✔ STunnel configurado correctamente.${NC}"
}

finalize_installation() {
    echo -e "\n${BLUE}${BOLD}[ 5 / 5 ] Instalando Comando 'ssl'...${NC}"
    
    # ÚNICAMENTE SE CREA /usr/local/bin/ssl (No toca /usr/local/bin/menu)
    cat > /usr/local/bin/ssl << '_INNER_MENU_'
#!/bin/bash
while read -r -t 0.2 discard; do :; done 2>/dev/null

CONFIG_DIR="/etc/ssh-ws"
CONFIG_FILE="$CONFIG_DIR/config.conf"

SYS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
SYS_OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Linux")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

load_conf() { [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"; }

save_conf() {
    cat > "$CONFIG_FILE" << _SAV_CONF_
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
CERT_TYPE="$CERT_TYPE"
REDIRECT_TARGET="$REDIRECT_TARGET"
PYTHON_PORT="$PYTHON_PORT"
HTTP_RESPONSE_CODE="$HTTP_RESPONSE_CODE"
CERT_PATH="$CERT_PATH"
_SAV_CONF_
}

header() {
    load_conf
    clear
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e "${CYAN}${BOLD}       PANEL DE CONTROL SSH WEBSOCKET SSL           ${NC}"
    echo -e "${CYAN}${BOLD}====================================================${NC}"
    echo -e " ${WHITE}Sistema / ARQ   :${NC} ${GREEN}${BOLD}$SYS_OS ($SYS_ARCH)${NC}"
    echo -e " ${WHITE}Dominio Actual  :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${WHITE}Destino SSL 443 :${NC} ${GREEN}${BOLD}$REDIRECT_TARGET ($PYTHON_PORT)${NC}"
    if [[ "$REDIRECT_TARGET" == "python" ]]; then
        echo -e " ${WHITE}Payload HTTP    :${NC} ${GREEN}${BOLD}HTTP $HTTP_RESPONSE_CODE${NC}"
    fi
    echo -e " ${WHITE}Certificado SSL :${NC} ${CYAN}${BOLD}$CERT_TYPE${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
}

switch_redirect_target() {
    header
    echo -e "${PURPLE}${BOLD}[ CAMBIAR DESTINO DE REDIRECCION ]${NC}\n"
    echo -e " ${WHITE}[ 1 ]${NC} ${GREEN}Python Proxy${NC} ${CYAN}(Soporta Payloads / WebSockets)${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${GREEN}SSH Directo (Puerto 22)${NC} ${CYAN}(SSL Directo sin Payload)${NC}"
    echo -e -n "\n${YELLOW}➜ Selecciona una opcion [1-2]: ${NC}"
    read -r opt
    case $opt in
        1)
            REDIRECT_TARGET="python"
            echo -e -n "\n${CYAN}Puerto de Python Proxy [Default 8080]: ${NC}"
            read -r new_py
            PYTHON_PORT=${new_py:-8080}
            if [[ "$HTTP_RESPONSE_CODE" == "N/A" ]]; then HTTP_RESPONSE_CODE="101"; fi
            save_conf
            systemctl restart ws-proxy
            sed -i "s/connect = 127.0.0.1:.*/connect = 127.0.0.1:$PYTHON_PORT/" /etc/stunnel/stunnel.conf
            systemctl restart stunnel4 2>/dev/null || systemctl restart stunnel 2>/dev/null
            echo -e "${GREEN}✔ Redirigido a Python Proxy ($PYTHON_PORT).${NC}"
            ;;
        2)
            REDIRECT_TARGET="ssh"
            PYTHON_PORT="22"
            HTTP_RESPONSE_CODE="N/A"
            save_conf
            systemctl stop ws-proxy 2>/dev/null
            sed -i "s/connect = 127.0.0.1:.*/connect = 127.0.0.1:22/" /etc/stunnel/stunnel.conf
            systemctl restart stunnel4 2>/dev/null || systemctl restart stunnel 2>/dev/null
            echo -e "${GREEN}✔ Redirigido a SSH Directo (22).${NC}"
            ;;
    esac
    read -r _
}

change_http_response() {
    header
    if [[ "$REDIRECT_TARGET" == "ssh" ]]; then
        echo -e "${RED}[!] Activa el modo Python Proxy para cambiar el código de respuesta.${NC}"
        read -r _; return
    fi
    echo -e "${PURPLE}${BOLD}[ CAMBIAR RESPUESTA HTTP PAYLOAD ]${NC}\n"
    echo -e " ${WHITE}[ 1 ]${NC} ${GREEN}101 Switching Protocols${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${CYAN}200 OK${NC}"
    echo -e " ${WHITE}[ 3 ]${NC} ${YELLOW}301 Moved Permanently${NC}"
    echo -e " ${WHITE}[ 4 ]${NC} ${RED}404 Not Found${NC}"
    echo -e -n "\n${YELLOW}➜ Selecciona una opcion [1-4]: ${NC}"
    read -r opt
    case $opt in
        1) HTTP_RESPONSE_CODE="101" ;; 2) HTTP_RESPONSE_CODE="200" ;; 3) HTTP_RESPONSE_CODE="301" ;; 4) HTTP_RESPONSE_CODE="404" ;; *) return ;;
    esac
    save_conf; systemctl restart ws-proxy
    echo -e "${GREEN}✔ Respuesta cambiada a HTTP $HTTP_RESPONSE_CODE.${NC}"
    read -r _
}

renew_cert() {
    header
    echo -e "${PURPLE}${BOLD}[ RENOVACION / CAMBIO DE CERTIFICADO SSL ]${NC}\n"
    echo -e " ${WHITE}[ 1 ]${NC} ${GREEN}Renovar Let's Encrypt (Certbot)${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${YELLOW}Cambiar a Certificado Autofirmado (OpenSSL)${NC}"
    echo -e -n "\n${YELLOW}➜ Selecciona una opcion [1-2]: ${NC}"
    read -r opt
    case $opt in
        1) systemctl stop stunnel4 stunnel 2>/dev/null; certbot renew; systemctl start stunnel4 2>/dev/null || systemctl start stunnel 2>/dev/null; echo -e "${GREEN}✔ Certificado renovado.${NC}" ;;
        2)
            mkdir -p /etc/stunnel/certs
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/stunnel/certs/privkey.pem -out /etc/stunnel/certs/fullchain.pem -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" >/dev/null 2>&1
            CERT_PATH="/etc/stunnel/certs"; CERT_TYPE="selfsigned"; save_conf
            sed -i "s|cert = .*|cert = $CERT_PATH/fullchain.pem|" /etc/stunnel/stunnel.conf
            sed -i "s|key = .*|key = $CERT_PATH/privkey.pem|" /etc/stunnel/stunnel.conf
            systemctl restart stunnel4 2>/dev/null || systemctl restart stunnel 2>/dev/null
            echo -e "${GREEN}✔ Cambiado a Autofirmado.${NC}"
            ;;
    esac
    read -r _
}

view_info() {
    header
    echo -e "${PURPLE}${BOLD}[ INFORMACION TECNICA Y PAYLOADS ]${NC}\n"
    echo -e " ${WHITE}• Dominio / SNI   :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${WHITE}• Puerto SSL 443  :${NC} ${GREEN}${BOLD}ACTIVO${NC}"
    echo -e " ${WHITE}• Destino Actual  :${NC} ${CYAN}${BOLD}$REDIRECT_TARGET ($PYTHON_PORT)${NC}"
    if [[ "$REDIRECT_TARGET" == "python" ]]; then echo -e " ${WHITE}• Respuesta HTTP  :${NC} ${GREEN}${BOLD}$HTTP_RESPONSE_CODE${NC}"; fi
    echo -e "\n${CYAN}${BOLD}── Configuración en Apps VPN ──${NC}"
    echo -e " ${WHITE}• IP / Host       :${NC} ${YELLOW}$DOMAIN${NC}"
    echo -e " ${WHITE}• Puerto          :${NC} ${GREEN}443${NC}"
    echo -e " ${WHITE}• SNI / Bug Host  :${NC} ${YELLOW}$DOMAIN${NC}"
    echo -e " ${WHITE}• Ej. Payload     :${NC} ${CYAN}GET / HTTP/1.1[crlf]Host: $DOMAIN[crlf]Upgrade: websocket[crlf][crlf]${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
    read -r _
}

while true; do
    header
    echo -e " ${WHITE}[ 1 ]${NC} ${CYAN}Cambiar Destino (Python Proxy <-> SSH 22)${NC}"
    echo -e " ${WHITE}[ 2 ]${NC} ${GREEN}Cambiar Respuesta HTTP Payload (101, 200, 301, 404)${NC}"
    echo -e " ${WHITE}[ 3 ]${NC} ${CYAN}Renovar / Cambiar Certificado SSL${NC}"
    echo -e " ${WHITE}[ 4 ]${NC} ${GREEN}Ver Informacion de Conexion y Payloads${NC}"
    echo -e " ${WHITE}[ 5 ]${NC} ${CYAN}Ver Logs en Tiempo Real${NC}"
    echo -e " ${WHITE}[ 6 ]${NC} ${GREEN}Reiniciar Servicios (STunnel / Python)${NC}"
    echo -e " ${WHITE}[ 7 ]${NC} ${RED}Desinstalar Todo${NC}"
    echo -e " ${WHITE}[ 0 ]${NC} ${YELLOW}Salir${NC}"
    echo -e "${CYAN}${BOLD}----------------------------------------------------${NC}"
    echo -e -n "${YELLOW}➜ ${NC}Selecciona una opcion [0-7]: "
    read -r op

    case $op in
        1) switch_redirect_target ;;
        2) change_http_response ;;
        3) renew_cert ;;
        4) view_info ;;
        5) tail -f /var/log/stunnel.log ;;
        6) systemctl restart stunnel4 2>/dev/null || systemctl restart stunnel 2>/dev/null; [[ "$REDIRECT_TARGET" == "python" ]] && systemctl restart ws-proxy; echo -e "${GREEN}✔ Reiniciado.${NC}"; sleep 1 ;;
        7)
            echo -e -n "\n${RED}¿Esta SEGURO de eliminar todo el servicio SSL? (s/n): ${NC}"
            read -r confirm
            if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                systemctl stop stunnel4 stunnel ws-proxy 2>/dev/null
                systemctl disable stunnel4 stunnel ws-proxy 2>/dev/null
                rm -f /etc/systemd/system/stunnel4.service /etc/systemd/system/stunnel.service /etc/systemd/system/ws-proxy.service
                rm -rf /etc/stunnel/stunnel.conf /usr/local/bin/ws-proxy.py $CONFIG_DIR /usr/local/bin/ssl
                systemctl daemon-reload
                echo -e "${GREEN}✔ Desinstalado completamente.${NC}"; exit 0
            fi ;;
        0) exit 0 ;;
    esac
done
_INNER_MENU_

    chmod +x /usr/local/bin/ssl
}

# -------------------------------------------------------------------
# EJECUCIÓN PRINCIPAL
# -------------------------------------------------------------------

print_banner
install_dependencies
prompt_installation_data
setup_ssl_certificate
setup_python_proxy
setup_stunnel
finalize_installation

sleep 2

if systemctl is-active --quiet stunnel4 || systemctl is-active --quiet stunnel; then
    echo -e "\n${GREEN}${BOLD}====================================================${NC}"
    echo -e "${GREEN}${BOLD}       ¡INSTALACION COMPLETADA CON EXITO!           ${NC}"
    echo -e "${GREEN}${BOLD}====================================================${NC}"
    echo -e " ${PURPLE}${BOLD}Sistema / ARQ  :${NC} ${GREEN}${BOLD}$SYS_OS ($SYS_ARCH)${NC}"
    echo -e " ${PURPLE}${BOLD}Dominio        :${NC} ${YELLOW}${BOLD}$DOMAIN${NC}"
    echo -e " ${PURPLE}${BOLD}Puerto SSL 443 :${NC} ${GREEN}${BOLD}ACTIVO${NC}"
    echo -e " ${PURPLE}${BOLD}Comando Panel  :${NC} ${YELLOW}${BOLD}ssl${NC}"
    echo -e "${GREEN}${BOLD}----------------------------------------------------${NC}\n"
    sleep 2
    /usr/local/bin/ssl
else
    echo -e "\n${RED}${BOLD}[✗] STunnel fallo al arrancar. Revisa los logs con: journalctl -u stunnel4 -n 20${NC}\n"
fi
_OUTER_EOF_

chmod +x /usr/local/bin/install_ssh_ws.sh
/usr/local/bin/install_ssh_ws.sh
