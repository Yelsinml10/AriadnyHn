#!/bin/bash
# ============================================================
# 🔥 FIREWALL DEFINITIVO PARA UBUNTU (CON INSTALADOR)
# ============================================================
# 📌 Este script INSTALA UFW si no está presente
# 📌 Abre TODOS los puertos (TCP + UDP)
# 📌 Funciona en Ubuntu 20.04, 22.04, 24.04
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
# FUNCIÓN: INSTALAR UFW
# ============================================================
instalar_ufw() {
    if ! command -v ufw &> /dev/null; then
        step "UFW no está instalado. Instalando..."
        apt-get update -qq
        apt-get install -y -qq ufw
        info "✅ UFW instalado correctamente"
    else
        info "UFW ya está instalado"
    fi
}

# ============================================================
# FUNCIÓN: ABRIR TODOS LOS PUERTOS
# ============================================================
abrir_todos() {
    step "Abriendo TODOS los puertos (TCP + UDP)..."
    
    # 1. Asegurar que UFW esté instalado
    instalar_ufw
    
    # 2. Detener UFW
    sudo systemctl stop ufw 2>/dev/null
    sudo systemctl disable ufw 2>/dev/null
    sudo ufw --force disable 2>/dev/null
    
    # 3. Limpiar iptables
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    
    # 4. Limpiar nftables
    sudo nft flush ruleset 2>/dev/null || true
    
    # 5. Abrir todos los puertos con UFW
    sudo ufw allow 1:65535/tcp
    sudo ufw allow 1:65535/udp
    sudo ufw reload
    
    echo ""
    info "✅ TODOS los puertos TCP y UDP (1-65535) están ABIERTOS"
    echo ""
    sudo ufw status verbose
}

# ============================================================
# FUNCIÓN: CONFIGURACIÓN SEGURA
# ============================================================
configuracion_segura() {
    step "Configurando firewall SEGURO..."
    
    instalar_ufw
    
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable
    sudo ufw reload
    
    echo ""
    info "✅ Configuración segura: SSH(22), HTTP(80), HTTPS(443)"
    sudo ufw status verbose
}

# ============================================================
# FUNCIÓN: DESACTIVAR COMPLETAMENTE
# ============================================================
desactivar_completo() {
    step "Desactivando firewall COMPLETAMENTE..."
    
    instalar_ufw
    
    sudo systemctl stop ufw
    sudo systemctl disable ufw
    sudo ufw --force disable
    
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    
    sudo nft flush ruleset 2>/dev/null || true
    
    info "✅ Firewall DESACTIVADO. TODOS los puertos están abiertos."
}

# ============================================================
# FUNCIÓN: VER ESTADO
# ============================================================
ver_estado() {
    echo ""
    echo -e "${BLUE}📋 Estado de UFW:${NC}"
    sudo ufw status verbose
    echo ""
    echo -e "${BLUE}📋 Reglas de iptables:${NC}"
    sudo iptables -L -n --line-numbers | head -20
}

# ============================================================
# FUNCIÓN: VER PUERTOS
# ============================================================
ver_puertos() {
    echo ""
    echo -e "${BLUE}📋 Puertos abiertos en UFW:${NC}"
    sudo ufw status | grep "ALLOW" || echo "  No hay puertos abiertos"
    echo ""
    echo -e "${BLUE}📋 Puertos en escucha:${NC}"
    sudo ss -tulpn | grep LISTEN | column -t
}

# ============================================================
# MENÚ PRINCIPAL
# ============================================================
clear
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}     🔥 FIREWALL DEFINITIVO PARA UBUNTU 🔥${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Selecciona una opción:${NC}"
echo "  1)  🔓 Abrir TODOS los puertos (TCP + UDP) [RECOMENDADO]"
echo "  2)  🔒 Configuración SEGURA (SSH + HTTP + HTTPS)"
echo "  3)  🔓 Desactivar firewall COMPLETAMENTE"
echo "  4)  📋 Ver estado del firewall"
echo "  5)  📋 Ver puertos abiertos"
echo "  6)  Salir"
echo ""
read -p "➜ Opción: " OPCION

# ============================================================
# EJECUTAR
# ============================================================
case $OPCION in
    1)
        abrir_todos
        ;;
    2)
        configuracion_segura
        ;;
    3)
        desactivar_completo
        ;;
    4)
        ver_estado
        ;;
    5)
        ver_puertos
        ;;
    6)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        error "Opción inválida"
        ;;
esac

echo ""
info "Operación completada exitosamente!"
