#!/bin/bash
# =============================================
# ACTIVAR PUERTOS CON FIREWALLD
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
# MENÚ PRINCIPAL
# =============================================
clear
echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║         CONFIGURACIÓN DE FIREWALLD            ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Selecciona una opción:${NC}"
echo "  1) Instalar firewalld"
echo "  2) Abrir TODOS los puertos TCP (1-65535)"
echo "  3) Abrir TODOS los puertos UDP (1-65535)"
echo "  4) Abrir TODOS los puertos TCP y UDP (1-65535)"
echo "  5) Recargar firewalld"
echo "  6) Ver puertos abiertos"
echo "  7) Iniciar firewalld"
echo "  8) Habilitar firewalld (inicio automático)"
echo "  9) Ver estado de firewalld"
echo "  10) Salir"
echo ""
read -p "➜ Opción: " OPCION

# =============================================
# FUNCIONES
# =============================================
instalar_firewalld() {
    step "Instalando firewalld..."
    apt-get update -qq
    apt-get install -y -qq firewalld
    info "firewalld instalado correctamente"
}

abrir_tcp() {
    step "Abriendo TODOS los puertos TCP (1-65535)..."
    sudo firewall-cmd --zone=public --permanent --add-port=1-65535/tcp
    info "Puertos TCP abiertos"
}

abrir_udp() {
    step "Abriendo TODOS los puertos UDP (1-65535)..."
    sudo firewall-cmd --zone=public --permanent --add-port=1-65535/udp
    info "Puertos UDP abiertos"
}

abrir_tcp_udp() {
    step "Abriendo TODOS los puertos TCP y UDP (1-65535)..."
    sudo firewall-cmd --zone=public --permanent --add-port=1-65535/tcp
    sudo firewall-cmd --zone=public --permanent --add-port=1-65535/udp
    info "Puertos TCP y UDP abiertos"
}

recargar() {
    step "Recargando firewalld..."
    sudo firewall-cmd --reload
    info "firewalld recargado"
}

ver_puertos() {
    echo ""
    echo -e "${BLUE}📋 Puertos abiertos:${NC}"
    sudo firewall-cmd --zone=public --list-ports
    echo ""
}

iniciar() {
    step "Iniciando firewalld..."
    sudo systemctl start firewalld
    info "firewalld iniciado"
}

habilitar() {
    step "Habilitando firewalld (inicio automático)..."
    sudo systemctl enable firewalld --now
    info "firewalld habilitado"
}

ver_estado() {
    echo ""
    echo -e "${BLUE}📋 Estado de firewalld:${NC}"
    sudo systemctl status firewalld --no-pager
    echo ""
}

# =============================================
# EJECUTAR OPCIÓN
# =============================================
case $OPCION in
    1)
        instalar_firewalld
        ;;
    2)
        abrir_tcp
        recargar
        ver_puertos
        ;;
    3)
        abrir_udp
        recargar
        ver_puertos
        ;;
    4)
        abrir_tcp_udp
        recargar
        ver_puertos
        ;;
    5)
        recargar
        ;;
    6)
        ver_puertos
        ;;
    7)
        iniciar
        ;;
    8)
        habilitar
        ;;
    9)
        ver_estado
        ;;
    10)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        error "Opción inválida"
        ;;
esac

# =============================================
# RESUMEN
# =============================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✅ FIREWALLD CONFIGURADO!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Comandos útiles:${NC}"
echo "   firewall-cmd --zone=public --list-ports      # Ver puertos"
echo "   firewall-cmd --zone=public --add-port=80/tcp # Abrir puerto específico"
echo "   firewall-cmd --reload                        # Recargar reglas"
echo "   systemctl status firewalld                   # Ver estado"
echo "   systemctl restart firewalld                  # Reiniciar"
echo ""

info "Operación completada exitosamente!"
