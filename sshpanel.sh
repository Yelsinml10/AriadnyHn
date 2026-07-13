# 1. Entrar a la carpeta del repositorio
cd ~/AriadnyHn

# 2. Crear el archivo install-sshpanel.sh
cat > install-sshpanel.sh << 'EOF'
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

[[ $EUID -ne 0 ]] && error "Ejecutar como root: sudo bash $0"

step "Instalando SSH Panel..."

TOKEN="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"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

curl -sL -H "Authorization: token $TOKEN" "$BASE_URL/sshpanel.sh" -o /usr/local/bin/sshpanel.sh

if [ ! -f /usr/local/bin/sshpanel.sh ]; then
    error "No se pudo descargar sshpanel.sh"
fi

chmod +x /usr/local/bin/sshpanel.sh

if ! grep -q "alias sshpanel=" ~/.bashrc; then
    echo "alias sshpanel='sudo /usr/local/bin/sshpanel.sh'" >> ~/.bashrc
    info "Alias 'sshpanel' agregado"
fi

ln -sf /usr/local/bin/sshpanel.sh /usr/local/bin/sshpanel 2>/dev/null

clear
echo -e "${GREEN}✅ SSH PANEL INSTALADO!${NC}"
echo ""
echo "Comandos:"
echo "  sshpanel"
echo "  sudo /usr/local/bin/sshpanel.sh"
echo ""
info "Instalación completada!"
EOF

# 3. Subir a GitHub
git add install-sshpanel.sh
git commit -m "Agregar instalador SSH Panel"
git push https://Yelsinml10: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@github.com/Yelsinml10/AriadnyHn.git main
