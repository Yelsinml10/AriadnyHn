#!/bin/bash

# =============================================
# PANEL MAESTRO VPN - INSTALADOR Y ADMINISTRADOR
# Edición Ultra Visual Pro ✨
# =============================================

# =============================================
# 1. PALETA DE COLORES Y ESTILOS (256 COLORES)
# =============================================
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Colores Neón & Gradients
PURPLE='\033[38;5;141m'
CYAN='\033[38;5;51m'
L_CYAN='\033[38;5;123m'
GREEN='\033[38;5;48m'
RED='\033[38;5;196m'
YELLOW='\033[38;5;220m'
ORANGE='\033[38;5;208m'
WHITE='\033[38;5;255m'
GRAY='\033[38;5;242m'
MAGENTA='\033[38;5;201m'

# Insignias con Fondo
BG_GREEN='\033[48;5;34m\033[38;5;255m\033[1m'
BG_RED='\033[48;5;160m\033[38;5;255m\033[1m'
BG_PURPLE='\033[48;5;93m\033[38;5;255m\033[1m'

TITLE="PANEL MAESTRO VPN"
TOKEN="${TOKEN:-}"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

# =============================================
# 2. FUNCIONES DE SISTEMA Y UTILIDADES VISUALES
# =============================================
info() { echo -e "  ${GREEN}✔${NC} ${WHITE}$1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠${NC} ${YELLOW}$1${NC}"; }
error() { echo -e "  ${RED}✖${NC} ${RED}$1${NC}" >&2; exit 1; }

pause() {
  echo -e "\n  ${GRAY}Presiona ${CYAN}[ENTER]${GRAY} para continuar...${NC}"
  read -r
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "\n  ${RED}✖ Ejecuta como root:${NC} ${YELLOW}sudo bash $0${NC}\n"
    exit 1
  fi
}

check_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y curl -qq || true
  fi
}

setup_menu_command() {
  local script_path
  script_path=$(readlink -f "$0")
  if [[ "$script_path" != "/usr/local/bin/menu" ]]; then
    cp "$script_path" /usr/local/bin/menu 2>/dev/null || true
    chmod +x /usr/local/bin/menu 2>/dev/null || true
  fi
}

download_and_execute() {
  local script_name="$1"
  echo -e "\n  ${CYAN}⬇ Descargando ${WHITE}$script_name${CYAN}...${NC}"
  if curl -fsSL "$BASE_URL/$script_name" > "$script_name"; then
    chmod +x "$script_name"
    echo -e "  ${GREEN}🚀 Ejecutando ${WHITE}$script_name${GREEN}...${NC}\n"
    "./$script_name"
    rm -f "$script_name"
    echo -e "\n  ${GREEN}✔ Operación finalizada.${NC}"
    pause
  else
    echo -e "\n  ${RED}✖ Error al descargar $script_name.${NC}"
    pause
  fi
}

