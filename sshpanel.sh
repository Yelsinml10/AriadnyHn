#!/bin/bash
# =============================================
# PANEL SSH PROFESSIONAL v3.0 (Corregido)
# Sistema avanzado de gestión de usuarios SSH
# =============================================

# === CONFIGURACIÓN ===
VERSION="3.0"
LOG_FILE="/var/log/ssh_panel.log"
BACKUP_DIR="/root/ssh_backups"
COLOR_RESET='\033[0m'
COLOR_RED='\033[1;31m'
COLOR_GREEN='\033[1;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[1;34m'
COLOR_PURPLE='\033[1;35m'
COLOR_CYAN='\033[1;36m'
COLOR_WHITE='\033[1;37m'
COLOR_BOLD='\033[1m'

# Asegurar que el script se ejecute como root
if [ "$EUID" -ne 0 ]; then
  echo -e "${COLOR_RED}✘ Este script debe ejecutarse como root (sudo).${COLOR_RESET}"
  exit 1
fi

# === FUNCIONES DE UTILIDAD ===
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

show_header() {
    clear
    echo -e "${COLOR_CYAN}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_CYAN}║            ${COLOR_WHITE}SSH PROFESSIONAL PANEL v${VERSION}${COLOR_CYAN}              ║${COLOR_RESET}"
    echo -e "${COLOR_CYAN}╠════════════════════════════════════════════════════════════╣${COLOR_RESET}"
    echo -e "${COLOR_CYAN}║  ${COLOR_GREEN}●${COLOR_RESET} Sistema: $(hostname)                          ${COLOR_CYAN}║${COLOR_RESET}"
    echo -e "${COLOR_CYAN}║  ${COLOR_GREEN}●${COLOR_RESET} Usuarios Activos: $(who | wc -l)                         ${COLOR_CYAN}║${COLOR_RESET}"
    echo -e "${COLOR_CYAN}║  ${COLOR_GREEN}●${COLOR_RESET} Memoria: $(free -h | awk '/Mem:/ {print $3"/"$2}')                    ${COLOR_CYAN}║${COLOR_RESET}"
    echo -e "${COLOR_CYAN}║  ${COLOR_GREEN}●${COLOR_RESET} Disco: $(df -h / | awk 'NR==2 {print $3"/"$2}')                    ${COLOR_CYAN}║${COLOR_RESET}"
    echo -e "${COLOR_CYAN}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
}

