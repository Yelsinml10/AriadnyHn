#!/bin/bash

# ==========================================
# Definición de Colores
# ==========================================
c_red="\e[1;31m"
c_green="\e[1;32m"
c_yellow="\e[1;33m"
c_blue="\e[1;34m"
c_magenta="\e[1;35m"
c_cyan="\e[1;36m"
c_white="\e[1;37m"
c_reset="\e[0m"

# ==========================================
# Función: Encabezado del Panel
# ==========================================
function encabezado() {
    clear
    mem_usage=$(free -m | awk 'NR==2{printf "%.0f%%", $3*100/$2}')
    ip_address=$(curl -s ifconfig.me || echo "Sin conexión")
    
    echo -e "${c_green}Memory usage: ${mem_usage}               IPv4 address: ${ip_address}${c_reset}\n"
    
    echo -e "${c_red}============================================================${c_reset}"
    echo -e " ${c_yellow}>>>>>>${c_white} SCRIPT MOD YELSIN ${c_yellow}<<<<<<${c_white}      [Version ${c_cyan}2.3${c_white}]"
    echo -e "${c_red}============================================================${c_reset}"
    echo -e ""
    echo -e "${c_yellow}  ADMINISTRADOR DE USUARIOS /SSH/HWID/TOKEN ${c_reset}"
    echo -e "${c_white}------------------------------------------------------------${c_reset}"
}

# ==========================================
# 1. Crear Usuario (Con Límite)
# ==========================================
function crear_usuario() {
    echo -e "\n${c_yellow}--- CREANDO NUEVO USUARIO VPN ---${c_reset}"
    read -p "$(echo -e ${c_white}Nombre de usuario: ${c_reset})" user
    read -p "$(echo -e ${c_white}Contraseña: ${c_reset})" pass
    read -p "$(echo -e ${c_white}Días de duración: ${c_reset})" dias
    read -p "$(echo -e ${c_white}Límite de conexiones simultáneas: ${c_reset})" limite

    if id "$user" &>/dev/null; then
        echo -e "${c_red}Error: El usuario '$user' ya existe.${c_reset}"
        sleep 2
        return
    fi

    # Crear usuario
    exp_date=$(date -d "+$dias days" +%Y-%m-%d)
    sudo useradd -e "$exp_date" -M -s /bin/false "$user"
    echo "$user:$pass" | sudo chpasswd
    
    # Aplicar límite de conexiones en el sistema
    echo "$user hard maxlogins $limite" | sudo tee -a /etc/security/limits.conf > /dev/null
    
    echo -e "\n${c_green}¡Usuario creado con éxito!${c_reset}"
    echo -e "${c_cyan}Usuario:${c_white} $user"
    echo -e "${c_cyan}Clave:${c_white} $pass"
    echo -e "${c_cyan}Límite:${c_white} $limite conexión(es)"
    echo -e "${c_cyan}Expira:${c_white} $exp_date"
    echo -e "\nPresiona ENTER para volver..."
    read -r
}

# ==========================================
# 2. Remover Usuario (Forzado y limpieza de límite)
# ==========================================
function remover_usuario() {
    echo -e "\n${c_yellow}--- REMOVER USUARIO VPN ---${c_reset}"
    read -p "$(echo -e ${c_white}Nombre de usuario a eliminar: ${c_reset})" user
    
    if id "$user" &>/dev/null; then
        echo -e "${c_cyan}Desconectando usuario...${c_reset}"
        sudo pkill -u "$user" 2>/dev/null
        sleep 1
        
        sudo userdel -f "$user" 2>/dev/null
        
        # Limpiar el límite del archivo limits.conf
        sudo sed -i "/^$user hard maxlogins/d" /etc/security/limits.conf
        
        echo -e "${c_green}Usuario '$user' y sus límites eliminados correctamente.${c_reset}"
    else
        echo -e "${c_red}Error: El usuario '$user' no existe en el sistema.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 6. Renovar Usuario
# ==========================================
function renovar_usuario() {
    echo -e "\n${c_yellow}--- RENOVAR USUARIO VPN ---${c_reset}"
    read -p "$(echo -e ${c_white}Nombre de usuario: ${c_reset})" user
    
    if id "$user" &>/dev/null; then
        read -p "$(echo -e ${c_white}Días a agregar: ${c_reset})" dias
        exp_date=$(date -d "+$dias days" +%Y-%m-%d)
        sudo usermod -e "$exp_date" "$user"
        echo -e "${c_green}Usuario '$user' renovado exitosamente hasta: $exp_date${c_reset}"
    else
        echo -e "${c_red}Error: El usuario '$user' no existe.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 7. Mostrar Cuentas
# ==========================================
function mostrar_cuentas() {
    echo -e "\n${c_yellow}--- LISTA DE USUARIOS VPN ---${c_reset}"
    echo -e "${c_cyan}USUARIO\t\t\tESTADO DE EXPIRACIÓN${c_reset}"
    echo -e "${c_white}------------------------------------------------------------${c_reset}"
    
    awk -F: '/\/bin\/false/ {print $1}' /etc/passwd | while read -r user; do
        exp_info=$(sudo chage -l "$user" | grep "Account expires" | cut -d: -f2)
        echo -e "${c_white}$user\t\t$exp_info${c_reset}"
    done
    
    echo -e "\nPresiona ENTER para volver..."
    read -r
}

# ==========================================
# 9. Eliminar Usuarios Vencidos (Forzado y limpieza)
# ==========================================
function eliminar_vencidos() {
    echo -e "\n${c_yellow}--- ELIMINANDO USUARIOS VENCIDOS ---${c_reset}"
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
                
                echo -e "${c_red}Eliminado:${c_white} $user (Venció el $exp_date)"
            fi
        fi
    done
    
    echo -e "\n${c_green}Limpieza completada.${c_reset}"
    sleep 2
}

# ==========================================
# Función: Menú Principal (Limpio)
# ==========================================
function menu() {
    while true; do
        encabezado
        echo -e "${c_yellow}[1] ${c_red}-> ${c_white}CREAR NUEVO USUARIO ${c_cyan}[SSH/HWID/TOKEN]${c_reset}"
        echo -e "${c_yellow}[2] ${c_red}-> ${c_white}REMOVER USUARIO ${c_cyan}[SSH/HWID/TOKEN]${c_reset}"
        echo -e "${c_yellow}[6] ${c_red}-> ${c_white}RENOVAR USUARIO ${c_cyan}[SSH/HWID/TOKEN]${c_reset}"
        echo -e "${c_yellow}[7] ${c_red}-> ${c_white}MOSTRAR CUENTAS ${c_cyan}[SSH/HWID/TOKEN]${c_reset}"
        echo -e "${c_yellow}[9] ${c_red}-> ${c_white}ELIMINAR USUARIOS VENCIDOS${c_reset}"
        echo -e "${c_white}------------------------------------------------------------${c_reset}"
        echo -e "${c_cyan}[0] ${c_red}-> ${c_white}\e[41m VOLVER \e[0m${c_reset}"
        echo -e "${c_white}------------------------------------------------------------${c_reset}"
        
        echo -ne "${c_white}► Seleccione una Opcion: ${c_green}"
        read -r opcion

        case $opcion in
            1) crear_usuario ;;
            2) remover_usuario ;;
            6) renovar_usuario ;;
            7) mostrar_cuentas ;;
            9) eliminar_vencidos ;;
            0) clear; echo -e "${c_green}Saliendo del panel...${c_reset}"; exit 0 ;;
            *) echo -e "${c_red}Opción inválida.${c_reset}"; sleep 1 ;;
        esac
    done
}

# Iniciar el script
menu