get_vps_info() {
  if [ -f /etc/os-release ]; then
      VPS_OS=$(grep -w PRETTY_NAME /etc/os-release | cut -d '"' -f 2)
  else
      VPS_OS=$(uname -srm)
  fi
  VPS_IP=$(curl -sS ifconfig.me 2>/dev/null || curl -sS ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
  VPS_RAM=$(free -m 2>/dev/null | awk 'NR==2{printf "%sMB / %sMB", $3, $2}')
  VPS_CPU=$(uptime 2>/dev/null | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
}

draw_header() {
  clear
  echo -e "\n  ${PURPLE}${BOLD}🚀 PANEL MAESTRO VPN${NC} ${GRAY}• [ PRO EDITION ]${NC}\n"
}

display_header_main() {
  get_vps_info
  draw_header
  echo -e "${L_CYAN}  ╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "  ${L_CYAN}│${NC}  ${BOLD}${WHITE}🖥️  SISTEMA  :${NC} ${GREEN}${VPS_OS}${NC}"
  echo -e "  ${L_CYAN}│${NC}  ${BOLD}${WHITE}🌐 IP VPS   :${NC} ${YELLOW}${VPS_IP}${NC}"
  echo -e "  ${L_CYAN}│${NC}  ${BOLD}${WHITE}🧠 MEMORIA  :${NC} ${CYAN}${VPS_RAM}${NC}"
  echo -e "  ${L_CYAN}│${NC}  ${BOLD}${WHITE}⚡ CARGA CPU:${NC} ${MAGENTA}${VPS_CPU}${NC} ${GRAY}(Load Avg)${NC}"
  echo -e "${L_CYAN}  ╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
}

# =============================================
# 3. MÓDULO: CADDY SERVER (ADMINISTRACIÓN COMPLETA)
# =============================================
caddy_menu() {
  CADDY_CONF="/etc/caddy/Caddyfile"
  while true; do
    if systemctl is-active --quiet caddy; then 
      CADDY_STATUS=" ${BG_GREEN} ● ACTIVO ${NC}"
    else 
      CADDY_STATUS=" ${BG_RED} ● INACTIVO ${NC}"
    fi

    if [[ -f "$CADDY_CONF" ]]; then
      DOMINIO_ACTUAL=$(grep -E '[a-zA-Z0-9.-]+:443' "$CADDY_CONF" 2>/dev/null | head -n 1 | awk -F':' '{print $1}' | tr -d ' ' || echo "No detectado")
      [[ -z "$DOMINIO_ACTUAL" ]] && DOMINIO_ACTUAL="No detectado"
      PUERTOS_HTTPS=$(grep -E '^[a-zA-Z0-9.-]+:[0-9]+' "$CADDY_CONF" 2>/dev/null | grep -o ':[0-9]*' | tr -d ':' | paste -sd, - || echo "N/A")
      PUERTOS_HTTP=$(grep -E '^:[0-9]+' "$CADDY_CONF" 2>/dev/null | grep -o '[0-9]*' | paste -sd, - || echo "N/A")
    else
      DOMINIO_ACTUAL="Caddyfile no encontrado"
      PUERTOS_HTTPS="N/A"
      PUERTOS_HTTP="N/A"
    fi

    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🌐 ADMINISTRADOR DE CADDY SERVER${NC}          ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}DOMINIO :${NC} ${WHITE}${DOMINIO_ACTUAL}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}HTTP    :${NC} ${GREEN}${PUERTOS_HTTP}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}HTTPS   :${NC} ${GREEN}${PUERTOS_HTTPS}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO  :${NC}${CADDY_STATUS}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📊 Estado del servicio${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}✏️  Cambiar dominio actual${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🔌 Gestionar puertos HTTP (Agregar/Quitar/Cambiar)${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔒 Gestionar puertos HTTPS (Agregar/Quitar/Cambiar)${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}📜 Ver logs en tiempo real${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}🔄 Reiniciar Caddy${NC}"
    echo -e "  ${RED}[7]${NC} ${RED}🗑️  Desinstalar Caddy por completo${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -e "  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_caddy

    case "$opt_caddy" in
      1) clear; systemctl status caddy --no-pager || true; pause ;;
      2) 
        echo -e "\n  ${YELLOW}Dominio actual:${NC} ${WHITE}$DOMINIO_ACTUAL${NC}"
        read -r -p "  ➜ Ingresa el NUEVO dominio para Caddy: " NUEVO_DOMINIO
        if [[ -n "$NUEVO_DOMINIO" && "$DOMINIO_ACTUAL" != "No detectado" && -f "$CADDY_CONF" ]]; then
            sed -i "s/$DOMINIO_ACTUAL/$NUEVO_DOMINIO/g" "$CADDY_CONF" 2>/dev/null || true
            systemctl restart caddy 2>/dev/null || true
            info "Dominio actualizado exitosamente a: $NUEVO_DOMINIO"
        fi
        pause ;;
      3) 
        echo -e "\n  ${YELLOW}=== GESTIÓN DE PUERTOS HTTP (CADDY) ===${NC}"
        echo -e "  Puertos HTTP actuales: ${WHITE}$PUERTOS_HTTP${NC}\n"
        echo -e "  ${CYAN}[1]${NC} ${WHITE}➕ Agregar un puerto${NC}"
        echo -e "  ${CYAN}[2]${NC} ${WHITE}➖ Quitar un puerto${NC}"
        echo -e "  ${CYAN}[3]${NC} ${WHITE}✏️  Reemplazar todos los puertos${NC}"
        read -r -p "  ➜ Selecciona una sub-opción: " opt_p_http

        case "$opt_p_http" in
          1)
            read -r -p "  ➜ Puerto HTTP a agregar: " ADD_P
            if [[ "$ADD_P" =~ ^[0-9]+$ ]]; then
              LIST_HTTP=$(echo "$PUERTOS_HTTP" | tr ',' ' ')
              FORMATTED_HTTP=""
              EXISTS=0
              for p in $LIST_HTTP; do
                p_clean=$(echo "$p" | xargs)
                if [[ "$p_clean" == "$ADD_P" ]]; then EXISTS=1; fi
                if [[ -n "$p_clean" && "$p_clean" != "N/A" ]]; then
                  if [[ -z "$FORMATTED_HTTP" ]]; then
                    FORMATTED_HTTP=":${p_clean}"
                  else
                    FORMATTED_HTTP="${FORMATTED_HTTP}, :${p_clean}"
                  fi
                fi
              done
              if [[ $EXISTS -eq 0 ]]; then
                if [[ -z "$FORMATTED_HTTP" ]]; then
                  FORMATTED_HTTP=":${ADD_P}"
                else
                  FORMATTED_HTTP="${FORMATTED_HTTP}, :${ADD_P}"
                fi
              fi
              sed -i -E "s/^:[0-9]+(,[[:space:]]*:[0-9]+)*[[:space:]]*\{/$FORMATTED_HTTP {/g" "$CADDY_CONF" 2>/dev/null || true
              systemctl restart caddy 2>/dev/null || true
              info "Puerto HTTP $ADD_P agregado correctamente."
            else
              warn "Puerto no válido."
            fi
            ;;
          2)
            read -r -p "  ➜ Puerto HTTP a quitar: " DEL_P
            if [[ "$DEL_P" =~ ^[0-9]+$ ]]; then
              LIST_HTTP=$(echo "$PUERTOS_HTTP" | tr ',' ' ')
              FORMATTED_HTTP=""
              for p in $LIST_HTTP; do
                p_clean=$(echo "$p" | xargs)
                if [[ "$p_clean" != "$DEL_P" && -n "$p_clean" && "$p_clean" != "N/A" ]]; then
                  if [[ -z "$FORMATTED_HTTP" ]]; then
                    FORMATTED_HTTP=":${p_clean}"
                  else
                    FORMATTED_HTTP="${FORMATTED_HTTP}, :${p_clean}"
                  fi
                fi
              done
              if [[ -n "$FORMATTED_HTTP" ]]; then
                sed -i -E "s/^:[0-9]+(,[[:space:]]*:[0-9]+)*[[:space:]]*\{/$FORMATTED_HTTP {/g" "$CADDY_CONF" 2>/dev/null || true
                systemctl restart caddy 2>/dev/null || true
                info "Puerto HTTP $DEL_P eliminado correctamente."
              else
                warn "No se puede dejar Caddy sin puertos HTTP."
              fi
            else
              warn "Puerto no válido."
            fi
            ;;
          3)
            read -r -p "  ➜ Nuevos puertos HTTP (separados por comas): " NUEVOS_HTTP
            if [[ -n "$NUEVOS_HTTP" && -f "$CADDY_CONF" ]]; then
                IFS=',' read -ra ADDR <<< "$NUEVOS_HTTP"
                FORMATTED_HTTP=""
                for i in "${ADDR[@]}"; do
                    cp_clean=$(echo "$i" | xargs)
                    if [[ -n "$cp_clean" ]]; then
                        if [[ -z "$FORMATTED_HTTP" ]]; then
                            FORMATTED_HTTP=":${cp_clean}"
                        else
                            FORMATTED_HTTP="${FORMATTED_HTTP}, :${cp_clean}"
                        fi
                    fi
                done
                if [[ -n "$FORMATTED_HTTP" ]]; then
                    sed -i -E "s/^:[0-9]+(,[[:space:]]*:[0-9]+)*[[:space:]]*\{/$FORMATTED_HTTP {/g" "$CADDY_CONF" 2>/dev/null || true
                    systemctl restart caddy 2>/dev/null || true
                    info "Puertos HTTP actualizados correctamente."
                else
                    warn "Formato de puertos HTTP inválido."
                fi
            fi
            ;;
        esac
        pause ;;
      4) 
        echo -e "\n  ${YELLOW}=== GESTIÓN DE PUERTOS HTTPS (CADDY) ===${NC}"
        echo -e "  Dominio: ${WHITE}$DOMINIO_ACTUAL${NC}"
        echo -e "  Puertos HTTPS actuales: ${WHITE}$PUERTOS_HTTPS${NC}\n"
        echo -e "  ${CYAN}[1]${NC} ${WHITE}➕ Agregar un puerto${NC}"
        echo -e "  ${CYAN}[2]${NC} ${WHITE}➖ Quitar un puerto${NC}"
        echo -e "  ${CYAN}[3]${NC} ${WHITE}✏️  Reemplazar todos los puertos${NC}"
        read -r -p "  ➜ Selecciona una sub-opción: " opt_p_https

        case "$opt_p_https" in
          1)
            read -r -p "  ➜ Puerto HTTPS a agregar: " ADD_P
            if [[ "$ADD_P" =~ ^[0-9]+$ && "$DOMINIO_ACTUAL" != "No detectado" ]]; then
              LIST_HTTPS=$(echo "$PUERTOS_HTTPS" | tr ',' ' ')
              FORMATTED_PORTS=""
              EXISTS=0
              for p in $LIST_HTTPS; do
                p_clean=$(echo "$p" | xargs)
                if [[ "$p_clean" == "$ADD_P" ]]; then EXISTS=1; fi
                if [[ -n "$p_clean" && "$p_clean" != "N/A" ]]; then
                  if [[ -z "$FORMATTED_PORTS" ]]; then
                    FORMATTED_PORTS="${DOMINIO_ACTUAL}:${p_clean}"
                  else
                    FORMATTED_PORTS="${FORMATTED_PORTS}, ${DOMINIO_ACTUAL}:${p_clean}"
                  fi
                fi
              done
              if [[ $EXISTS -eq 0 ]]; then
                if [[ -z "$FORMATTED_PORTS" ]]; then
                  FORMATTED_PORTS="${DOMINIO_ACTUAL}:${ADD_P}"
                else
                  FORMATTED_PORTS="${FORMATTED_PORTS}, ${DOMINIO_ACTUAL}:${ADD_P}"
                fi
              fi
              sed -i -E "s/^[a-zA-Z0-9.-]+:[0-9]+.*\{/$FORMATTED_PORTS {/g" "$CADDY_CONF" 2>/dev/null || true
              systemctl restart caddy 2>/dev/null || true
              info "Puerto HTTPS $ADD_P agregado correctamente."
            else
              warn "Puerto o dominio no válido."
            fi
            ;;
          2)
            read -r -p "  ➜ Puerto HTTPS a quitar: " DEL_P
            if [[ "$DEL_P" =~ ^[0-9]+$ && "$DOMINIO_ACTUAL" != "No detectado" ]]; then
              LIST_HTTPS=$(echo "$PUERTOS_HTTPS" | tr ',' ' ')
              FORMATTED_PORTS=""
              for p in $LIST_HTTPS; do
                p_clean=$(echo "$p" | xargs)
                if [[ "$p_clean" != "$DEL_P" && -n "$p_clean" && "$p_clean" != "N/A" ]]; then
                  if [[ -z "$FORMATTED_PORTS" ]]; then
                    FORMATTED_PORTS="${DOMINIO_ACTUAL}:${p_clean}"
                  else
                    FORMATTED_PORTS="${FORMATTED_PORTS}, ${DOMINIO_ACTUAL}:${p_clean}"
                  fi
                fi
              done
              if [[ -n "$FORMATTED_PORTS" ]]; then
                sed -i -E "s/^[a-zA-Z0-9.-]+:[0-9]+.*\{/$FORMATTED_PORTS {/g" "$CADDY_CONF" 2>/dev/null || true
                systemctl restart caddy 2>/dev/null || true
                info "Puerto HTTPS $DEL_P eliminado correctamente."
              else
                warn "No se puede dejar Caddy sin puertos HTTPS."
              fi
            else
              warn "Puerto o dominio no válido."
            fi
            ;;
          3)
            read -r -p "  ➜ Nuevos puertos HTTPS (separados por comas): " NUEVOS_PUERTOS
            if [[ -n "$NUEVOS_PUERTOS" && -f "$CADDY_CONF" ]]; then
                IFS=',' read -ra ADDR <<< "$NUEVOS_PUERTOS"
                FORMATTED_PORTS=""
                for i in "${ADDR[@]}"; do
                    clean_port=$(echo "$i" | xargs)
                    if [[ -n "$clean_port" ]]; then
                        if [[ -z "$FORMATTED_PORTS" ]]; then
                            FORMATTED_PORTS="${DOMINIO_ACTUAL}:${clean_port}"
                        else
                            FORMATTED_PORTS="${FORMATTED_PORTS}, ${DOMINIO_ACTUAL}:${clean_port}"
                        fi
                    fi
                done
                if [[ -n "$FORMATTED_PORTS" ]]; then
                    sed -i -E "s/^[a-zA-Z0-9.-]+:[0-9]+.*\{/$FORMATTED_PORTS {/g" "$CADDY_CONF" 2>/dev/null || true
                    systemctl restart caddy 2>/dev/null || true
                    info "Puertos HTTPS actualizados correctamente."
                else
                    warn "Formato de puertos HTTPS inválido."
                fi
            fi
            ;;
        esac
        pause ;;
      5) clear; journalctl -u caddy -f || true; pause ;;
      6) systemctl restart caddy || true; info "Caddy reiniciado."; sleep 1 ;;
      7) 
        echo -e "\n  ${RED}⚠️ ¿Estás seguro de desinstalar Caddy por completo? (s/N)${NC}"
        read -r -p "  ➜ " conf_caddy
        if [[ "$conf_caddy" =~ ^[sS]$ ]]; then
          systemctl stop caddy 2>/dev/null || true
          systemctl disable caddy 2>/dev/null || true
          apt-get purge -y caddy 2>/dev/null || true
          rm -rf /etc/caddy 2>/dev/null || true
          info "Caddy desinstalado por completo."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 4. MÓDULO: V2RAY (VMESS) - ADMINISTRACIÓN COMPLETA
