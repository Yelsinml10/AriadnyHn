#!/bin/bash

# =================================================================
# PANEL ADMINISTRATIVO DE NGINX PROXY & CERTBOT SSL
# CON AUTO-INSTALACIÓN AUTOMÁTICA DEL COMANDO: MenuN
# ROUTING: SSH-WS (8888) | XRAY/V2RAY (9090) | PUERTO DINÁMICO
# =================================================================

# ==========================================
# AUTO-REGISTRO DEL COMANDO MenuN EN EL SISTEMA
# ==========================================
SELF_PATH="${BASH_SOURCE[0]:-$0}"
if [ -f "$SELF_PATH" ]; then
    REAL_PATH=$(readlink -f "$SELF_PATH" 2>/dev/null || echo "$SELF_PATH")
    if [ "$REAL_PATH" != "/usr/local/bin/MenuN" ]; then
        rm -f /usr/local/bin/nginx /usr/local/bin/menu /usr/local/bin/proxy /usr/local/bin/ng /usr/local/bin/panel 2>/dev/null
        cp -f "$REAL_PATH" /usr/local/bin/MenuN 2>/dev/null
        ln -sf /usr/local/bin/MenuN /usr/local/bin/menun 2>/dev/null
        chmod +x /usr/local/bin/MenuN /usr/local/bin/menun 2>/dev/null
    fi
fi

CONFIG_FILE="/etc/proxy_panel.conf"
NGINX_CONF="/etc/nginx/sites-available/proxy_panel.conf"
NGINX_LINK="/etc/nginx/sites-enabled/proxy_panel.conf"

# ==========================================
# PALETA DE COLORES ANSI COMPLETA
# ==========================================
RESET='\033[0m'
BOLD='\033[1m'

C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_MAGENTA='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'

# ==========================================
# VERIFICACIÓN DE PERMISOS Y ARQUITECTURA
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}${BOLD}[!] Este script debe ejecutarse como ROOT (sudo).${RESET}"
  exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_NAME="AMD64 / x86_64" ;;
    aarch64|arm64) ARCH_NAME="ARM64 / aarch64" ;;
    armv7l|armhf)  ARCH_NAME="ARMv7 / 32-bit" ;;
    *)       ARCH_NAME="Desconocida ($ARCH)" ;;
esac

# Detectar Gestor de Paquetes
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MAN="apt-get"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update -y"
        CRON_PKG="cron"
    elif command -v dnf &>/dev/null; then
        PKG_MAN="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update"
        CRON_PKG="cronie"
    elif command -v yum &>/dev/null; then
        PKG_MAN="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update"
        CRON_PKG="cronie"
    else
        echo -e "${C_RED}[!] No se detectó un gestor de paquetes compatible.${RESET}"
        exit 1
    fi
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        HTTP_PORTS=$(echo "$HTTP_PORTS" | tr -d ',' | xargs)
        HTTPS_PORTS=$(echo "$HTTPS_PORTS" | tr -d ',' | xargs)
    fi
}

save_config() {
    HTTP_PORTS=$(echo "$HTTP_PORTS" | tr -d ',' | xargs)
    HTTPS_PORTS=$(echo "$HTTPS_PORTS" | tr -d ',' | xargs)
    cat <<EOF > "$CONFIG_FILE"
DOMAIN="$DOMAIN"
HTTP_PORTS="$HTTP_PORTS"
HTTPS_PORTS="$HTTPS_PORTS"
EOF
}

# ==========================================
# CONFIGURACIÓN DE RENOVACIÓN AUTOMÁTICA SSL
# ==========================================
setup_auto_renew_ssl() {
    echo -e "${C_CYAN}${BOLD}[*] Configurando renovación SSL automática (Cron + Certbot Hooks)...${RESET}"
    
    mkdir -p /etc/letsencrypt/renewal-hooks/pre
    mkdir -p /etc/letsencrypt/renewal-hooks/post
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy

    cat <<'EOF' > /etc/letsencrypt/renewal-hooks/pre/stop_nginx.sh
#!/bin/bash
systemctl stop nginx
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/pre/stop_nginx.sh

    cat <<'EOF' > /etc/letsencrypt/renewal-hooks/post/start_nginx.sh
#!/bin/bash
systemctl start nginx
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/post/start_nginx.sh

    cat <<'EOF' > /etc/letsencrypt/renewal-hooks/deploy/reload_nginx.sh
#!/bin/bash
systemctl reload nginx
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload_nginx.sh

    systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null
    systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null

    (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "30 3 * * * certbot renew --quiet") | crontab -
    
    echo -e "${C_GREEN}${BOLD}[✓] Renovación automática SSL activada (Diaria 3:30 AM).${RESET}"
}

