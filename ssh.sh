#!/bin/bash
# ==============================================================================
# 🔥 SCRIPT DE INSTALACIÓN Y CONFIGURACIÓN SSH PARA VPS
# ==============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# FUNCIONES
# ==============================================================================
print_message() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
print_info() { echo -e "${BLUE}[→]${NC} $1"; }
print_title() { echo -e "${CYAN}════════════════════════════════════════════════════${NC}"; }

# ==============================================================================
# VERIFICAR ROOT
# ==============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Ejecuta como root: sudo bash $0"
    fi
}

# ==============================================================================
# DETECTAR DISTRIBUCIÓN
# ==============================================================================
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        print_error "No se puede detectar el sistema operativo"
    fi
    print_info "Sistema detectado: $DISTRO $VERSION"
}

# ==============================================================================
# INSTALAR OPENSSH
# ==============================================================================
install_openssh() {
    print_info "Instalando/actualizando OpenSSH..."
    
    case $DISTRO in
        ubuntu|debian|linuxmint)
            apt update -qq
            apt install -y -qq openssh-server openssh-client
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if command -v dnf &> /dev/null; then
                dnf install -y -q openssh-server openssh-clients
            else
                yum install -y -q openssh-server openssh-clients
            fi
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm
            pacman -S --noconfirm openssh
            ;;
        *)
            print_error "Distribución no soportada: $DISTRO"
            ;;
    esac
    
    print_message "OpenSSH instalado correctamente"
}

# ==============================================================================
# CONFIGURAR CONTRASEÑA ROOT (CORREGIDO PARA PROMPTS LIMPIOS)
# ==============================================================================
set_root_password() {
    print_title
    echo -e "${YELLOW}🔑 CONFIGURACIÓN DE CONTRASEÑA ROOT${NC}"
    print_title
    echo ""
    
    echo -e -n "${YELLOW}¿Deseas establecer una nueva contraseña para root? (s/N): ${NC}"
    read change_pass
    
    if [[ "$change_pass" =~ ^[Ss]$ ]]; then
        echo ""
        print_info "Ingresa la nueva contraseña para root:"
        
        while true; do
            echo -e -n "${BLUE}Nueva contraseña: ${NC}"
            read -s password1
            echo ""
            echo -e -n "${BLUE}Confirmar contraseña: ${NC}"
            read -s password2
            echo ""
            
            if [[ "$password1" == "$password2" ]]; then
                if [[ ${#password1} -ge 6 ]]; then
                    echo "root:$password1" | chpasswd
                    print_message "Contraseña de root actualizada correctamente"
                    break
                else
                    print_warning "La contraseña debe tener al menos 6 caracteres"
                fi
            else
                print_warning "Las contraseñas no coinciden, intenta de nuevo."
            fi
        done
    else
        print_info "Manteniendo la contraseña actual de root"
    fi
    
    # Desbloquear la cuenta root a nivel de sistema operativo
    passwd -u root 2>/dev/null
}

# ==============================================================================
# CREAR DIRECTORIO /run/sshd
# ==============================================================================
create_sshd_run_dir() {
    print_info "Verificando directorio /run/sshd..."
    
    if [[ ! -d /run/sshd ]]; then
        mkdir -p /run/sshd
        chmod 755 /run/sshd
        chown root:root /run/sshd
        print_message "Directorio /run/sshd creado"
        
        mkdir -p /etc/tmpfiles.d
        cat > /etc/tmpfiles.d/sshd.conf << EOF
d /run/sshd 0755 root root -
EOF
        print_message "Configuración persistente creada"
    else
        print_message "Directorio /run/sshd ya existe"
    fi
}

# ==============================================================================
# HACER BACKUP
# ==============================================================================
backup_sshd_config() {
    local backup_dir="/etc/ssh/backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/sshd_config_${timestamp}.bak"
    
    if [[ -f /etc/ssh/sshd_config ]]; then
        print_info "Creando backup de la configuración actual..."
        mkdir -p "$backup_dir"
        cp /etc/ssh/sshd_config "$backup_file"
        print_message "Backup: $backup_file"
    fi
}

# ==============================================================================
# CREAR CONFIGURACIÓN SSH (CORREGIDO Y OPTIMIZADO)
# ==============================================================================
create_sshd_config() {
    print_info "Creando nueva configuración SSH..."
    
    backup_sshd_config
    
    # Eliminar configuraciones de la nube que bloquean el login por contraseña
    rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf 2>/dev/null
    
    cat > /etc/ssh/sshd_config << 'SSHCONFIG'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp
SSHCONFIG

    chmod 600 /etc/ssh/sshd_config
    chown root:root /etc/ssh/sshd_config
    
    print_message "Configuración SSH creada"
}

# ==============================================================================
# VERIFICAR CONFIGURACIÓN
# ==============================================================================
test_ssh_config() {
    print_info "Verificando la configuración SSH..."
    
    create_sshd_run_dir
    
    if sshd -t 2>/dev/null; then
        print_message "Configuración válida"
        return 0
    else
        print_error "Error en la configuración"
        sshd -t
        return 1
    fi
}

# ==============================================================================
# REINICIAR SSH
# ==============================================================================
restart_ssh_service() {
    print_info "Reiniciando el servicio SSH..."
    
    create_sshd_run_dir
    
    if systemctl list-units --full -all | grep -q "ssh.service"; then
        systemctl daemon-reload
        systemctl restart ssh
        systemctl enable ssh
        print_message "Servicio SSH reiniciado (ssh)"
    elif systemctl list-units --full -all | grep -q "sshd.service"; then
        systemctl daemon-reload
        systemctl restart sshd
        systemctl enable sshd
        print_message "Servicio SSH reiniciado (sshd)"
    else
        print_warning "No se encontró el servicio, reinicio manual..."
        service ssh restart || service sshd restart || /etc/init.d/ssh restart
    fi
    
    sleep 2
    
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        print_message "Servicio SSH funcionando"
    else
        print_warning "Verifica el estado: systemctl status ssh"
    fi
}

# ==============================================================================
# MOSTRAR RESUMEN
# ==============================================================================
show_summary() {
    print_title
    echo -e "${GREEN}  ✅ CONFIGURACIÓN SSH COMPLETADA${NC}"
    print_title
    echo ""
    echo -e "${BLUE}📋 Configuración aplicada:${NC}"
    echo "  • Puerto: 22"
    echo "  • Root login: HABILITADO"
    echo "  • Contraseña: HABILITADA"
    echo "  • Clave pública: HABILITADA"
    echo ""
    echo -e "${BLUE}📌 Datos de conexión:${NC}"
    echo "  • Usuario: ${GREEN}root${NC}"
    echo "  • Contraseña: ${GREEN}La que acabas de configurar${NC}"
    echo "  • IP: Usa la IP pública de tu servidor"
    echo ""
    echo -e "${YELLOW}⚠️  PRUEBA LA CONEXIÓN ANTES DE CERRAR${NC}"
    echo "  • Comando local para probar: ssh root@localhost"
    print_title
}

# ==============================================================================
# EJECUCIÓN PRINCIPAL
# ==============================================================================
main() {
    clear
    print_title
    echo -e "${GREEN}  🔥 CONFIGURADOR SSH CON CONTRASEÑA ROOT 🔥${NC}"
    print_title
    echo ""
    
    check_root
    detect_distro
    set_root_password
    install_openssh
    create_sshd_config
    
    if test_ssh_config; then
        restart_ssh_service
        show_summary
    else
        print_error "No se pudo aplicar la configuración"
    fi
}

# ==============================================================================
# EJECUTAR SCRIPT
# ==============================================================================
main