# =============================================
v2ray_menu() {
  # Si V2Ray no está instalado o no existe config, ejecuta tu instalador oficial del repositorio
  if ! command -v v2ray >/dev/null 2>&1 || [[ ! -f "/usr/local/etc/v2ray/config.json" ]]; then
    echo -e "\n  ${YELLOW}⚠️ V2Ray no está instalado en el sistema.${NC}"
    download_and_execute "install-v2ray.sh"
    if ! command -v v2ray >/dev/null 2>&1 || [[ ! -f "/usr/local/etc/v2ray/config.json" ]]; then
      warn "No se pudo completar la instalación de V2Ray."
      return 1
    fi
  fi

  if ! command -v jq >/dev/null 2>&1; then apt-get install -y jq -qq || true; fi
  V2RAY_CONF="/usr/local/etc/v2ray/config.json"
  
  while true; do
    if systemctl is-active --quiet v2ray; then 
      V2RAY_STATUS=" ${BG_GREEN} ● ACTIVO ${NC}"
    else 
      V2RAY_STATUS=" ${BG_RED} ● INACTIVO ${NC}"
    fi

    V2RAY_PORT=$(jq -r '.inbounds[0].port' "$V2RAY_CONF" 2>/dev/null || echo "N/A")
    V2RAY_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$V2RAY_CONF" 2>/dev/null || echo "N/A")
    V2RAY_USERS=$(jq '.inbounds[0].settings.clients | length' "$V2RAY_CONF" 2>/dev/null || echo "0")

    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}⚡ ADMINISTRADOR V2RAY (VMESS)${NC}            ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}PUERTO   :${NC} ${GREEN}${V2RAY_PORT}${NC} ${GRAY}(Local)${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}PATH     :${NC} ${YELLOW}${V2RAY_PATH}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}USUARIOS :${NC} ${WHITE}${V2RAY_USERS}${NC} ${GRAY}Activos${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${V2RAY_STATUS}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📋 Listar Usuarios (UUIDs)${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}➕ Añadir nuevo usuario${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🗑️  Eliminar usuario${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔌 Cambiar puerto local${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🔀 Cambiar PATH (Ruta Websocket)${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}📜 Ver logs en tiempo real${NC}"
    echo -e "  ${CYAN}[7]${NC} ${WHITE}🔄 Reiniciar V2Ray${NC}"
    echo -e "  ${RED}[8]${NC} ${RED}🗑️  Desinstalar V2Ray por completo${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -e "  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_v2ray

    case "$opt_v2ray" in
      1) echo -e "\n  ${YELLOW}=== USUARIOS CONFIGURADOS ===${NC}"; jq -r '.inbounds[0].settings.clients | to_entries[] | "  [\(.key)] UUID: \(.value.id)"' "$V2RAY_CONF" 2>/dev/null || true; pause ;;
      2) 
        NUEVO_UUID=$(cat /proc/sys/kernel/random/uuid)
        jq --arg uuid "$NUEVO_UUID" '.inbounds[0].settings.clients += [{"id": $uuid, "alterId": 0}]' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
        systemctl restart v2ray || true
        info "Nuevo UUID añadido: $NUEVO_UUID"; pause ;;
      3) 
        jq -r '.inbounds[0].settings.clients | to_entries[] | "  [\(.key)] \(.value.id)"' "$V2RAY_CONF" 2>/dev/null || true
        read -r -p "  ➜ Ingresa el número [#] a eliminar (q para salir): " IDX
        if [[ "$IDX" =~ ^[0-9]+$ ]]; then
          jq "del(.inbounds[0].settings.clients[$IDX])" "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          info "Usuario eliminado exitosamente."
        fi
        pause ;;
      4) 
        echo -e "\n  ${YELLOW}Puerto actual:${NC} ${WHITE}$V2RAY_PORT${NC}"
        read -r -p "  ➜ Ingresa el nuevo puerto: " NUEVO_PUE
        if [[ "$NUEVO_PUE" =~ ^[0-9]+$ ]]; then
          jq --argjson p "$NUEVO_PUE" '.inbounds[0].port = $p' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          info "Puerto cambiado a $NUEVO_PUE exitosamente."
        else
          warn "Puerto inválido."
        fi
        pause ;;
      5) 
        echo -e "\n  ${YELLOW}Path actual:${NC} ${WHITE}$V2RAY_PATH${NC}"
        read -r -p "  ➜ Ingresa el nuevo path (Ej: /v2ray o /): " NUEVO_PATH
        if [[ -n "$NUEVO_PATH" ]]; then
          jq --arg path "$NUEVO_PATH" '.inbounds[0].streamSettings.wsSettings.path = $path' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          info "Path cambiado a $NUEVO_PATH exitosamente."
        else
          warn "Path no válido."
        fi
        pause ;;
      6) clear; journalctl -u v2ray -f || true; pause ;;
      7) systemctl restart v2ray || true; info "V2Ray reiniciado."; sleep 1 ;;
      8) 
        echo -e "\n  ${RED}⚠️ ¿Estás seguro de desinstalar V2Ray por completo? (s/N)${NC}"
        read -r -p "  ➜ " conf_v2
        if [[ "$conf_v2" =~ ^[sS]$ ]]; then
          systemctl stop v2ray 2>/dev/null || true
          systemctl disable v2ray 2>/dev/null || true
          rm -rf /usr/local/etc/v2ray /usr/local/share/v2ray /var/log/v2ray /etc/systemd/system/v2ray.service /usr/local/bin/v2ray 2>/dev/null || true
          systemctl daemon-reload 2>/dev/null || true
          info "V2Ray desinstalado por completo."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 5. MÓDULO: SSH-GO PROXY - ADMINISTRACIÓN COMPLETA