generate_password() {
    tr -dc 'A-Za-z0-9!@#$%&*' </dev/urandom | head -c 12
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        for i in {1..4}; do
            if [ $(echo "$ip" | cut -d. -f$i) -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# === FUNCIONES PRINCIPALES ===

create_user() {
    show_header
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║              ${COLOR_WHITE}CREACIÓN DE USUARIO SSH${COLOR_BLUE}                ║${COLOR_RESET}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    
    while true; do
        read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Nombre de usuario: )" username
        if id "$username" &>/dev/null; then
            echo -e "${COLOR_RED}✘ El usuario '$username' ya existe.${COLOR_RESET}"
        elif [ -z "$username" ]; then
            echo -e "${COLOR_RED}✘ El nombre no puede estar vacío.${COLOR_RESET}"
        elif [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo -e "${COLOR_RED}✘ Nombre inválido. Solo minúsculas, números y guión bajo.${COLOR_RESET}"
        else
            break
        fi
    done
    
    echo -e "${COLOR_YELLOW}➜ Opciones de contraseña:${COLOR_RESET}"
    echo "  1) Generar automáticamente"
    echo "  2) Ingresar manualmente"
    read -p "Selecciona (1-2): " pass_option
    
    if [ "$pass_option" = "1" ]; then
        password=$(generate_password)
        echo -e "${COLOR_GREEN}✓ Contraseña generada: ${COLOR_WHITE}$password${COLOR_RESET}"
    else
        read -sp "Contraseña: " password
        echo ""
        read -sp "Confirmar contraseña: " password_confirm
        echo ""
        if [ "$password" != "$password_confirm" ]; then
            echo -e "${COLOR_RED}✘ Las contraseñas no coinciden.${COLOR_RESET}"
            sleep 2
            return
        fi
    fi
    
    while true; do
        read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Límite de conexiones simultáneas: )" max_connections
        if [[ "$max_connections" =~ ^[0-9]+$ ]] && [ "$max_connections" -gt 0 ]; then
            break
        fi
        echo -e "${COLOR_RED}✘ Ingresa un número válido mayor a 0.${COLOR_RESET}"
    done
    
    while true; do
        read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Días de expiración: )" exp_days
        if [[ "$exp_days" =~ ^[0-9]+$ ]] && [ "$exp_days" -gt 0 ]; then
            break
        fi
        echo -e "${COLOR_RED}✘ Ingresa un número válido mayor a 0.${COLOR_RESET}"
    done
    
    echo -e "${COLOR_YELLOW}➜ Restricciones adicionales:${COLOR_RESET}"
    read -p "¿Limitar por IP? (s/n): " limit_ip
    if [ "$limit_ip" = "s" ] || [ "$limit_ip" = "S" ]; then
        while true; do
            read -p "IP permitida: " allowed_ip
            if validate_ip "$allowed_ip"; then
                break
            fi
            echo -e "${COLOR_RED}✘ IP inválida.${COLOR_RESET}"
        done
    fi
    
    read -p "¿Permitir acceso SSH directo? (s/n): " shell_access
    shell="/bin/false"
    if [ "$shell_access" = "s" ] || [ "$shell_access" = "S" ]; then
        shell="/bin/bash"
        echo -e "${COLOR_YELLOW}⚠ Acceso a shell habilitado (menos seguro)${COLOR_RESET}"
    fi
    
    echo -e "\n${COLOR_BLUE}┌────────────────────────────────────────────────────────────┐${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│              ${COLOR_WHITE}CREANDO USUARIO...${COLOR_BLUE}                         │${COLOR_RESET}"
    echo -e "${COLOR_BLUE}└────────────────────────────────────────────────────────────┘${COLOR_RESET}"
    
    useradd -m -s "$shell" -c "SSH User $(date +%Y-%m-%d)" "$username"
    echo "$username:$password" | chpasswd
    
    exp_date=$(date -d "+$exp_days days" +%Y-%m-%d)
    chage -E "$exp_date" "$username"
    
    mkdir -p /etc/ssh/limits
    echo "$max_connections" > "/etc/ssh/limits/$username"
    
    if ! grep -q "^$username soft maxlogins" /etc/security/limits.conf; then
        echo -e "$username soft maxlogins $max_connections" >> /etc/security/limits.conf
        echo -e "$username hard maxlogins $max_connections" >> /etc/security/limits.conf
    fi
    
    # Restricción de IP segura mediante bloques Match al final del archivo
    if [ "$limit_ip" = "s" ] || [ "$limit_ip" = "S" ]; then
        echo -e "\nMatch User $username\n    AllowUsers $username@$allowed_ip" >> /etc/ssh/sshd_config
        systemctl restart sshd || systemctl restart ssh
    fi
    
    mkdir -p "/home/$username/.ssh"
    chown "$username:$username" "/home/$username/.ssh"
    chmod 700 "/home/$username/.ssh"
    
    log_action "Usuario creado: $username (Expira: $exp_date, Límite: $max_connections)"
    
    echo -e "\n${COLOR_GREEN}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_GREEN}║              ${COLOR_WHITE}USUARIO CREADO EXITOSAMENTE${COLOR_GREEN}              ║${COLOR_RESET}"
    echo -e "${COLOR_GREEN}╠════════════════════════════════════════════════════════════╣${COLOR_RESET}"
    echo -e "${COLOR_GREEN}║${COLOR_RESET}  Usuario: ${COLOR_WHITE}$username${COLOR_RESET}"
    echo -e "${COLOR_GREEN}║${COLOR_RESET}  Contraseña: ${COLOR_WHITE}$password${COLOR_RESET}"
    echo -e "${COLOR_GREEN}║${COLOR_RESET}  Límite: ${COLOR_WHITE}$max_connections conexiones${COLOR_RESET}"
    echo -e "${COLOR_GREEN}║${COLOR_RESET}  Expira: ${COLOR_WHITE}$exp_date ($exp_days días)${COLOR_RESET}"
    if [ "$limit_ip" = "s" ] || [ "$limit_ip" = "S" ]; then
        echo -e "${COLOR_GREEN}║${COLOR_RESET}  IP Restringida: ${COLOR_WHITE}$allowed_ip${COLOR_RESET}"
    fi
    echo -e "${COLOR_GREEN}║${COLOR_RESET}  Shell: ${COLOR_WHITE}$shell${COLOR_RESET}"
    echo -e "${COLOR_GREEN}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    
    read -p "Presiona Enter para continuar..."
}

