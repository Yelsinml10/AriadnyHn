#!/bin/bash

# ==========================================
# DEFINICIÓN DE COLORES Y ESTILOS
# ==========================================
c_red="\e[1;31m"
c_green="\e[1;32m"
c_yellow="\e[1;33m"
c_blue="\e[1;34m"
c_magenta="\e[1;35m"
c_cyan="\e[1;36m"
c_white="\e[1;37m"
c_bold="\e[1m"
c_reset="\e[0m"

# ==========================================
# VERIFICACIÓN DE ROOT
# ==========================================
if [ "$EUID" -ne 0 ]; then
    echo -e "\n${c_red}[ERROR] Este script debe ejecutarse como ROOT (sudo).${c_reset}\n"
    exit 1
fi

# ==========================================
# FUNCIÓN: ENCABEZADO DEL PANEL
# ==========================================
function encabezado() {
    clear
    mem_usage=$(free -m | awk 'NR==2{printf "%.0f%%", $3*100/$2}')
    ip_address=$(curl -sS --max-time 2 ifconfig.me || curl -sS --max-time 2 api.ipify.org || echo "Sin conexión")
    
    echo -e "${c_green}Uso de RAM: ${mem_usage}               IP Pública: ${ip_address}${c_reset}"
    echo -e "${c_red}============================================================${c_reset}"
    echo -e " ${c_yellow}>>>>>>${c_white} SCRIPT MOD YELSIN ${c_yellow}<<<<<<${c_white}      [Versión ${c_cyan}2.5 VIP${c_white}]"
    echo -e "${c_red}============================================================${c_reset}"
    echo -e "  ${c_yellow}ADMINISTRADOR DE USUARIOS [SSH / UDP / HYSTERIA 2]${c_reset}"
    echo -e "${c_white}------------------------------------------------------------${c_reset}"
}

# ==========================================
# 1. CREAR USUARIO (CON LÍMITE Y SEGURIDAD)
# ==========================================
function crear_usuario() {
    echo -e "\n${c_yellow}--- CREANDO NUEVO USUARIO VPN ---${c_reset}"
    
    # 1. Validar nombre de usuario
    while true; do
        read -p "$(echo -e ${c_white}"Nombre de usuario: "${c_reset})" user
        user=$(echo "$user" | tr -d ' ')
        if [ -z "$user" ]; then
            echo -e "${c_red}El usuario no puede estar vacío.${c_reset}"
        elif [[ "$user" =~ [^a-zA-Z0-9_.-] ]]; then
            echo -e "${c_red}Carácter inválido. Solo letras, números, puntos y guiones.${c_reset}"
        elif id "$user" &>/dev/null; then
            echo -e "${c_red}Error: El usuario '$user' ya existe en el sistema.${c_reset}"
            read -p "Presiona ENTER para continuar..."
            return
        else
            break
        fi
    done

    # 2. Validar contraseña
    while true; do
        read -p "$(echo -e ${c_white}"Contraseña: "${c_reset})" pass
        if [ -z "$pass" ]; then
            echo -e "${c_red}La contraseña no puede estar vacía.${c_reset}"
        elif [[ "$pass" == *":"* ]]; then
            echo -e "${c_red}La contraseña no puede contener el carácter ':' (dos puntos).${c_reset}"
        else
            break
        fi
    done

    # 3. Validar días de duración
    while true; do
        read -p "$(echo -e ${c_white}"Días de duración [Ej. 30]: "${c_reset})" dias
        if [[ "$dias" =~ ^[0-9]+$ ]] && [ "$dias" -gt 0 ]; then
            break
        else
            echo -e "${c_red}Ingresa un número de días válido (mayor a 0).${c_reset}"
        fi
    done

    # 4. Validar límite de conexiones
    while true; do
        read -p "$(echo -e ${c_white}"Límite de conexiones simultáneas [Ej. 1]: "${c_reset})" limite
        if [[ "$limite" =~ ^[0-9]+$ ]] && [ "$limite" -gt 0 ]; then
            break
        else
            echo -e "${c_red}Ingresa un límite válido (mayor a 0).${c_reset}"
        fi
    done

    # Fecha de expiración
    exp_date=$(date -d "+$dias days" +%Y-%m-%d)

    # Crear usuario con soporte para mayúsculas/minúsculas (--badnames)
    useradd -e "$exp_date" -M -s /bin/false --badnames "$user" 2>/dev/null || useradd -e "$exp_date" -M -s /bin/false "$user" 2>/dev/null

    # Comprobar que el usuario realmente fue creado
    if ! id "$user" &>/dev/null; then
        echo -e "\n${c_red}[ERROR CRÍTICO] No se pudo crear el usuario en Linux.${c_reset}"
        read -p "Presiona ENTER para volver..."
        return
    fi

    # Asignar contraseña
    echo "$user:$pass" | chpasswd
    
    # Aplicar límite en limits.conf
    sed -i "/^$user /d" /etc/security/limits.conf 2>/dev/null
    echo "$user hard maxlogins $limite" >> /etc/security/limits.conf
    
    echo -e "\n${c_green}${c_bold}✔ ¡Usuario creado exitosamente!${c_reset}"
    echo -e "${c_cyan}Usuario   :${c_white} $user"
    echo -e "${c_cyan}Clave     :${c_white} $pass"
    echo -e "${c_cyan}Límite    :${c_white} $limite conexión(es)"
    echo -e "${c_cyan}Expiración:${c_white} $exp_date ($dias días)"
    echo -e "${c_cyan}Compatible:${c_green} SSH / UDP Custom / Hysteria 1 y 2${c_reset}"
    echo -e "\nPresiona ENTER para volver..."
    read -r
}