# =============================================
sshgo_menu() {
  PROXY_DIR="/opt/vpn-proxy"
  PROXY_SVC="vpn-proxy"

  # Verificación previa: Si SSH-Go no está instalado, se instala primero
  if [[ ! -f "$PROXY_DIR/vpn-proxy" ]]; then
    echo -e "\n  ${YELLOW}⚠️ SSH-Go Proxy no está instalado en el sistema.${NC}"
    echo -e "  ${CYAN}Iniciando instalación automática de SSH-Go...${NC}"
    download_and_execute "install-sshgo.sh"
    if [[ ! -f "$PROXY_DIR/vpn-proxy" ]]; then
      warn "No se pudo completar la instalación de SSH-Go Proxy."
      return 1
    fi
  fi

  while true; do
    if systemctl is-active --quiet "$PROXY_SVC"; then 
      PROXY_STATUS=" ${BG_GREEN} ● ACTIVO ${NC}"
    else 
      PROXY_STATUS=" ${BG_RED} ● INACTIVO ${NC}"
    fi

    if [[ -f "$PROXY_DIR/main.go" ]]; then
      PUERTOS_ACTUALES=$(grep -E 'puertos\s*}:=\s*\[\]int' "$PROXY_DIR/main.go" 2>/dev/null | grep -o '{[^}]*}' | tr -d '{} ' || echo "8080")
      [[ -z "$PUERTOS_ACTUALES" ]] && PUERTOS_ACTUALES="8080"
    else
      PUERTOS_ACTUALES="No instalado"
    fi

    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🚀 ADMINISTRADOR SSH-GO PROXY${NC}            ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}PUERTOS  :${NC} ${GREEN}${PUERTOS_ACTUALES}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${PROXY_STATUS}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}⚙️  Gestionar Puertos (Agregar/Quitar/Cambiar)${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}🧪 Prueba de Conexión (Test HTTP/SSH)${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}📜 Ver logs en tiempo real${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔄 Reiniciar Proxy${NC}"
    echo -e "  ${RED}[5]${NC} ${RED}🗑️  Desinstalar SSH-Go Proxy${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -e "  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_sshgo

    case "$opt_sshgo" in
      1) 
        echo -e "\n  ${YELLOW}=== GESTIÓN DE PUERTOS SSH-GO ===${NC}"
        echo -e "  Puertos actuales: ${WHITE}$PUERTOS_ACTUALES${NC}\n"
        echo -e "  ${CYAN}[1]${NC} ${WHITE}➕ Agregar un puerto${NC}"
        echo -e "  ${CYAN}[2]${NC} ${WHITE}➖ Quitar un puerto${NC}"
        echo -e "  ${CYAN}[3]${NC} ${WHITE}✏️  Reemplazar todos los puertos${NC}"
        read -r -p "  ➜ Selecciona una sub-opción: " opt_p_sshgo

        NEW_PORTS_LIST=""
        case "$opt_p_sshgo" in
          1)
            read -r -p "  ➜ Puerto a agregar: " ADD_P
            if [[ "$ADD_P" =~ ^[0-9]+$ && -f "$PROXY_DIR/main.go" ]]; then
              CURRENT_LIST=$(echo "$PUERTOS_ACTUALES" | tr ',' ' ')
              EXISTS=0
              for p in $CURRENT_LIST; do
                p_clean=$(echo "$p" | xargs)
                if [[ "$p_clean" == "$ADD_P" ]]; then EXISTS=1; fi
                if [[ -n "$p_clean" && "$p_clean" != "No" ]]; then
                  if [[ -z "$NEW_PORTS_LIST" ]]; then NEW_PORTS_LIST="$p_clean"; else NEW_PORTS_LIST="${NEW_PORTS_LIST}, $p_clean"; fi
                fi
              done
              if [[ $EXISTS -eq 0 ]]; then
                if [[ -z "$NEW_PORTS_LIST" ]]; then NEW_PORTS_LIST="$ADD_P"; else NEW_PORTS_LIST="${NEW_PORTS_LIST}, $ADD_P"; fi
              fi
            fi
            ;;
          2)
            read -r -p "  ➜ Puerto a quitar: " DEL_P
            if [[ "$DEL_P" =~ ^[0-9]+$ && -f "$PROXY_DIR/main.go" ]]; then
              CURRENT_LIST=$(echo "$PUERTOS_ACTUALES" | tr ',' ' ')
              for p in $CURRENT_LIST; do
                p_clean=$(echo "$p" | xargs)
                if [[ "$p_clean" != "$DEL_P" && -n "$p_clean" && "$p_clean" != "No" ]]; then
                  if [[ -z "$NEW_PORTS_LIST" ]]; then NEW_PORTS_LIST="$p_clean"; else NEW_PORTS_LIST="${NEW_PORTS_LIST}, $p_clean"; fi
                fi
              done
            fi
            ;;
          3)
            read -r -p "  ➜ Nuevos puertos (separados por comas): " NUEVOS_PUERTOS
            if [[ -n "$NUEVOS_PUERTOS" && -f "$PROXY_DIR/main.go" ]]; then
              IFS=',' read -ra ADDR <<< "$NUEVOS_PUERTOS"
              for i in "${ADDR[@]}"; do
                clean_p=$(echo "$i" | xargs)
                if [[ "$clean_p" =~ ^[0-9]+$ ]]; then
                  if [[ -z "$NEW_PORTS_LIST" ]]; then NEW_PORTS_LIST="$clean_p"; else NEW_PORTS_LIST="${NEW_PORTS_LIST}, $clean_p"; fi
                fi
              done
            fi
            ;;
        esac

        if [[ -n "$NEW_PORTS_LIST" && -f "$PROXY_DIR/main.go" ]]; then
            echo -e "  ${CYAN}Actualizando código fuente y recompilando binario...${NC}"
            sed -i -E "s/puertos\s*}:=\s*\[\]int\{[^}]+\}/puertos := []int{$NEW_PORTS_LIST}/g" "$PROXY_DIR/main.go" 2>/dev/null
            cd "$PROXY_DIR"
            export PATH=$PATH:/usr/local/go/bin
            go build -ldflags="-s -w" -o vpn-proxy main.go 2>/dev/null
            chmod +x vpn-proxy
            systemctl restart "$PROXY_SVC" 2>/dev/null || true
            info "Puertos actualizados ($NEW_PORTS_LIST) y binario recompilado."
        elif [[ -z "$NEW_PORTS_LIST" && "$opt_p_sshgo" =~ ^[123]$ ]]; then
            warn "No se pudo actualizar la lista de puertos (inválido o quedaba vacía)."
        fi
        pause ;;
      2) 
        RESP=$(curl -s -i -H 'X-Real-Host: 127.0.0.1:22' http://localhost:8080 2>/dev/null | head -n 1 || echo "Error")
        echo -e "\n  ${WHITE}Respuesta local:${NC} ${GREEN}$RESP${NC}"; pause ;;
      3) clear; journalctl -u "$PROXY_SVC" -f || true; pause ;;
      4) systemctl restart "$PROXY_SVC" || true; info "Proxy reiniciado."; sleep 1 ;;
      5) 
        echo -e "\n  ${RED}⚠️ ¿Estás seguro de desinstalar SSH-Go Proxy? (s/N)${NC}"
        read -r -p "  ➜ " conf_s
        if [[ "$conf_s" =~ ^[sS]$ ]]; then
          systemctl stop "$PROXY_SVC" 2>/dev/null || true
          systemctl disable "$PROXY_SVC" 2>/dev/null || true
          rm -f "/etc/systemd/system/${PROXY_SVC}.service" 2>/dev/null
          systemctl daemon-reload 2>/dev/null || true
          rm -rf "$PROXY_DIR" 2>/dev/null
          info "SSH-Go desinstalado correctamente."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 6. MÓDULO: FIREWALL UFW