list_users() {
    show_header
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║              ${COLOR_WHITE}LISTA DE USUARIOS SSH${COLOR_BLUE}                   ║${COLOR_RESET}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    
    printf "${COLOR_CYAN}%-15s %-18s %-12s %-8s %-15s${COLOR_RESET}\n" "USUARIO" "CREACIÓN" "EXPIRA" "CONEX" "ESTADO"
    echo "──────────────────────────────────────────────────────────────────"
    
    for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        create_date=$(ls -ld /home/$user 2>/dev/null | awk '{print $6, $7, $8}')
        [ -z "$create_date" ] && create_date="N/A"
        
        # Extracción segura de fecha de expiración por chage
        exp_raw=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2)
        if [[ "$exp_raw" =~ "never" ]] || [[ "$exp_raw" =~ "Nunca" ]] || [ -z "$exp_raw" ]; then
            exp_date="Nunca"
        else
            exp_date=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null || echo "N/A")
        fi
        
        max_conn=$(cat "/etc/ssh/limits/$user" 2>/dev/null || echo "N/A")
        
        if ps -u "$user" 2>/dev/null | grep -q sshd; then
            status="${COLOR_GREEN}● Activo${COLOR_RESET}"
        else
            status="${COLOR_RED}○ Inactivo${COLOR_RESET}"
        fi
        
        current_conn=$(ps -u "$user" 2>/dev/null | grep sshd | wc -l)
        conn_info="$current_conn/$max_conn"
        
        printf "${COLOR_WHITE}%-15s${COLOR_RESET} %-18s %-12s %-8s %b\n" "$user" "$create_date" "$exp_date" "$conn_info" "$status"
    done
    
    echo ""
    echo -e "${COLOR_YELLOW}Total de usuarios: $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | wc -l)${COLOR_RESET}"
    echo ""
    read -p "Presiona Enter para continuar..."
}

user_details() {
    show_header
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║              ${COLOR_WHITE}DETALLES DE USUARIO${COLOR_BLUE}                    ║${COLOR_RESET}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    
    read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Usuario a consultar: )" username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${COLOR_RED}✘ Usuario no encontrado.${COLOR_RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    echo -e "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    
    echo -e "${COLOR_WHITE}● Información General${COLOR_RESET}"
    echo "  Usuario: $username"
    echo "  UID: $(id -u $username)"
    echo "  GID: $(id -g $username)"
    echo "  Shell: $(getent passwd $username | cut -d: -f7)"
    echo "  Home: /home/$username"
    
    echo -e "\n${COLOR_WHITE}● Fechas${COLOR_RESET}"
    echo "  Último cambio de password: $(chage -l $username | grep "Last password change" | cut -d: -f2-)"
    echo "  Expiración de cuenta: $(chage -l $username | grep "Account expires" | cut -d: -f2-)"
    echo "  Último inicio de sesión: $(last $username -n 1 | head -1 | awk '{$1=""; print $0}')"
    
    echo -e "\n${COLOR_WHITE}● Límites y Conexiones${COLOR_RESET}"
    max_conn=$(cat "/etc/ssh/limits/$username" 2>/dev/null || echo "Sin límite")
    current_conn=$(ps -u "$username" 2>/dev/null | grep sshd | wc -l)
    echo "  Límite máximo: $max_conn conexiones"
    echo "  Conexiones actuales: $current_conn"
    
    echo -e "\n${COLOR_WHITE}● Restricciones${COLOR_RESET}"
    # Búsqueda adaptada al bloque Match seguro
    if sed -n "/Match User $username/,/^$/p" /etc/ssh/sshd_config | grep -q "AllowUsers"; then
        allowed_ip=$(sed -n "/Match User $username/,/^$/p" /etc/ssh/sshd_config | grep "AllowUsers" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
        echo "  Restringido a IP: $allowed_ip"
    else
        echo "  Sin restricción de IP"
    fi
    
    echo -e "\n${COLOR_WHITE}● Estado${COLOR_RESET}"
    if ps -u "$username" 2>/dev/null | grep -q sshd; then
        echo -e "  ${COLOR_GREEN}✓ Conectado actualmente${COLOR_RESET}"
    else
        echo -e "  ${COLOR_RED}✗ No conectado${COLOR_RESET}"
    fi
    
    echo -e "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    read -p "Presiona Enter para continuar..."
}

