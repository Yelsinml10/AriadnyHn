#!/bin/bash
# ==============================================================================
# 🔥 SCRIPT DEFINITIVO DE SSH PARA VPS (DESBLOQUEO TOTAL DE ROOT)
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
print_info() { echo -e "${BLUE}[→]${NC} $1"; }
print_title() { echo -e "${CYAN}════════════════════════════════════════════════════${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Ejecuta como root: sudo bash $0"
    fi
}

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

set_root_password() {
    print_title
    echo -e "${YELLOW}🔑 CONFIGURACIÓN Y DESBLOQUEO DE ROOT${NC}"
    print_title
    echo ""
    
    # 1. ROMPER EL BLOQUEO DEL SISTEMA OPERATIVO
    print_info "Desbloqueando la cuenta root en el sistema..."
    usermod -s /bin/bash root 2>/dev/null
    usermod -U root 2>/dev/null
    print_message "Consola de root asignada y cuenta desbloqueada."
    
    # 2. ASIGNAR CONTRASEÑA
    echo -e -n "${YELLOW}¿Deseas establecer la contraseña para root ahora? (s/N): ${NC}"
    read change_pass
    
    if [[ "$change_pass" =~ ^[Ss]$ ]]; then
        echo ""
        while true; do
            echo -e -n "${BLUE}Ingresa nueva contraseña: ${NC}"
            read -s password1
            echo ""
            echo -e -n "${BLUE}Confirma contraseña: ${NC}"
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
        print_info "Manteniendo la contraseña actual."
    fi
}

create_sshd_run_dir() {
    if [[ ! -d /run/sshd ]]; then
        mkdir -p /run/sshd
        chmod 755 /run/sshd
        chown root:root /run/sshd
        mkdir -p /etc/tmpfiles.d
        cat > /etc/tmpfiles.d/sshd.conf << EOF
d /run/sshd 0755 root root -
EOF
    fi
}

create_sshd_config() {
    print_info "Aplicando configuración SSH sin restricciones..."
    
    # Backup
    mkdir -p /etc/ssh/backups
    cp /etc/ssh/sshd_config "/etc/ssh/backups/sshd_config_$(date +"%Y%m%d_%H%M%S").bak" 2>/dev/null
    
    # ELIMINAR REGLAS DE CLOUD-INIT QUE BLOQUEAN CONTRASEÑAS
    rm -rf /etc/ssh/sshd_config.d/* 2>/dev/null
    
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
    
    print_message "Archivos obstructivos eliminados y configuración SSH aplicada."
}

test_ssh_config() {
    create_sshd_run_dir
    if sshd -t 2>/dev/null; then
        return 0
    else
        print_error "Error de sintaxis en la configuración SSH"
        sshd -t
        return 1
    fi
}

restart_ssh_service() {
    print_info "Reiniciando el demonio SSH..."
    
    if systemctl list-units --full -all | grep -q "ssh.service"; then
        systemctl daemon-reload
        systemctl restart ssh
        systemctl enable ssh
    elif systemctl list-units --full -all | grep -q "sshd.service"; then
        systemctl daemon-reload
        systemctl restart sshd
        systemctl enable sshd
    else
        service ssh restart || service sshd restart || /etc/init.d/ssh restart
    fi
    
    sleep 1
    print_message "Servicio SSH reiniciado exitosamente."
}

show_summary() {
    print_title
    echo -e "${GREEN}  ✅ ACCESO ROOT TOTAL CONFIGURADO${NC}"
    print_title
    echo ""
    echo -e "${BLUE}📌 Ya puedes iniciar sesión directamente:${NC}"
    echo "  • Usuario: root"
    echo "  • Comando: ssh root@tu_direccion_ip"
    echo ""
    echo -e "${YELLOW}⚠️  La cuenta root fue desbloqueada a nivel de sistema (usermod).${NC}"
    echo -e "${YELLOW}⚠️  Las reglas de la nube (cloud-init) fueron purgadas.${NC}"
    print_title
}

main() {
    clear
    print_title
    echo -e "${GREEN}  🔥 SCRIPT DEFINITIVO - DESBLOQUEO ROOT SSH 🔥${NC}"
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
        print_error "Fallo al aplicar la configuración."
    fi
}

main