# ==========================================
# 2. REMOVER USUARIO
# ==========================================
function remover_usuario() {
    echo -e "\n${c_yellow}--- REMOVER USUARIO VPN ---${c_reset}"
    read -p "$(echo -e ${c_white}"Nombre de usuario a eliminar: "${c_reset})" user
    user=$(echo "$user" | tr -d ' ')
    
    if id "$user" &>/dev/null; then
        echo -e "${c_cyan}Desconectando procesos activos...${c_reset}"
        pkill -u "$user" 2>/dev/null
        sleep 1
        
        userdel -f "$user" 2>/dev/null
        sed -i "/^$user /d" /etc/security/limits.conf 2>/dev/null
        
        echo -e "${c_green}✔ Usuario '$user' y sus límites eliminados correctamente.${c_reset}"
    else
        echo -e "${c_red}Error: El usuario '$user' no existe en el sistema.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 3. CAMBIAR CONTRASEÑA DE USUARIO
# ==========================================
function cambiar_password() {
    echo -e "\n${c_yellow}--- CAMBIAR CONTRASEÑA ---${c_reset}"
    read -p "$(echo -e ${c_white}"Nombre de usuario: "${c_reset})" user
    user=$(echo "$user" | tr -d ' ')

    if id "$user" &>/dev/null; then
        while true; do
            read -p "$(echo -e ${c_white}"Nueva Contraseña: "${c_reset})" pass
            if [ -z "$pass" ] || [[ "$pass" == *":"* ]]; then
                echo -e "${c_red}Contraseña inválida o contiene ':'${c_reset}"
            else
                break
            fi
        done
        echo "$user:$pass" | chpasswd
        echo -e "${c_green}✔ Contraseña de '$user' actualizada a: $pass${c_reset}"
    else
        echo -e "${c_red}Error: El usuario '$user' no existe.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 4. RENOVAR USUARIO
# ==========================================
function renovar_usuario() {
    echo -e "\n${c_yellow}--- RENOVAR DÍAS DE USUARIO ---${c_reset}"
    read -p "$(echo -e ${c_white}"Nombre de usuario: "${c_reset})" user
    user=$(echo "$user" | tr -d ' ')
    
    if id "$user" &>/dev/null; then
        while true; do
            read -p "$(echo -e ${c_white}"Días a agregar desde hoy: "${c_reset})" dias
            if [[ "$dias" =~ ^[0-9]+$ ]] && [ "$dias" -gt 0 ]; then
                break
            else
                echo -e "${c_red}Ingresa un número válido.${c_reset}"
            fi
        done

        exp_date=$(date -d "+$dias days" +%Y-%m-%d)
        usermod -e "$exp_date" "$user"
        echo -e "${c_green}✔ Usuario '$user' renovado exitosamente hasta: $exp_date ($dias días)${c_reset}"
    else
        echo -e "${c_red}Error: El usuario '$user' no existe.${c_reset}"
    fi
    sleep 2
}

# ==========================================
# 5. MOSTRAR CUENTAS DETALLADAS
# ==========================================
function mostrar_cuentas() {
    echo -e "\n${c_yellow}--- LISTA DE USUARIOS REGISTRADOS ---${c_reset}"
    printf "${c_cyan}%-18s %-16s %-16s %-10s${c_reset}\n" "USUARIO" "EXPIRACIÓN" "DÍAS RESTANTES" "ESTADO"
    echo -e "${c_white}------------------------------------------------------------${c_reset}"
    
    today_sec=$(date +%s)
    total_users=0

    while IFS=: read -r user _ _ _ _ _ shell; do
        if [[ "$shell" == *"/false"* || "$shell" == *"/nologin"* ]]; then
            ((total_users++))
            exp_info=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
            
            if [[ "$exp_info" == "never" || -z "$exp_info" ]]; then
                printf "${c_white}%-18s %-16s %-16s ${c_green}%-10s${c_reset}\n" "$user" "Nunca" "Ilimitado" "ACTIVO"
            else
                exp_sec=$(date -d "$exp_info" +%s 2>/dev/null)
                if [ -n "$exp_sec" ]; then
                    diff_days=$(( (exp_sec - today_sec) / 86400 ))
                    
                    if [ "$diff_days" -gt 0 ]; then
                        printf "${c_white}%-18s %-16s %-16s ${c_green}%-10s${c_reset}\n" "$user" "$exp_info" "$diff_days días" "ACTIVO"
                    elif [ "$diff_days" -eq 0 ]; then
                        printf "${c_white}%-18s %-16s %-16s ${c_yellow}%-10s${c_reset}\n" "$user" "$exp_info" "Hoy" "VENCE HOY"
                    else
                        printf "${c_white}%-18s %-16s %-16s ${c_red}%-10s${c_reset}\n" "$user" "$exp_info" "Expirado" "VENCIDO"
                    fi
                fi
            fi
        fi
    done < /etc/passwd

    echo -e "${c_white}------------------------------------------------------------${c_reset}"
    echo -e "${c_yellow}Total de usuarios VPN:${c_white} $total_users${c_reset}"
    echo -e "\nPresiona ENTER para volver..."
    read -r
}

# ==========================================
# 6. ELIMINAR USUARIOS VENCIDOS
# ==========================================
function eliminar_vencidos() {
    echo -e "\n${c_yellow}--- ELIMINANDO USUARIOS VENCIDOS ---${c_reset}"
    today=$(date +%s)
    eliminados=0
    
    while IFS=: read -r user _ _ _ _ _ shell; do
        if [[ "$shell" == *"/false"* || "$shell" == *"/nologin"* ]]; then
            exp_info=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
            
            if [[ "$exp_info" != "never" && -n "$exp_info" ]]; then
                exp_sec=$(date -d "$exp_info" +%s 2>/dev/null)
                if [[ -n "$exp_sec" && "$today" -gt "$exp_sec" ]]; then
                    pkill -u "$user" 2>/dev/null
                    userdel -f "$user" 2>/dev/null
                    sed -i "/^$user /d" /etc/security/limits.conf 2>/dev/null
                    echo -e "${c_red}✖ Eliminado:${c_white} $user (Venció el: $exp_info)"
                    ((eliminados++))
                fi
            fi
        fi
    done < /etc/passwd

    if [ "$eliminados" -eq 0 ]; then
        echo -e "${c_green}No se encontraron usuarios vencidos.${c_reset}"
    else
        echo -e "\n${c_green}✔ Limpieza completada. Total eliminados: $eliminados${c_reset}"
    fi
    sleep 2
}

# ==========================================
# MENÚ PRINCIPAL
# ==========================================
function menu() {
    while true; do
        encabezado
        echo -e "${c_yellow}[1] ${c_red}-> ${c_white}CREAR NUEVO USUARIO ${c_cyan}[SSH/UDP/HYSTERIA]${c_reset}"
        echo -e "${c_yellow}[2] ${c_red}-> ${c_white}REMOVER USUARIO ${c_cyan}[ELIMINAR]${c_reset}"
        echo -e "${c_yellow}[3] ${c_red}-> ${c_white}CAMBIAR CONTRASEÑA DE USUARIO${c_reset}"
        echo -e "${c_yellow}[4] ${c_red}-> ${c_white}RENOVAR DÍAS DE USUARIO${c_reset}"
        echo -e "${c_yellow}[5] ${c_red}-> ${c_white}LISTAR TODAS LAS CUENTAS${c_reset}"
        echo -e "${c_yellow}[6] ${c_red}-> ${c_white}ELIMINAR USUARIOS VENCIDOS (AUTO-CLEAN)${c_reset}"
        echo -e "${c_white}------------------------------------------------------------${c_reset}"
        echo -e "${c_cyan}[0] ${c_red}-> ${c_white}\e[41m SALIR DEL PANEL \e[0m${c_reset}"
        echo -e "${c_white}------------------------------------------------------------${c_reset}"
        
        echo -ne "${c_white}► Seleccione una Opción: ${c_green}"
        read -r opcion

        case $opcion in
            1) crear_usuario ;;
            2) remover_usuario ;;
            3) cambiar_password ;;
            4) renovar_usuario ;;
            5) mostrar_cuentas ;;
            6) eliminar_vencidos ;;
            0) clear; echo -e "${c_green}Saliendo del panel...${c_reset}"; exit 0 ;;
            *) echo -e "${c_red}Opción inválida.${c_reset}"; sleep 1 ;;
        esac
    done
}

# Iniciar el script
menu