delete_user() {
    show_header
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║              ${COLOR_WHITE}ELIMINAR USUARIO${COLOR_BLUE}                       ║${COLOR_RESET}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    
    read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Usuario a eliminar: )" username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${COLOR_RED}✘ Usuario no encontrado.${COLOR_RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    echo -e "${COLOR_YELLOW}⚠ ADVERTENCIA: Esta acción es irreversible.${COLOR_RESET}"
    echo "   Usuario: $username"
    echo "   Home: /home/$username"
    echo "   Archivos: $(find /home/$username -type f 2>/dev/null | wc -l) archivos"
    
    read -p "¿Estás seguro de eliminar este usuario? (s/N): " confirm
    
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        echo -e "${COLOR_GREEN}✓ Operación cancelada.${COLOR_RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    mkdir -p "$BACKUP_DIR"
    tar -czf "$BACKUP_DIR/${username}_$(date +%Y%m%d_%H%M%S).tar.gz" "/home/$username" 2>/dev/null
    
    userdel -r "$username" 2>/dev/null
    
    rm -f "/etc/ssh/limits/$username"
    sed -i "/^$username soft maxlogins/d" /etc/security/limits.conf
    sed -i "/^$username hard maxlogins/d" /etc/security/limits.conf
    
    # Eliminar bloque Match específico del usuario de forma segura en sshd_config
    sed -i "/Match User $username/,+1d" /etc/ssh/sshd_config
    systemctl restart sshd || systemctl restart ssh
    
    log_action "Usuario eliminado: $username"
    
    echo -e "\n${COLOR_GREEN}✓ Usuario $username eliminado exitosamente.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}📦 Backup guardado en: $BACKUP_DIR${COLOR_RESET}"
    
    read -p "Presiona Enter para continuar..."
}

extend_user() {
    show_header
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║              ${COLOR_WHITE}EXTENDER CADUCIDAD${COLOR_BLUE}                     ║${COLOR_RESET}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    
    read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Usuario a extender: )" username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${COLOR_RED}✘ Usuario no encontrado.${COLOR_RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    # Obtener días de expiración actuales desde la época de forma segura
    exp_days_epoch=$(chage -l "$username" | grep "Account expires" | cut -d: -f2)
    
    if [[ "$exp_days_epoch" =~ "never" ]] || [[ "$exp_days_epoch" =~ "Nunca" ]]; then
        echo -e "Fecha actual de expiración: ${COLOR_YELLOW}Nunca${COLOR_RESET}"
        base_date="now"
    else
        base_date=$(date -d "$exp_days_epoch" +%Y-%m-%d 2>/dev/null)
        echo -e "Fecha actual de expiración: ${COLOR_YELLOW}$base_date${COLOR_RESET}"
    fi
    
    while true; do
        read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Días a extender: )" extra_days
        if [[ "$extra_days" =~ ^[0-9]+$ ]] && [ "$extra_days" -gt 0 ]; then
            break
        fi
        echo -e "${COLOR_RED}✘ Ingresa un número válido.${COLOR_RESET}"
    done
    
    new_date=$(date -d "$base_date + $extra_days days" +%Y-%m-%d)
    
    chage -E "$new_date" "$username"
    log_action "Extendida caducidad de $username a $new_date (+$extra_days días)"
    
    echo -e "\n${COLOR_GREEN}✓ Caducidad extendida exitosamente.${COLOR_RESET}"
    echo -e "Nueva fecha: ${COLOR_WHITE}$new_date${COLOR_RESET}"
    
    read -p "Presiona Enter para continuar..."
}

