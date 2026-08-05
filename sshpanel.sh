#!/bin/bash

# ==========================================
# Definición de Colores Estándar ANSI
# ==========================================
c_red='\033[0;31m'
c_green='\033[0;32m'
c_yellow='\033[1;33m'
c_blue='\033[0;34m'
c_purple='\033[0;35m'
c_cyan='\033[0;36m'
c_white='\033[1;37m'
c_bold='\033[1m'
c_reset='\033[0m'

RED="$c_red"
GREEN="$c_green"
YELLOW="$c_yellow"
BLUE="$c_blue"
PURPLE="$c_purple"
CYAN="$c_cyan"
WHITE="$c_white"
BOLD="$c_bold"
NC="$c_reset"

# ==========================================
# Configuración del Acceso Directo "sshpanel"
# ==========================================
setup_shortcut() {
    local current_script
    current_script="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

    if [[ -f "$current_script" ]]; then
        if [[ "$current_script" != "/usr/local/bin/sshpanel" ]]; then
            cp "$current_script" /usr/local/bin/sshpanel 2>/dev/null
            chmod +x /usr/local/bin/sshpanel 2>/dev/null
        fi
        if [[ "$current_script" != "/usr/bin/sshpanel" ]]; then
            ln -sf /usr/local/bin/sshpanel /usr/bin/sshpanel 2>/dev/null
        fi
    fi

    # Registrar Alias en el sistema
    grep -q "alias sshpanel=" /root/.bashrc 2>/dev/null || echo "alias sshpanel='/usr/local/bin/sshpanel'" >> /root/.bashrc
    grep -q "alias sshpanel=" /etc/bash.bashrc 2>/dev/null || echo "alias sshpanel='/usr/local/bin/sshpanel'" >> /etc/bash.bashrc
    grep -q "alias sshpanel=" /etc/profile 2>/dev/null || echo "alias sshpanel='/usr/local/bin/sshpanel'" >> /etc/profile
}

# ==========================================
# Función: Encabezado del Panel
# ==========================================
function encabezado() {
    clear
    mem_usage=$(free -m 2>/dev/null | awk 'NR==2{printf "%.0f%%", $3*100/$2}')
    ip_address=$(curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null || curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo "Sin conexión")
    
    echo -e "${c_cyan}${c_bold}┌────────────────────────────────────────────────────────┐${c_reset}"
    echo -e "${c_cyan}${c_bold}│          SCRIPT MOD YELSIN  [Versión 2.3]              │${c_reset}"
    echo -e "${c_cyan}${c_bold}├────────────────────────────────────────────────────────┤${c_reset}"
    echo -e "  ${c_white}${c_bold}• Memoria RAM:${c_reset} ${c_green}${c_bold}${mem_usage}${c_reset}       ${c_white}${c_bold}• IP Pública:${c_reset} ${c_cyan}${c_bold}${ip_address}${c_reset}"
    echo -e "${c_cyan}${c_bold}└────────────────────────────────────────────────────────┘${c_reset}"
    echo -e "  ${c_purple}${c_bold}ADMINISTRADOR DE USUARIOS / SSH / HWID / TOKEN${c_reset}"
    echo -e "  ${c_yellow}Comando directo: ${c_green}sshpanel${c_reset}"
    echo -e "${c_cyan}${c_bold}──────────────────────────────────────────────────────────${c_reset}\n"
}

