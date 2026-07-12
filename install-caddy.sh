#!/bin/bash

# =============================================
# Autoinstalador Caddy Server
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

# Verificar root
[[ $EUID -ne 0 ]] && error "Ejecutar como root: sudo bash $0"

# =============================================
# 0. SOLICITAR DOMINIO PARA CADDY
# =============================================
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║         CONFIGURACIÓN DE DOMINIO               ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Ingresa el dominio que usará Caddy para HTTPS:${NC}"
echo -e "${YELLOW}(Ejemplo: rust.freenethn.org)${NC}"
echo ""
read -p "➜ Dominio: " CADDY_DOMAIN

# Validar que no esté vacío
if [[ -z "$CADDY_DOMAIN" ]]; then
    error "No ingresaste un dominio. Ejecuta de nuevo."
fi

# Validar formato básico (opcional)
if [[ ! "$CADDY_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${YELLOW}⚠️  El dominio parece inválido. Asegúrate de usar formato: dominio.com${NC}"
    echo -e "${BLUE}¿Quieres continuar igual? (s/N)${NC}"
    read -p "➜ " confirmar
    if [[ ! "$confirmar" =~ ^[sS]$ ]]; then
        error "Instalación cancelada."
    fi
fi

echo ""
info "Usando dominio: ${GREEN}$CADDY_DOMAIN${NC}"
echo ""

# =============================================
# 1. Instalar Caddy desde repositorio oficial
# =============================================
step "Instalando dependencias y Caddy..."
apt update -qq
apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

apt update -qq
apt install -y -qq caddy

if ! command -v caddy &>/dev/null; then
    error "Hubo un problema instalando Caddy."
fi
info "Caddy instalado correctamente: $(caddy version | awk '{print $1}')"

# =============================================
# 2. Aplicar tu Caddyfile Exacto CON DOMINIO EDITABLE
# =============================================
step "Creando /etc/caddy/Caddyfile..."

# Backup del original
mv /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null

# Usar un heredoc que reemplazará la variable CADDY_DOMAIN
cat > /etc/caddy/Caddyfile << EOF
{
    auto_https disable_redirects
}

# ========================================================
# ENRUTADOR DINÁMICO - MULTIPUERTO HTTP
# ========================================================
:80, :8880, :2052, :2082, :2086, :2095 {
    
    @dinamico_http path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_http {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} {
            flush_interval -1
        }
    }

    handle {
        reverse_proxy 127.0.0.1:8080 {
            flush_interval -1
        }
    }
}

# ========================================================
# ENRUTADOR DINÁMICO - MULTIPUERTO HTTPS
# ========================================================
${CADDY_DOMAIN}:443, ${CADDY_DOMAIN}:8443, ${CADDY_DOMAIN}:2053, ${CADDY_DOMAIN}:2083 {
    
    @dinamico_https path_regexp puerto ^/puerto_(?P<target>[0-9]+)(/.*)?$
    handle @dinamico_https {
        uri strip_prefix /puerto_{re.puerto.target}
        reverse_proxy 127.0.0.1:{re.puerto.target} {
            flush_interval -1
        }
    }

    handle {
        reverse_proxy 127.0.0.1:8080 {
            flush_interval -1
        }
    }
}
EOF

info "Caddyfile guardado con dominio: ${GREEN}$CADDY_DOMAIN${NC}"

# =============================================
# 3. Reiniciar servicio
# =============================================
step "Reiniciando Caddy..."
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

sleep 2

if systemctl is-active --quiet caddy; then
    info "Caddy está activo y corriendo."
else
    error "Caddy falló al arrancar. Revisa los logs con: journalctl -u caddy --no-pager | tail -n 20"
fi

# =============================================
# 4. Mostrar resumen
# =============================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             ✅ Caddy Instalado!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📌 Resumen de configuración:${NC}"
echo -e "   Dominio configurado: ${GREEN}$CADDY_DOMAIN${NC}"
echo ""
echo -e "${BLUE}🔌 Puertos HTTPS:${NC}"
echo "   • ${CADDY_DOMAIN}:443"
echo "   • ${CADDY_DOMAIN}:8443"
echo "   • ${CADDY_DOMAIN}:2053"
echo "   • ${CADDY_DOMAIN}:2083"
echo ""
echo -e "${BLUE}📋 Comandos útiles:${NC}"
echo "   systemctl status caddy"
echo "   systemctl restart caddy"
echo "   journalctl -u caddy -f"
echo ""
echo -e "${BLUE}📁 Archivo de configuración:${NC}"
echo "   /etc/caddy/Caddyfile"
echo ""
info "Instalación completada exitosamente!"