change_password() {
    show_header
    echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BLUE}║              ${COLOR_WHITE}CAMBIAR CONTRASEÑA${COLOR_BLUE}                     ║${COLOR_RESET}"
    echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    
    read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Usuario: )" username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${COLOR_RED}✘ Usuario no encontrado.${COLOR_RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    echo -e "${COLOR_YELLOW}➜ Opciones:${COLOR_RESET}"
    echo "  1) Generar contraseña automáticamente"
    echo "  2) Ingresar manualmente"
    read -p "Selecciona (1-2): " pass_option
    
    if [ "$pass_option" = "1" ]; then
        new_password=$(generate_password)
        echo -e "${COLOR_GREEN}✓ Nueva contraseña: ${COLOR_WHITE}$new_password${COLOR_RESET}"
    else
        read -sp "Nueva contraseña: " new_password
        echo ""
        read -sp "Confirmar contraseña: " password_confirm
        echo ""
        if [ "$new_password" != "$password_confirm" ]; then
            echo -e "${COLOR_RED}✘ Las contraseñas no coinciden.${COLOR_RESET}"
            sleep 2
            return
        fi
    fi
    
    echo "$username:$new_password" | chpasswd
    log_action "Contraseña cambiada para $username"
    
    echo -e "\n${COLOR_GREEN}✓ Contraseña actualizada exitosamente.${COLOR_RESET}"
    read -p "Presiona Enter para continuar..."
}

# === MENÚ PRINCIPAL ===
while true; do
    show_header
    
    echo -e "${COLOR_BLUE}┌────────────────────────────────────────────────────────────┐${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  1${COLOR_RESET}  Crear usuario SSH                          ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  2${COLOR_RESET}  Listar usuarios                            ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  3${COLOR_RESET}  Detalles de usuario                        ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  4${COLOR_RESET}  Eliminar usuario                           ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  5${COLOR_RESET}  Extender caducidad                         ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  6${COLOR_RESET}  Cambiar contraseña                         ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  7${COLOR_RESET}  Ver logs del sistema                       ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  8${COLOR_RESET}  Backup/restaurar usuarios                  ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}│${COLOR_WHITE}  9${COLOR_RESET}  Monitoreo en tiempo real                   ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_WHITE}  0${COLOR_RESET}  Salir                                     ${COLOR_BLUE}│${COLOR_RESET}"
    echo -e "${COLOR_BLUE}└────────────────────────────────────────────────────────────┘${COLOR_RESET}"
    echo ""
    
    read -p "$(echo -e ${COLOR_GREEN}➜${COLOR_RESET} Selecciona una opción: )" option
    
    case $option in
        1) create_user ;;
        2) list_users ;;
        3) user_details ;;
        4) delete_user ;;
        5) extend_user ;;
        6) change_password ;;
        7) 
            if [ -f "$LOG_FILE" ]; then
                tail -50 "$LOG_FILE"
            else
                echo "No hay logs disponibles."
            fi
            read -p "Presiona Enter para continuar..."
            ;;
        8)
            echo "Función de backup en desarrollo..."
            sleep 2
            ;;
        9)
            echo "Monitoreo en tiempo real..."
            echo "Presiona Ctrl+C para salir"
            sleep 1
            watch -n 2 'ps aux | grep sshd | grep -v grep'
            ;;
        0)
            echo -e "\n${COLOR_GREEN}¡Hasta luego!${COLOR_RESET}"
            log_action "Sesión finalizada"
            exit 0
            ;;
        *)
            echo -e "${COLOR_RED}✘ Opción inválida.${COLOR_RESET}"
            sleep 2
            ;;
    esac
done