# =============================================
firewall_menu() {
  while true; do
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then 
      FW_STATUS=" ${BG_GREEN} ● ACTIVO (Filtrando) ${NC}"
    else 
      FW_STATUS=" ${BG_RED} ● INACTIVO (Abierto) ${NC}"
    fi

    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🛡️  ADMINISTRADOR DE FIREWALL UFW${NC}          ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${FW_STATUS}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}🔍 Ver Estado y Reglas Activas${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}🔓 Abrir Todos los Puertos (TCP/UDP)${NC} ${YELLOW}[Recomendado]${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🛡️  Configuración Segura (Solo 22, 80, 443)${NC}"
    echo -e "  ${RED}[4]${NC} ${RED}🚫 Desactivar Firewall por Completo${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -e "  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_fw

    case "$opt_fw" in
      1) clear; ufw status verbose || echo "UFW no está instalado."; pause ;;
      2) ufw --force disable >/dev/null 2>&1 || true; info "Todos los puertos abiertos."; pause ;;
      3) 
        if ! command -v ufw >/dev/null 2>&1; then apt-get install -y ufw || true; fi
        ufw allow 22/tcp >/dev/null 2>&1 || true
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || true
        info "Configuración Segura Activada."; pause ;;
      4) ufw --force disable >/dev/null 2>&1 || true; warn "Firewall desactivado por completo."; pause ;;
      0) break ;;
    esac
  done
}

