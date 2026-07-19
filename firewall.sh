#!/bin/bash
# ============================================================
# 🔥 FIREWALL DEFINITIVO PARA UBUNTU
# Abre TODOS los puertos sin restricciones
# ============================================================

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

# ============================================================
# MENÚ
# ============================================================
clear
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}     🔥 FIREWALL DEFINITIVO PARA UBUNTU 🔥${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Selecciona una opción:${NC}"
echo "  1)  🔓 Abrir TODOS los puertos (TCP + UDP) [RECOMENDADO]"
echo "  2)  🔒 Cerrar TODOS los puertos (solo SSH)"
echo "  3)  📋 Ver estado del firewall"
echo "  4)  📋 Ver puertos abiertos"
echo "  5)  Salir"
echo ""
read -p "➜ Opción: " OPCION

# ============================================================
# FUNCIONES
# ============================================================

abrir_todos() {
    step "Abriendo TODOS los puertos (TCP + UDP)..."
    
    # Detener UFW
    sudo systemctl stop ufw 2>/dev/null
    sudo systemctl disable ufw 2>/dev/null
    sudo ufw --force disable 2>/dev/null
    
    # Limpiar iptables
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    
    # Limpiar nftables
    sudo nft flush ruleset 2>/dev/null || true
    
    # Abrir todos los puertos con UFW
    sudo ufw allow 1:65535/tcp
    sudo ufw allow 1:65535/udp
    sudo ufw reload
    
    echo ""
    info "✅ TODOS los puertos TCP y UDP (1-65535) están ABIERTOS"
    echo ""
    sudo ufw status verbose
}

cerrar_todos() {
    step "Cerrando TODOS los puertos (solo SSH)..."
    
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp
    sudo ufw --force enable
    sudo ufw reload
    
    echo ""
    info "✅ Solo puerto SSH (22) abierto"
    sudo ufw status verbose
}

ver_estado() {
    echo ""
    echo -e "${BLUE}📋 Estado de UFW:${NC}"
    sudo ufw status verbose
    echo ""
    echo -e "${BLUE}📋 Reglas de iptables:${NC}"
    sudo iptables -L -n --line-numbers | head -20
}

ver_puertos() {
    echo ""
    echo -e "${BLUE}📋 Puertos abiertos en UFW:${NC}"
    sudo ufw status | grep "ALLOW" || echo "  No hay puertos abiertos"
    echo ""
    echo -e "${BLUE}📋 Puertos en escucha (servicios activos):${NC}"
    sudo ss -tulpn | grep LISTEN | column -t
}

# ============================================================
# EJECUTAR
# ============================================================
case $OPCION in
    1)
        abrir_todos
        ;;
    2)
        cerrar_todos
        ;;
    3)
        ver_estado
        ;;
    4)
        ver_puertos
        ;;
    5)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        error "Opción inválida"
        ;;
esac

echo ""
info "Operación completada exitosamente!"
