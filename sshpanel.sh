#!/bin/bash
# =============================================
# INSTALADOR SSH PANEL
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
# INSTALAR SSH PANEL
# =============================================
step "Instalando SSH Panel..."

# Configuración con token
TOKEN="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"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

# Descargar sshpanel.sh
curl -sL -H "Authorization: token $TOKEN" "$BASE_URL/sshpanel.sh" -o /usr/local/bin/sshpanel.sh

# Verificar que se descargó
if [ ! -f /usr/local/bin/sshpanel.sh ]; then
    error "No se pudo descargar sshpanel.sh"
fi

# Dar permisos
chmod +x /usr/local/bin/sshpanel.sh

# Crear alias
if ! grep -q "alias sshpanel=" ~/.bashrc; then
    echo "alias sshpanel='sudo /usr/local/bin/sshpanel.sh'" >> ~/.bashrc
    info "Alias 'sshpanel' agregado a ~/.bashrc"
fi

# Crear enlace simbólico
ln -sf /usr/local/bin/sshpanel.sh /usr/local/bin/sshpanel 2>/dev/null

info "SSH Panel instalado correctamente"

# =============================================
# RESUMEN
# =============================================
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║         ✅ SSH PANEL INSTALADO! 🚀             ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}📋 Comandos para usar:${NC}"
echo "   sshpanel                        # Ejecutar el panel"
echo "   sudo /usr/local/bin/sshpanel.sh # Ejecutar directamente"
echo ""
echo -e "${BLUE}📁 Archivos:${NC}"
echo "   Script: /usr/local/bin/sshpanel.sh"
echo ""
echo -e "${YELLOW}💡 Para usar el alias inmediatamente:${NC}"
echo "   source ~/.bashrc"
echo "   sshpanel"
echo ""

info "Instalación completada exitosamente!"