# =============================================
# 7. MENÚ PRINCIPAL DEL SISTEMA
# =============================================
main_menu() {
  while true; do
    display_header_main

    echo -e "  ${CYAN}[1]${NC} ${WHITE}🌐 Caddy Server${NC}          ${GRAY}(Instalar / Administrar)${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}⚡ V2Ray VMess${NC}           ${GRAY}(Instalar / Administrar)${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🚀 SSH-Go Proxy${NC}          ${GRAY}(Instalar / Administrar)${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}📦 Instalar TODO de una vez${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🛡️  Firewall UFW${NC}           ${GRAY}(Administrar Seguridad)${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}👥 SSH Panel${NC}               ${GRAY}(Gestión de usuarios SSH)${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${RED}[0]${NC} ${WHITE}🚪 SALIR DEL PANEL${NC}"
    echo -e "  ${GRAY}─────────────────────────────────────────────────────────${NC}\n"

    echo -en "  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r option

    case "$option" in
      1) caddy_menu ;;
      2) v2ray_menu ;;
      3) sshgo_menu ;;
      4)
        echo -e "\n  ${CYAN}📦 Instalando todos los servicios en secuencia...${NC}"
        download_and_execute "install-caddy.sh"
        download_and_execute "install-v2ray.sh"
        download_and_execute "install-sshgo.sh"
        ;;
      5) firewall_menu ;;
      6) 
        echo -e "\n  ${YELLOW}📥 Instalando/Ejecutando SSH Panel...${NC}"
        mkdir -p /usr/local/bin || true
        curl -fsSL "https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main/sshpanel.sh" -o /usr/local/bin/sshpanel.sh || true
        chmod +x /usr/local/bin/sshpanel.sh || true
        if ! grep -q "alias sshpanel=" ~/.bashrc 2>/dev/null; then echo "alias sshpanel='sudo /usr/local/bin/sshpanel.sh'" >> ~/.bashrc; fi
        info "SSH Panel listo para usar. Puedes ejecutar: sshpanel"
        pause
        ;;
      0) 
        clear
        echo -e "\n  ${GREEN}¡Gracias por utilizar PANEL MAESTRO VPN! 👋${NC}\n"
        exit 0 ;;
      *) sleep 1 ;;
    esac
  done
}

# =============================================
# INICIO DEL SCRIPT
# =============================================
require_root
check_dependencies
setup_menu_command
main_menu