# ==========================================
# 1. Crear Usuario (Con Límite)
# ==========================================
function crear_usuario() {
    echo -e "${c_yellow}${c_bold}=== CREANDO NUEVO USUARIO VPN ===${c_reset}\n"
    read -p "$(echo -e "${c_cyan}❯ ${c_white}Nombre de usuario: ${c_reset}")" user
    read -p "$(echo -e "${c_cyan}❯ ${c_white}Contraseña: ${c_reset}")" pass
    read -p "$(echo -e "${c_cyan}❯ ${c_white}Días de duración: ${c_reset}")" dias
    read -p "$(echo -e "${c_cyan}❯ ${c_white}Límite de conexiones simultáneas: ${c_reset}")" limite

    if id "$user" &>/dev/null; then
        echo -e "\n${c_red}${c_bold}✘ Error: El usuario '$user' ya existe.${c_reset}"
        sleep 2
        return
    fi

    # Crear usuario
    exp_date=$(date -d "+$dias days" +%Y-%m-%d)
    sudo useradd -e "$exp_date" -M -s /bin/false "$user"
    echo "$user:$pass" | sudo chpasswd
    
    # Aplicar límite de conexiones en el sistema
    echo "$user hard maxlogins $limite" | sudo tee -a /etc/security/limits.conf > /dev/null
    
    echo -e "\n${c_green}${c_bold}✔ ¡Usuario creado con éxito!${c_reset}"
    echo -e "  ${c_white}• Usuario :${c_reset} ${c_yellow}${c_bold}$user${c_reset}"
    echo -e "  ${c_white}• Clave   :${c_reset} ${c_green}${c_bold}$pass${c_reset}"
    echo -e "  ${c_white}• Límite  :${c_reset} ${c_cyan}${c_bold}$limite conexión(es)${c_reset}"
    echo -e "  ${c_white}• Expira  :${c_reset} ${c_purple}${c_bold}$exp_date${c_reset}"
    
    echo -e "\n${c_white}Presiona ${c_yellow}ENTER${c_white} para volver...${c_reset}"
    read -r
}