# Generación del Certificado SSL
obtain_ssl() {
    echo -e "${C_YELLOW}${BOLD}[*] Solicitando Certificado SSL (Certbot) para $DOMAIN...${RESET}"
    systemctl stop nginx 2>/dev/null
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    systemctl start nginx
    
    setup_auto_renew_ssl
}

# ==========================================
# CONSTRUCTOR DINÁMICO DE NGINX
# ==========================================
build_nginx_config() {
    save_config
    local http_listen=""
    local https_listen=""

    for port in $HTTP_PORTS; do
        if [ -n "$port" ]; then
            http_listen+="    listen $port;\n    listen [::]:$port;\n"
        fi
    done

    for port in $HTTPS_PORTS; do
        if [ -n "$port" ]; then
            https_listen+="    listen $port ssl;\n    listen [::]:$port ssl;\n"
        fi
    done

    cat <<EOF > /tmp/nginx_panel.tmp
# ==========================================
# BLOQUE HTTP DINÁMICO
# ==========================================
server {
$(echo -e "$http_listen")
    server_name $DOMAIN;

    # SSH-WS (SSH Go, Python, Rust, C, etc. AL PUERTO INTERNO 8888)
    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }

    # Redirección de Protocolos Xray / V2Ray AL PUERTO INTERNO 9090
    location /vless {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /trojan {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /xray {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /v2ray {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # ENRUTADOR DINÁMICO POR PUERTO: /puerto_XXXX/ -> puerto XXXX
    location ~ ^/puerto_(?<target_port>[0-9]+)/ {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:\$target_port/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}

# ==========================================
# BLOQUE HTTPS (SSL) DINÁMICO
# ==========================================
server {
$(echo -e "$https_listen")
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # SSH-WS Seguro (SSH Go, Python, Rust, C, etc. AL PUERTO INTERNO 8888)
    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }

    # Redirección de Protocolos Xray / V2Ray SSL AL PUERTO INTERNO 9090
    location /vless {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /trojan {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /xray {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /v2ray {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # ENRUTADOR DINÁMICO SSL: /puerto_XXXX/ -> puerto XXXX
    location ~ ^/puerto_(?<target_port>[0-9]+)/ {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:\$target_port/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

    mv /tmp/nginx_panel.tmp "$NGINX_CONF"
    mkdir -p /etc/nginx/sites-enabled
    ln -sf "$NGINX_CONF" "$NGINX_LINK"
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    
    # Recargar Nginx suavemente
    if [ -f /usr/sbin/nginx ]; then
        /usr/sbin/nginx -t && systemctl reload nginx
    else
        /usr/bin/nginx -t && systemctl reload nginx
    fi
}

# ==========================================
# ASISTENTE DE PRIMERA INSTALACIÓN
# ==========================================
first_install() {
    clear
    echo -e "${C_BLUE}==================================================${RESET}"
    echo -e "${C_CYAN}${BOLD}       CONFIGURACIÓN INICIAL NGINX PROXY          ${RESET}"
    echo -e "${C_BLUE}==================================================${RESET}\n"

    detect_pkg_manager
    echo -e "${C_CYAN}[i] Arquitectura:${RESET} ${C_YELLOW}${BOLD}$ARCH_NAME${RESET}"
    echo -e "${C_CYAN}[i] Gestor Pkg:${RESET}   ${C_YELLOW}${BOLD}$PKG_MAN${RESET}\n"

    echo -e "${C_YELLOW}[*] Instalando dependencias...${RESET}"
    $PKG_UPDATE
    $PKG_INSTALL nginx certbot curl jq socat tar unzip $CRON_PKG

    echo -e "\n${BOLD}${C_MAGENTA}--- INGRESA LOS DATOS ---${RESET}"
    read -p "$(echo -e "${C_WHITE}${BOLD}Dominio principal: ${RESET}")" DOMAIN
    read -p "$(echo -e "${C_WHITE}${BOLD}Puertos HTTP (ej: 80 8080): ${RESET}")" HTTP_PORTS
    read -p "$(echo -e "${C_WHITE}${BOLD}Puertos HTTPS (ej: 443 8443): ${RESET}")" HTTPS_PORTS

    save_config
    obtain_ssl
    build_nginx_config

    echo -e "\n${C_GREEN}${BOLD}[✓] ¡Instalación y Auto-SSL completados con éxito!${RESET}"
    echo -e "${C_CYAN}${BOLD}[✓] Comando 'MenuN' instalado en el sistema.${RESET}"
    read -p "Presiona Enter para ir al menú..."
}

# ==========================================
# FUNCIONES DE GESTIÓN DEL MENÚ
# ==========================================
change_domain() {
    echo -e "\n${C_MAGENTA}${BOLD}--- CAMBIAR DOMINIO ---${RESET}"
    read -p "Nuevo dominio: " new_domain
    if [ -n "$new_domain" ]; then
        DOMAIN="$new_domain"
        save_config
        obtain_ssl
        build_nginx_config
        echo -e "${C_GREEN}${BOLD}[✓] Dominio cambiado a $DOMAIN${RESET}"
    fi
}

add_http_port() {
    read -p "Nuevo puerto HTTP: " port
    port=$(echo "$port" | tr -d ',')
    if [[ ! "$HTTP_PORTS" =~ (^|[[:space:]])$port($|[[:space:]]) ]]; then
        HTTP_PORTS="$HTTP_PORTS $port"
        build_nginx_config
        echo -e "${C_GREEN}${BOLD}[✓] Puerto HTTP $port agregado.${RESET}"
    else
        echo -e "${C_RED}${BOLD}[!] El puerto HTTP ya existe.${RESET}"
    fi
}

remove_http_port() {
    read -p "Puerto HTTP a remover: " port
    port=$(echo "$port" | tr -d ',')
    HTTP_PORTS=$(echo "$HTTP_PORTS" | sed -e "s/\b$port\b//" | xargs)
    build_nginx_config
    echo -e "${C_YELLOW}${BOLD}[-] Puerto HTTP $port eliminado.${RESET}"
}

add_https_port() {
    read -p "Nuevo puerto HTTPS SSL: " port
    port=$(echo "$port" | tr -d ',')
    if [[ ! "$HTTPS_PORTS" =~ (^|[[:space:]])$port($|[[:space:]]) ]]; then
        HTTPS_PORTS="$HTTPS_PORTS $port"
        build_nginx_config
        echo -e "${C_GREEN}${BOLD}[✓] Puerto HTTPS $port agregado.${RESET}"
    else
        echo -e "${C_RED}${BOLD}[!] El puerto HTTPS ya existe.${RESET}"
    fi
}

remove_https_port() {
    read -p "Puerto HTTPS a remover: " port
    port=$(echo "$port" | tr -d ',')
    HTTPS_PORTS=$(echo "$HTTPS_PORTS" | sed -e "s/\b$port\b//" | xargs)
    build_nginx_config
    echo -e "${C_YELLOW}${BOLD}[-] Puerto HTTPS $port eliminado.${RESET}"
}

test_ssl_renew() {
    echo -e "\n${C_CYAN}${BOLD}[*] Simulando renovación SSL...${RESET}"
    certbot renew --dry-run
    read -p "Presiona Enter para regresar..."
}

restart_services() {
    echo -e "${C_YELLOW}[*] Reiniciando Nginx...${RESET}"
    systemctl restart nginx
    echo -e "${C_GREEN}${BOLD}[✓] Nginx reiniciado.${RESET}"
}

view_status_logs() {
    clear
    echo -e "${C_BLUE}==================================================${RESET}"
    echo -e "${C_CYAN}${BOLD}             ESTATUS Y LOGS DEL SISTEMA           ${RESET}"
    echo -e "${C_BLUE}==================================================${RESET}\n"
    
    echo -e "${C_MAGENTA}${BOLD}=== ESTADO DETALLADO DEL SERVICIO NGINX ===${RESET}"
    systemctl status nginx --no-pager -l | head -n 12

    echo -e "\n${C_CYAN}${BOLD}=== TAREA AUTOMÁTICA RENOVACIÓN SSL ===${RESET}"
    crontab -l 2>/dev/null | grep "certbot renew" && echo -e "${C_GREEN}${BOLD}[ PROGRAMADO EN CRON ]${RESET}" || echo -e "${C_RED}${BOLD}[ NO PROGRAMADO ]${RESET}"

    echo -e "\n${C_CYAN}${BOLD}=== VENCIMIENTO CERTIFICADO SSL ===${RESET}"
    certbot certificates 2>/dev/null | grep -E "Certificate Name|Expiry Date" || echo "Sin certificados activos."

    echo -e "\n${C_CYAN}${BOLD}=== ÚLTIMOS LOGS DE ERROR DE NGINX ===${RESET}"
    tail -n 8 /var/log/nginx/error.log 2>/dev/null || echo "Sin logs de error."
    
    echo -e "\n"
    read -p "Presiona Enter para regresar..."
}

uninstall_script() {
    echo -e "\n${C_RED}${BOLD}==================================================${RESET}"
    echo -e "${C_RED}${BOLD}             DESINSTALACIÓN DEL SISTEMA           ${RESET}"
    echo -e "${C_RED}${BOLD}==================================================${RESET}"
    read -p "$(echo -e "${C_YELLOW}¿Deseas eliminar la configuración? (s/n): ${RESET}")" confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        systemctl stop nginx 2>/dev/null
        rm -f "$NGINX_CONF" "$NGINX_LINK" "$CONFIG_FILE"
        rm -f /usr/local/bin/MenuN /usr/local/bin/menun /usr/local/bin/nginx /usr/local/bin/menu /usr/local/bin/proxy /usr/local/bin/ng 2>/dev/null
        rm -f /etc/letsencrypt/renewal-hooks/pre/stop_nginx.sh
        rm -f /etc/letsencrypt/renewal-hooks/post/start_nginx.sh
        rm -f /etc/letsencrypt/renewal-hooks/deploy/reload_nginx.sh
        (crontab -l 2>/dev/null | grep -v "certbot renew") | crontab -
        systemctl start nginx 2>/dev/null
        echo -e "${C_RED}${BOLD}[✓] Configuración eliminada.${RESET}"
        exit 0
    fi
}

# Comprobar estado de la primera instalación
load_config
if [ -z "$DOMAIN" ]; then
    first_install
    load_config
else
    build_nginx_config
fi

# ==========================================
# MENÚ PRINCIPAL MULTICOLOR
# ==========================================
while true; do
    clear
    echo -e "${C_BLUE}==================================================${RESET}"
    echo -e "${C_CYAN}${BOLD}        PANEL DE CONTROL NGINX PROXY             ${RESET}"
    echo -e "${C_BLUE}==================================================${RESET}"
    echo -e "${C_WHITE}Arquitectura:${RESET} ${C_YELLOW}${BOLD}$ARCH_NAME${RESET}"
    echo -e "${C_WHITE}Dominio:     ${RESET} ${C_GREEN}${BOLD}$DOMAIN${RESET}"
    echo -e "${C_WHITE}Auto-SSL:    ${RESET} ${C_GREEN}${BOLD}ACTIVADO (Diario 3:30 AM)${RESET}"
    echo -e "${C_WHITE}Puertos HTTP:${RESET} ${C_YELLOW}${BOLD}[ $HTTP_PORTS ]${RESET}"
    echo -e "${C_WHITE}Puertos HTTPS:${RESET}${C_GREEN}${BOLD}[ $HTTPS_PORTS ]${RESET}"
    echo -e "${C_BLUE}--------------------------------------------------${RESET}"
    echo -e "${C_MAGENTA}${BOLD}Rutas Proxy:${RESET}"
    echo -e " ${C_CYAN}• /${RESET}                 ${C_WHITE}──> SSH-WS (127.0.0.1:8888)${RESET}"
    echo -e " ${C_CYAN}• /vless, /vmess...${RESET} ${C_WHITE}──> Xray   (127.0.0.1:9090)${RESET}"
    echo -e " ${C_CYAN}• /puerto_XXXX/${RESET}     ${C_WHITE}──> Dynamic (127.0.0.1:XXXX)${RESET}"
    echo -e "${C_BLUE}--------------------------------------------------${RESET}"
    echo -e " ${C_YELLOW}1)${RESET} ${C_CYAN}Cambiar Dominio y SSL${RESET}"
    echo -e " ${C_YELLOW}2)${RESET} ${C_GREEN}Agregar Puerto HTTP${RESET}"
    echo -e " ${C_YELLOW}3)${RESET} ${C_YELLOW}Quitar Puerto HTTP${RESET}"
    echo -e " ${C_YELLOW}4)${RESET} ${C_GREEN}Agregar Puerto HTTPS (SSL)${RESET}"
    echo -e " ${C_YELLOW}5)${RESET} ${C_YELLOW}Quitar Puerto HTTPS (SSL)${RESET}"
    echo -e " ${C_YELLOW}6)${RESET} ${C_BLUE}Probar Renovación SSL (Dry-Run)${RESET}"
    echo -e " ${C_YELLOW}7)${RESET} ${C_WHITE}${BOLD}Reiniciar Nginx${RESET}"
    echo -e " ${C_YELLOW}8)${RESET} ${C_CYAN}Ver Estatus y Logs${RESET}"
    echo -e " ${C_YELLOW}9)${RESET} ${C_MAGENTA}Desinstalar Configuración${RESET}"
    echo -e " ${C_RED}0)${RESET} ${C_RED}${BOLD}Salir del Panel${RESET}"
    echo -e "${C_BLUE}==================================================${RESET}"
    read -p "$(echo -e "${BOLD}${C_WHITE}Opción [0-9]: ${RESET}")" option

    case $option in
        1) change_domain; sleep 2 ;;
        2) add_http_port; sleep 2 ;;
        3) remove_http_port; sleep 2 ;;
        4) add_https_port; sleep 2 ;;
        5) remove_https_port; sleep 2 ;;
        6) test_ssl_renew ;;
        7) restart_services; sleep 2 ;;
        8) view_status_logs ;;
        9) uninstall_script ;;
        0) echo -e "${C_CYAN}¡Hasta luego!${RESET}"; exit 0 ;;
        *) echo -e "${C_RED}[!] Opción no válida.${RESET}"; sleep 1 ;;
    esac
done