# ==========================================
# 2. Remover Usuario
# ==========================================
function remover_usuario() {
    echo -e "${c_yellow}${c_bold}=== REMOVER USUARIO VPN ===${c_reset}\n"
    read -p "$(echo -e "${c_cyan}❯ ${c_white}Nombre de usuario a eliminar: ${c_reset}")" user
    
    if id "$user" &>/dev/null; then
        echo -e "\n${c_yellow}Desconectando usuario...${c_reset}"
        sudo pkill -u "$user" 2>/dev/null
        sleep 1
        
        sudo userdel -f "$user" 2>/dev/null
        
        # Limpiar el límite del archivo limits.conf
        sudo sed -i "/^$user hard maxlogins/d" /etc/security/limits.conf
        
        echo -e "${c_green}${c_bold}✔ Usuario '$user' y sus límites eliminados correctamente.${c_reset}"
    else
        echo -e "\n${c_red}${c_bold}✘ Error: El usuario '$user' no existe en el sistema.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 6. Renovar Usuario
# ==========================================
function renovar_usuario() {
    echo -e "${c_yellow}${c_bold}=== RENOVAR USUARIO VPN ===${c_reset}\n"
    read -p "$(echo -e "${c_cyan}❯ ${c_white}Nombre de usuario: ${c_reset}")" user
    
    if id "$user" &>/dev/null; then
        read -p "$(echo -e "${c_cyan}❯ ${c_white}Días a agregar: ${c_reset}")" dias
        exp_date=$(date -d "+$dias days" +%Y-%m-%d)
        sudo usermod -e "$exp_date" "$user"
        echo -e "\n${c_green}${c_bold}✔ Usuario '$user' renovado exitosamente hasta: ${c_yellow}$exp_date${c_reset}"
    else
        echo -e "\n${c_red}${c_bold}✘ Error: El usuario '$user' no existe.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 7. Mostrar Cuentas
# ==========================================
function mostrar_cuentas() {
    echo -e "${c_yellow}${c_bold}=== LISTA DE USUARIOS VPN ===${c_reset}\n"
    echo -e "${c_cyan}${c_bold}USUARIO\t\t\tESTADO DE EXPIRACIÓN${c_reset}"
    echo -e "${c_cyan}──────────────────────────────────────────────────────────${c_reset}"
    
    awk -F: '/\/bin\/false/ {print $1}' /etc/passwd | while read -r user; do
        exp_info=$(sudo chage -l "$user" | grep "Account expires" | cut -d: -f2)
        echo -e "${c_white}${c_bold}$user\t\t${c_green}$exp_info${c_reset}"
    done
    
    echo -e "\n${c_white}Presiona ${c_yellow}ENTER${c_white} para volver...${c_reset}"
    read -r
}

# ==========================================
# 9. Eliminar Usuarios Vencidos
# ==========================================
function eliminar_vencidos() {
    echo -e "${c_yellow}${c_bold}=== ELIMINANDO USUARIOS VENCIDOS ===${c_reset}\n"
    today=$(date +%s)
    
    awk -F: '/\/bin\/false/ {print $1}' /etc/passwd | while read -r user; do
        exp_date=$(sudo chage -l "$user" | grep "Account expires" | cut -d: -f2)
        
        if [[ "$exp_date" != *"never"* ]]; then
            exp_sec=$(date -d "$exp_date" +%s 2>/dev/null)
            if [[ -n "$exp_sec" && "$today" -gt "$exp_sec" ]]; then
                sudo pkill -u "$user" 2>/dev/null
                sudo userdel -f "$user" 2>/dev/null
                
                # Limpiar el límite del archivo limits.conf
                sudo sed -i "/^$user hard maxlogins/d" /etc/security/limits.conf
                
                echo -e "${c_red}${c_bold}Eliminado:${c_white} $user (Venció el $exp_date)"
            fi
        fi
    done
    
    echo -e "\n${c_green}${c_bold}✔ Limpieza de usuarios vencidos completada.${c_reset}"
    sleep 2
}

# ==========================================
# Menú del Panel SSH
# ==========================================
function panel_ssh() {
    while true; do
        encabezado
        echo -e " ${c_white}${c_bold}[ 1 ]${c_reset} ${c_cyan}Crear Nuevo Usuario${c_reset} ${c_purple}[SSH/HWID/TOKEN]${c_reset}"
        echo -e " ${c_white}${c_bold}[ 2 ]${c_reset} ${c_cyan}Remover Usuario${c_reset} ${c_purple}[SSH/HWID/TOKEN]${c_reset}"
        echo -e " ${c_white}${c_bold}[ 6 ]${c_reset} ${c_cyan}Renovar Usuario${c_reset} ${c_purple}[SSH/HWID/TOKEN]${c_reset}"
        echo -e " ${c_white}${c_bold}[ 7 ]${c_reset} ${c_cyan}Mostrar Cuentas${c_reset} ${c_purple}[SSH/HWID/TOKEN]${c_reset}"
        echo -e " ${c_white}${c_bold}[ 9 ]${c_reset} ${c_yellow}Eliminar Usuarios Vencidos${c_reset}"
        echo -e "${c_cyan}${c_bold}──────────────────────────────────────────────────────────${c_reset}"
        echo -e " ${c_white}${c_bold}[ 0 ]${c_reset} ${c_red}${c_bold}Salir del Panel SSH${c_reset}"
        echo -e "${c_cyan}${c_bold}──────────────────────────────────────────────────────────${c_reset}"
        
        read -p "$(echo -e "${c_yellow}${c_bold} Seleccione una opción [0-9]: ${c_reset}")" opcion

        case $opcion in
            1) crear_usuario ;;
            2) remover_usuario ;;
            6) renovar_usuario ;;
            7) mostrar_cuentas ;;
            9) eliminar_vencidos ;;
            0) clear; echo -e "${c_green}Saliendo de sshpanel...${c_reset}"; exit 0 ;;
            *) echo -e "${c_red}Opción inválida.${c_reset}"; sleep 1 ;;
        esac
    done
}

# Configurar acceso directo sshpanel al iniciar
setup_shortcut

# Iniciar el panel SSH
panel_ssh
