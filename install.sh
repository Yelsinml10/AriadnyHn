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
  local dest_path="$2"
  
  if [[ -z "$dest_path" ]]; then
    dest_path="./$script_name"
  fi
  
  echo -e "\n  ${CYAN}⬇ Descargando ${WHITE}$script_name${CYAN}...${NC}"
  if curl -fsSL "$BASE_URL/$script_name" -o "$dest_path"; then
    chmod +x "$dest_path"
    echo -e "  ${GREEN}🚀 Ejecutando ${WHITE}$script_name${GREEN}...${NC}\n"
    "$dest_path"
    echo -e "\n  ${GREEN}✔ Operación finalizada.${NC}"
    pause
  else
    echo -e "\n  ${RED}✖ Error al descargar $script_name.${NC}"
    pause
  fi
}

download_script() {
  local script_name="$1"
  local dest_path="$2"
  
  if [[ -z "$dest_path" ]]; then
    dest_path="/usr/local/bin/$(basename "$script_name" .sh)"
  fi
  
  echo -e "\n  ${CYAN}⬇ Descargando ${WHITE}$script_name${CYAN}...${NC}"
  if curl -fsSL "$BASE_URL/$script_name" -o "$dest_path"; then
    chmod +x "$dest_path"
    info "✅ Script instalado en $dest_path"
    return 0
  else
    echo -e "\n  ${RED}✖ Error al descargar $script_name.${NC}"
    return 1
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
# 3. MÓDULO: CADDY SERVER
# =============================================
caddy_menu() {
  # --- VALIDACIÓN DE INSTALACIÓN AGREGADA ---
  if ! command -v caddy >/dev/null 2>&1 || [[ ! -f "/etc/caddy/Caddyfile" ]]; then
    echo -e "\n  ${YELLOW}⚠️ Caddy Server no está instalado o falta configuración.${NC}"
    echo -e "  ${CYAN}Iniciando instalación...${NC}"
    download_and_execute "install-caddy.sh"
    
    if ! command -v caddy >/dev/null 2>&1 || [[ ! -f "/etc/caddy/Caddyfile" ]]; then
      warn "No se pudo instalar Caddy Server."
      return 1
    fi
  fi
  # ------------------------------------------

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
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🔌 Gestionar puertos HTTP${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔒 Gestionar puertos HTTPS${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}📜 Ver logs en tiempo real${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}🔄 Reiniciar Caddy${NC}"
    echo -e "  ${RED}[7]${NC} ${RED}🗑️  Desinstalar Caddy${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_caddy

    case "$opt_caddy" in
      1) clear; systemctl status caddy --no-pager || true; pause ;;
      2) 
        echo -e "\n  ${YELLOW}Dominio actual:${NC} ${WHITE}$DOMINIO_ACTUAL${NC}"
        read -r -p "  ➜ Ingresa el NUEVO dominio: " NUEVO_DOMINIO
        if [[ -n "$NUEVO_DOMINIO" && -f "$CADDY_CONF" ]]; then
            sed -i "s/$DOMINIO_ACTUAL/$NUEVO_DOMINIO/g" "$CADDY_CONF" 2>/dev/null || true
            systemctl restart caddy 2>/dev/null || true
            info "Dominio actualizado a: $NUEVO_DOMINIO"
        fi
        pause ;;
      3) 
        echo -e "\n  ${YELLOW}Puertos HTTP actuales: ${WHITE}$PUERTOS_HTTP${NC}"
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
                info "Puertos HTTP actualizados."
            fi
        fi
        pause ;;
      4) 
        echo -e "\n  ${YELLOW}Puertos HTTPS actuales: ${WHITE}$PUERTOS_HTTPS${NC}"
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
                info "Puertos HTTPS actualizados."
            fi
        fi
        pause ;;
      5) clear; journalctl -u caddy -f || true; pause ;;
      6) systemctl restart caddy || true; info "Caddy reiniciado."; sleep 1 ;;
      7) 
        echo -e "\n  ${RED}⚠️ ¿Desinstalar Caddy? (s/N)${NC}"
        read -r -p "  ➜ " conf_caddy
        if [[ "$conf_caddy" =~ ^[sS]$ ]]; then
          systemctl stop caddy 2>/dev/null || true
          systemctl disable caddy 2>/dev/null || true
          apt-get purge -y caddy 2>/dev/null || true
          rm -rf /etc/caddy 2>/dev/null || true
          info "Caddy desinstalado."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 4. MÓDULO: V2RAY (VMESS)
# =============================================
v2ray_menu() {
  if ! command -v v2ray >/dev/null 2>&1 || [[ ! -f "/usr/local/etc/v2ray/config.json" ]]; then
    echo -e "\n  ${YELLOW}⚠️ V2Ray no está instalado.${NC}"
    download_and_execute "install-v2ray.sh"
    if ! command -v v2ray >/dev/null 2>&1 || [[ ! -f "/usr/local/etc/v2ray/config.json" ]]; then
      warn "No se pudo instalar V2Ray."
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
    echo -e "  ${PURPLE}│${NC} ${CYAN}PUERTO   :${NC} ${GREEN}${V2RAY_PORT}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}PATH     :${NC} ${YELLOW}${V2RAY_PATH}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}USUARIOS :${NC} ${WHITE}${V2RAY_USERS}${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${V2RAY_STATUS}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📋 Listar Usuarios${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}➕ Añadir usuario${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🗑️  Eliminar usuario${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔌 Cambiar puerto${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🔀 Cambiar PATH${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}📜 Ver logs${NC}"
    echo -e "  ${CYAN}[7]${NC} ${WHITE}🔄 Reiniciar V2Ray${NC}"
    echo -e "  ${RED}[8]${NC} ${RED}🗑️  Desinstalar V2Ray${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_v2ray

    case "$opt_v2ray" in
      1) echo -e "\n  ${YELLOW}USUARIOS:${NC}"; jq -r '.inbounds[0].settings.clients | to_entries[] | "  [\(.key)] UUID: \(.value.id)"' "$V2RAY_CONF" 2>/dev/null || true; pause ;;
      2) 
        NUEVO_UUID=$(cat /proc/sys/kernel/random/uuid)
        jq --arg uuid "$NUEVO_UUID" '.inbounds[0].settings.clients += [{"id": $uuid, "alterId": 0}]' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
        systemctl restart v2ray || true
        info "Nuevo UUID: $NUEVO_UUID"; pause ;;
      3) 
        jq -r '.inbounds[0].settings.clients | to_entries[] | "  [\(.key)] \(.value.id)"' "$V2RAY_CONF" 2>/dev/null || true
        read -r -p "  ➜ Número a eliminar: " IDX
        if [[ "$IDX" =~ ^[0-9]+$ ]]; then
          jq "del(.inbounds[0].settings.clients[$IDX])" "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          info "Usuario eliminado."
        fi
        pause ;;
      4) 
        read -r -p "  ➜ Nuevo puerto: " NUEVO_PUE
        if [[ "$NUEVO_PUE" =~ ^[0-9]+$ ]]; then
          jq --argjson p "$NUEVO_PUE" '.inbounds[0].port = $p' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          info "Puerto cambiado a $NUEVO_PUE"
        fi
        pause ;;
      5) 
        read -r -p "  ➜ Nuevo path: " NUEVO_PATH
        if [[ -n "$NUEVO_PATH" ]]; then
          jq --arg path "$NUEVO_PATH" '.inbounds[0].streamSettings.wsSettings.path = $path' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          info "Path cambiado a $NUEVO_PATH"
        fi
        pause ;;
      6) clear; journalctl -u v2ray -f || true; pause ;;
      7) systemctl restart v2ray || true; info "V2Ray reiniciado."; sleep 1 ;;
      8) 
        echo -e "\n  ${RED}⚠️ ¿Desinstalar V2Ray? (s/N)${NC}"
        read -r -p "  ➜ " conf_v2
        if [[ "$conf_v2" =~ ^[sS]$ ]]; then
          systemctl stop v2ray 2>/dev/null || true
          systemctl disable v2ray 2>/dev/null || true
          rm -rf /usr/local/etc/v2ray /usr/local/share/v2ray /var/log/v2ray /etc/systemd/system/v2ray.service /usr/local/bin/v2ray 2>/dev/null || true
          systemctl daemon-reload 2>/dev/null || true
          info "V2Ray desinstalado."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 5. MÓDULO: SSH-GO PROXY
# =============================================
sshgo_menu() {
  PROXY_DIR="/opt/vpn-proxy"
  PROXY_SVC="vpn-proxy"

  if [[ ! -f "$PROXY_DIR/vpn-proxy" ]]; then
    echo -e "\n  ${YELLOW}⚠️ SSH-Go Proxy no está instalado.${NC}"
    echo -e "  ${CYAN}Iniciando instalación...${NC}"
    download_and_execute "install-sshgo.sh"
    if [[ ! -f "$PROXY_DIR/vpn-proxy" ]]; then
      warn "No se pudo instalar SSH-Go Proxy."
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
      PUERTOS_ACTUALES=$(grep -E 'puertos\s*:?=\s*\[\]int' "$PROXY_DIR/main.go" 2>/dev/null | grep -o '{[^}]*}' | tr -d '{} ' || echo "8080")
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

    echo -e "  ${CYAN}[1]${NC} ${WHITE}➕ Agregar Puertos${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}➖ Quitar Puertos${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🧪 Prueba de Conexión${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}📜 Ver logs${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🔄 Reiniciar Proxy${NC}"
    echo -e "  ${RED}[6]${NC} ${RED}🗑️  Desinstalar${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_sshgo

    case "$opt_sshgo" in
      1) 
        echo -e "\n  ${YELLOW}Puertos actuales: ${WHITE}$PUERTOS_ACTUALES${NC}"
        read -r -p "  ➜ Puertos a AGREGAR (separados por comas): " PUERTOS_ADD
        if [[ -n "$PUERTOS_ADD" && -f "$PROXY_DIR/main.go" ]]; then
          # Combinar puertos actuales y nuevos, limpiar espacios, separar por líneas, 
          # quitar duplicados y volver a unir con comas
          COMBINADOS="${PUERTOS_ACTUALES}, ${PUERTOS_ADD}"
          NEW_PORTS_LIST=$(echo "$COMBINADOS" | tr ',' '\n' | sed 's/ //g' | grep -v '^$' | sort -u | paste -sd "," - | sed 's/,/, /g')
          
          if [[ -n "$NEW_PORTS_LIST" ]]; then
            sed -i -E "s/puertos\s*:?=\s*\[\]int\{[^}]*\}/puertos := []int{$NEW_PORTS_LIST}/g" "$PROXY_DIR/main.go" 2>/dev/null
            cd "$PROXY_DIR"
            export PATH=$PATH:/usr/local/go/bin
            go build -ldflags="-s -w" -o vpn-proxy main.go 2>/dev/null
            chmod +x vpn-proxy
            systemctl restart "$PROXY_SVC" 2>/dev/null || true
            info "Puertos actualizados a: $NEW_PORTS_LIST"
          fi
        fi
        pause ;;
      2)
        echo -e "\n  ${YELLOW}Puertos actuales: ${WHITE}$PUERTOS_ACTUALES${NC}"
        read -r -p "  ➜ Puertos a QUITAR (separados por comas): " PUERTOS_DEL
        if [[ -n "$PUERTOS_DEL" && -f "$PROXY_DIR/main.go" ]]; then
          IFS=',' read -ra ARR_ACT <<< "$PUERTOS_ACTUALES"
          IFS=',' read -ra ARR_DEL <<< "$PUERTOS_DEL"
          
          NEW_PORTS_LIST=""
          for act_p in "${ARR_ACT[@]}"; do
            clean_act=$(echo "$act_p" | xargs)
            mantener=true
            for del_p in "${ARR_DEL[@]}"; do
              clean_del=$(echo "$del_p" | xargs)
              if [[ "$clean_act" == "$clean_del" ]]; then
                mantener=false
                break
              fi
            done
            if $mantener; then
              if [[ -z "$NEW_PORTS_LIST" ]]; then NEW_PORTS_LIST="$clean_act"; else NEW_PORTS_LIST="${NEW_PORTS_LIST}, $clean_act"; fi
            fi
          done

          if [[ -n "$NEW_PORTS_LIST" ]]; then
            sed -i -E "s/puertos\s*:?=\s*\[\]int\{[^}]*\}/puertos := []int{$NEW_PORTS_LIST}/g" "$PROXY_DIR/main.go" 2>/dev/null
            cd "$PROXY_DIR"
            export PATH=$PATH:/usr/local/go/bin
            go build -ldflags="-s -w" -o vpn-proxy main.go 2>/dev/null
            chmod +x vpn-proxy
            systemctl restart "$PROXY_SVC" 2>/dev/null || true
            info "Puertos actualizados a: $NEW_PORTS_LIST"
          else
            warn "No puedes dejar el proxy sin puertos. Operación cancelada."
          fi
        fi
        pause ;;
      3) 
        RESP=$(curl -s -i -H 'X-Real-Host: 127.0.0.1:22' http://localhost:8080 2>/dev/null | head -n 1 || echo "Error")
        echo -e "\n  ${WHITE}Respuesta:${NC} ${GREEN}$RESP${NC}"; pause ;;
      4) clear; journalctl -u "$PROXY_SVC" -f || true; pause ;;
      5) systemctl restart "$PROXY_SVC" || true; info "Proxy reiniciado."; sleep 1 ;;
      6) 
        echo -e "\n  ${RED}⚠️ ¿Desinstalar SSH-Go? (s/N)${NC}"
        read -r -p "  ➜ " conf_s
        if [[ "$conf_s" =~ ^[sS]$ ]]; then
          systemctl stop "$PROXY_SVC" 2>/dev/null || true
          systemctl disable "$PROXY_SVC" 2>/dev/null || true
          rm -f "/etc/systemd/system/${PROXY_SVC}.service" 2>/dev/null
          systemctl daemon-reload 2>/dev/null || true
          rm -rf "$PROXY_DIR" 2>/dev/null
          info "SSH-Go desinstalado."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 6. MÓDULO: FIREWALL
# =============================================
firewall_menu() {
  if [[ -f "/usr/local/bin/firewall.sh" ]] && [[ -x "/usr/local/bin/firewall.sh" ]]; then
    FW_STATUS=" ${BG_GREEN} ● INSTALADO ${NC}"
  else
    FW_STATUS=" ${BG_RED} ● NO INSTALADO ${NC}"
  fi

  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🛡️  ADMINISTRADOR DE FIREWALL${NC}              ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${FW_STATUS}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📥 Instalar Firewall${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}🔓 Abrir TODOS los puertos${NC} ${YELLOW}[Recomendado]${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🛡️  Configuración SEGURA${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🚫 Desactivar Firewall${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🔍 Ver estado${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}📋 Ver puertos abiertos${NC}"
    echo -e "  ${RED}[7]${NC} ${RED}🗑️  Desinstalar${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_fw

    case "$opt_fw" in
      1) 
        echo -e "\n  ${CYAN}📥 Descargando Firewall...${NC}"
        if curl -fsSL "$BASE_URL/firewall.sh" -o /usr/local/bin/firewall.sh; then
          chmod +x /usr/local/bin/firewall.sh
          FW_STATUS=" ${BG_GREEN} ● INSTALADO ${NC}"
          info "✅ Firewall instalado"
          /usr/local/bin/firewall.sh
        else
          echo -e "\n  ${RED}✖ Error al descargar${NC}"
        fi
        pause
        ;;
      2)
        if [[ -f "/usr/local/bin/firewall.sh" ]]; then
          clear; echo "1" | /usr/local/bin/firewall.sh
          echo -e "\n  ${GREEN}✅ Todos los puertos abiertos.${NC}"
        else
          echo -e "\n  ${YELLOW}⚠️ Firewall no instalado.${NC}"
        fi
        pause
        ;;
      3)
        if [[ -f "/usr/local/bin/firewall.sh" ]]; then
          clear; echo "2" | /usr/local/bin/firewall.sh
          echo -e "\n  ${GREEN}✅ Configuración segura activada.${NC}"
        else
          echo -e "\n  ${YELLOW}⚠️ Firewall no instalado.${NC}"
        fi
        pause
        ;;
      4)
        if [[ -f "/usr/local/bin/firewall.sh" ]]; then
          clear; echo "3" | /usr/local/bin/firewall.sh
          echo -e "\n  ${YELLOW}⚠️ Firewall desactivado.${NC}"
        else
          echo -e "\n  ${YELLOW}⚠️ Firewall no instalado.${NC}"
        fi
        pause
        ;;
      5)
        if [[ -f "/usr/local/bin/firewall.sh" ]]; then
          clear; echo "4" | /usr/local/bin/firewall.sh
        else
          echo -e "\n  ${YELLOW}⚠️ Firewall no instalado.${NC}"
        fi
        pause
        ;;
      6)
        if [[ -f "/usr/local/bin/firewall.sh" ]]; then
          clear; echo "5" | /usr/local/bin/firewall.sh
        else
          echo -e "\n  ${YELLOW}⚠️ Firewall no instalado.${NC}"
        fi
        pause
        ;;
      7)
        if [[ -f "/usr/local/bin/firewall.sh" ]]; then
          echo -e "\n  ${RED}⚠️ ¿Desinstalar Firewall? (s/N)${NC}"
          read -r -p "  ➜ " conf_fw
          if [[ "$conf_fw" =~ ^[sS]$ ]]; then
            rm -f /usr/local/bin/firewall.sh
            iptables -P INPUT ACCEPT 2>/dev/null
            iptables -P FORWARD ACCEPT 2>/dev/null
            iptables -F 2>/dev/null
            FW_STATUS=" ${BG_RED} ● NO INSTALADO ${NC}"
            info "Firewall desinstalado."
          fi
        else
          echo -e "\n  ${YELLOW}⚠️ Firewall no instalado.${NC}"
        fi
        pause
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 7. MÓDULO: XRAY PANEL (DESDE REPOSITORIO)
# =============================================
xray_menu() {
  # Verificar si XRay está instalado (buscar binario)
  local XRAY_BIN=""
  if [[ -x "/usr/local/bin/v2ray" ]]; then
    XRAY_BIN="/usr/local/bin/v2ray"
  elif [[ -x "/usr/local/bin/xray" ]]; then
    XRAY_BIN="/usr/local/bin/xray"
  elif [[ -x "/usr/bin/v2ray" ]]; then
    XRAY_BIN="/usr/bin/v2ray"
  fi

  if [[ -z "$XRAY_BIN" ]]; then
    echo -e "\n  ${YELLOW}⚠️ XRay no está instalado en el sistema.${NC}"
    echo -e "  ${CYAN}📥 Descargando e instalando XRay...${NC}"
    
    # Descargar el script de XRay
    if curl -fsSL "$BASE_URL/xray.sh" -o /tmp/xray_install.sh; then
      chmod +x /tmp/xray_install.sh
      /tmp/xray_install.sh
      rm -f /tmp/xray_install.sh
      echo -e "\n  ${GREEN}✅ XRay instalado correctamente.${NC}"
      echo -e "  ${CYAN}💡 Puedes ejecutar 'menuV2' para acceder al menú XRay.${NC}"
      pause
    else
      echo -e "\n  ${RED}✖ Error al descargar XRay.${NC}"
      pause
      return 1
    fi
  fi

  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🔰 ADMINISTRADOR XRAY${NC}                     ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    
    if systemctl is-active --quiet v2ray 2>/dev/null; then
      echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${BG_GREEN} ● ACTIVO ${NC}"
    elif systemctl is-active --quiet xray 2>/dev/null; then
      echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${BG_GREEN} ● ACTIVO ${NC}"
    else
      echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${BG_RED} ● INACTIVO ${NC}"
    fi
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📥 Instalar/Actualizar XRay${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}📊 Abrir Menú XRay (menuV2)${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}📋 Ver estado del servicio${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}📜 Ver logs en tiempo real${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🔄 Reiniciar servicio${NC}"
    echo -e "  ${RED}[6]${NC} ${RED}🗑️  Desinstalar XRay${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_xray

    case "$opt_xray" in
      1) 
        echo -e "\n  ${CYAN}📥 Instalando XRay...${NC}"
        if curl -fsSL "$BASE_URL/xray.sh" -o /tmp/xray_install.sh; then
          chmod +x /tmp/xray_install.sh
          /tmp/xray_install.sh
          rm -f /tmp/xray_install.sh
          info "✅ XRay instalado correctamente"
          echo -e "  ${CYAN}💡 Ejecuta 'menuV2' para acceder al menú.${NC}"
        else
          echo -e "\n  ${RED}✖ Error al descargar.${NC}"
        fi
        pause
        ;;
      2) 
        # Buscar el binario de XRay
        local XRAY_CMD=""
        if [[ -x "/usr/local/bin/v2ray" ]]; then
          XRAY_CMD="/usr/local/bin/v2ray"
        elif [[ -x "/usr/local/bin/xray" ]]; then
          XRAY_CMD="/usr/local/bin/xray"
        elif [[ -x "/usr/bin/v2ray" ]]; then
          XRAY_CMD="/usr/bin/v2ray"
        elif [[ -x "/usr/bin/xray" ]]; then
          XRAY_CMD="/usr/bin/xray"
        fi
        
        if [[ -n "$XRAY_CMD" ]]; then
          echo -e "\n  ${CYAN}📊 Abriendo menú XRay...${NC}"
          "$XRAY_CMD"
        else
          echo -e "\n  ${YELLOW}⚠️ XRay no instalado. Usa opción [1] para instalar.${NC}"
          pause
        fi
        ;;
      3) 
        if systemctl list-units --full -all | grep -q "v2ray.service"; then
          clear; systemctl status v2ray --no-pager
        elif systemctl list-units --full -all | grep -q "xray.service"; then
          clear; systemctl status xray --no-pager
        else
          echo -e "\n  ${YELLOW}⚠️ Servicio no encontrado.${NC}"
        fi
        pause
        ;;
      4) 
        if systemctl list-units --full -all | grep -q "v2ray.service"; then
          clear; journalctl -u v2ray -f -n 20
        elif systemctl list-units --full -all | grep -q "xray.service"; then
          clear; journalctl -u xray -f -n 20
        else
          echo -e "\n  ${YELLOW}⚠️ Servicio no encontrado.${NC}"
          pause
        fi
        ;;
      5) 
        if systemctl list-units --full -all | grep -q "v2ray.service"; then
          systemctl restart v2ray
          info "XRay reiniciado"
        elif systemctl list-units --full -all | grep -q "xray.service"; then
          systemctl restart xray
          info "XRay reiniciado"
        else
          echo -e "\n  ${YELLOW}⚠️ Servicio no encontrado.${NC}"
        fi
        pause
        ;;
      6) 
        echo -e "\n  ${RED}⚠️ ¿Desinstalar XRay? (s/N)${NC}"
        read -r -p "  ➜ " conf_xray
        if [[ "$conf_xray" =~ ^[sS]$ ]]; then
          systemctl stop v2ray xray 2>/dev/null
          systemctl disable v2ray xray 2>/dev/null
          rm -rf /usr/local/bin/v2ray /usr/local/bin/xray /usr/local/v2ray /usr/local/xray 2>/dev/null
          rm -f /usr/bin/v2ray /usr/bin/xray /usr/local/bin/menuV2 /usr/bin/menuV2 2>/dev/null
          rm -f /etc/systemd/system/v2ray.service /etc/systemd/system/xray.service 2>/dev/null
          systemctl daemon-reload
          info "XRay desinstalado."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 8. MÓDULO: UDP PANEL (DESDE REPOSITORIO)
# =============================================
udp_menu() {
  # Verificar si UDP está instalado
  if [[ ! -f "/usr/bin/menuUDP" ]] && [[ ! -x "/usr/local/bin/udp-custom" ]] && [[ ! -d "/etc/hysteria" ]]; then
    echo -e "\n  ${YELLOW}⚠️ UDP no está instalado en el sistema.${NC}"
    echo -e "  ${CYAN}📥 Descargando e instalando UDP...${NC}"
    
    if curl -fsSL "$BASE_URL/Udp.sh" -o /tmp/udp_install.sh; then
      chmod +x /tmp/udp_install.sh
      /tmp/udp_install.sh
      rm -f /tmp/udp_install.sh
      echo -e "\n  ${GREEN}✅ UDP instalado correctamente.${NC}"
      echo -e "  ${CYAN}💡 Puedes ejecutar 'menuUDP' para acceder al menú.${NC}"
      pause
    else
      echo -e "\n  ${RED}✖ Error al descargar UDP.${NC}"
      pause
      return 1
    fi
  fi

  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}⚡ ADMINISTRADOR UDP${NC}                       ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    
    local udp_status=""
    if systemctl is-active --quiet udp-hysteria 2>/dev/null; then
      udp_status="${udp_status} ${BG_GREEN}HYSTERIA${NC}"
    fi
    if systemctl is-active --quiet udp-custom 2>/dev/null; then
      udp_status="${udp_status} ${BG_GREEN}CUSTOM${NC}"
    fi
    if systemctl is-active --quiet zivpn 2>/dev/null; then
      udp_status="${udp_status} ${BG_GREEN}ZI VPN${NC}"
    fi
    if [[ -z "$udp_status" ]]; then
      udp_status="${BG_RED} ● SIN SERVICIOS${NC}"
    fi
    
    echo -e "  ${PURPLE}│${NC} ${CYAN}ESTADO   :${NC}${udp_status}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📥 Instalar/Actualizar UDP${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}📊 Abrir Menú UDP (menuUDP)${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}📋 Ver servicios activos${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔄 Reiniciar servicios UDP${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}📜 Ver logs${NC}"
    echo -e "  ${RED}[6]${NC} ${RED}🗑️  Desinstalar UDP${NC}"
    echo -e "\n  ${GRAY}─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_udp

    case "$opt_udp" in
      1) 
        echo -e "\n  ${CYAN}📥 Instalando UDP...${NC}"
        if curl -fsSL "$BASE_URL/Udp.sh" -o /tmp/udp_install.sh; then
          chmod +x /tmp/udp_install.sh
          /tmp/udp_install.sh
          rm -f /tmp/udp_install.sh
          info "✅ UDP instalado correctamente"
          echo -e "  ${CYAN}💡 Ejecuta 'menuUDP' para acceder al menú.${NC}"
        else
          echo -e "\n  ${RED}✖ Error al descargar.${NC}"
        fi
        pause
        ;;
      2) 
        if [[ -x "/usr/bin/menuUDP" ]]; then
          echo -e "\n  ${CYAN}📊 Abriendo menú UDP...${NC}"
          /usr/bin/menuUDP
        elif [[ -x "/usr/local/bin/menuUDP" ]]; then
          echo -e "\n  ${CYAN}📊 Abriendo menú UDP...${NC}"
          /usr/local/bin/menuUDP
        else
          echo -e "\n  ${YELLOW}⚠️ UDP no instalado. Usa opción [1] para instalar.${NC}"
          pause
        fi
        ;;
      3) 
        clear
        echo -e "\n  ${YELLOW}📋 Servicios UDP:${NC}"
        echo -e "  ${CYAN}• Hysteria:${NC} $(systemctl is-active udp-hysteria 2>/dev/null || echo 'inactivo')"
        echo -e "  ${CYAN}• UDP Custom:${NC} $(systemctl is-active udp-custom 2>/dev/null || echo 'inactivo')"
        echo -e "  ${CYAN}• ZI VPN:${NC} $(systemctl is-active zivpn 2>/dev/null || echo 'inactivo')"
        pause
        ;;
      4) 
        echo -e "\n  ${CYAN}🔄 Reiniciando servicios UDP...${NC}"
        systemctl restart udp-hysteria 2>/dev/null && info "Hysteria reiniciado"
        systemctl restart udp-custom 2>/dev/null && info "UDP Custom reiniciado"
        systemctl restart zivpn 2>/dev/null && info "ZI VPN reiniciado"
        pause
        ;;
      5) 
        echo -e "\n  ${CYAN}📜 Logs de UDP:${NC}"
        journalctl -u udp-hysteria -u udp-custom -u zivpn -n 20 --no-pager 2>/dev/null || echo "No hay logs"
        pause
        ;;
      6) 
        echo -e "\n  ${RED}⚠️ ¿Desinstalar UDP? (s/N)${NC}"
        read -r -p "  ➜ " conf_udp
        if [[ "$conf_udp" =~ ^[sS]$ ]]; then
          systemctl stop udp-hysteria udp-custom zivpn 2>/dev/null
          systemctl disable udp-hysteria udp-custom zivpn 2>/dev/null
          rm -rf /etc/hysteria /etc/udp-custom /etc/zivpn 2>/dev/null
          rm -f /usr/local/bin/udp-custom /usr/local/bin/hysteria /usr/local/bin/zivpn 2>/dev/null
          rm -f /usr/bin/menuUDP /usr/local/bin/menuUDP 2>/dev/null
          rm -f /etc/systemd/system/udp-hysteria.service /etc/systemd/system/udp-custom.service /etc/systemd/system/zivpn.service 2>/dev/null
          systemctl daemon-reload
          info "UDP desinstalado."
          pause
          break
        fi
        ;;
      0) break ;;
    esac
  done
}

# =============================================
# 9. MÓDULO: MONITOREO DEL SISTEMA
# =============================================
monitoreo_menu() {
  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}📊 MONITOREO DEL SISTEMA${NC}                  ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}🖥️  CPU    :${NC} ${WHITE}$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%%${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}🧠 RAM    :${NC} ${WHITE}$(free -m | awk 'NR==2{printf "%sMB / %sMB (%.1f%%)", $3, $2, $3*100/$2}')${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}💾 DISCO  :${NC} ${WHITE}$(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}📶 RED    :${NC} ${WHITE}$(vnstat -h 2>/dev/null | grep "today" | awk '{print $3, $4}' || echo "N/A")${NC}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📊 Estadísticas en tiempo real${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}📈 Historial de uso de red${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🔍 Procesos activos${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}💾 Estado de discos${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_mon

    case "$opt_mon" in
      1) clear; htop || top ;;
      2) clear; vnstat -d || nethogs ;;
      3) clear; ps aux --sort=-%cpu | head -20 ;;
      4) clear; df -h ;;
      0) break ;;
    esac
    pause
  done
}

# =============================================
# 10. MÓDULO: BACKUP DE CONFIGURACIONES
# =============================================
backup_menu() {
  BACKUP_DIR="/root/backups"
  mkdir -p "$BACKUP_DIR"
  
  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}💾 BACKUP Y RESTAURACIÓN${NC}                  ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}📁 Directorio :${NC} ${WHITE}$BACKUP_DIR${NC}"
    echo -e "  ${PURPLE}│${NC} ${CYAN}📦 Backups   :${NC} ${WHITE}$(ls -1 $BACKUP_DIR/*.tar.gz 2>/dev/null | wc -l)${NC}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📦 Crear Backup completo${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}📂 Listar Backups${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🔄 Restaurar Backup${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🗑️  Eliminar Backup${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_backup

    case "$opt_backup" in
      1)
        FECHA=$(date +%Y%m%d_%H%M%S)
        echo -e "\n  ${CYAN}📦 Creando backup: backup_$FECHA.tar.gz${NC}"
        tar -czf "$BACKUP_DIR/backup_$FECHA.tar.gz" \
          /etc/caddy/Caddyfile \
          /usr/local/etc/v2ray/config.json \
          /opt/vpn-proxy/main.go \
          /etc/hysteria \
          /etc/udp-custom \
          /etc/zivpn 2>/dev/null
        info "✅ Backup creado: backup_$FECHA.tar.gz"
        ;;
      2)
        echo -e "\n  ${YELLOW}📂 Backups disponibles:${NC}"
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "  No hay backups"
        ;;
      3)
        echo -e "\n  ${YELLOW}📂 Backups disponibles:${NC}"
        ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | nl
        read -r -p "  ➜ Número de backup a restaurar: " num
        BACKUP_FILE=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | sed -n "${num}p")
        if [[ -f "$BACKUP_FILE" ]]; then
          tar -xzf "$BACKUP_FILE" -C /
          info "✅ Backup restaurado: $(basename $BACKUP_FILE)"
        else
          warn "Backup no encontrado"
        fi
        ;;
      4)
        echo -e "\n  ${YELLOW}📂 Backups disponibles:${NC}"
        ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | nl
        read -r -p "  ➜ Número de backup a eliminar: " num
        BACKUP_FILE=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | sed -n "${num}p")
        if [[ -f "$BACKUP_FILE" ]]; then
          rm -f "$BACKUP_FILE"
          info "✅ Backup eliminado: $(basename $BACKUP_FILE)"
        else
          warn "Backup no encontrado"
        fi
        ;;
      0) break ;;
    esac
    pause
  done
}

# =============================================
# 11. MÓDULO: CERTIFICADOS SSL
# =============================================
ssl_menu() {
  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🔐 CERTIFICADOS SSL${NC}                       ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ├─────────────────────────────────────────────────────────┤${NC}"
    
    if [[ -f "/etc/ssl/certs/caddy.pem" ]]; then
      EXPIRA=$(openssl x509 -enddate -noout -in /etc/ssl/certs/caddy.pem 2>/dev/null | cut -d= -f2)
      echo -e "  ${PURPLE}│${NC} ${CYAN}📜 Certificado :${NC} ${GREEN}Instalado${NC}"
      echo -e "  ${PURPLE}│${NC} ${CYAN}⏰ Expira     :${NC} ${WHITE}$EXPIRA${NC}"
    else
      echo -e "  ${PURPLE}│${NC} ${CYAN}📜 Certificado :${NC} ${RED}No instalado${NC}"
    fi
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}📥 Generar certificado SSL${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}🔍 Verificar certificado${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🔄 Renovar certificado${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}📋 Ver detalles${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_ssl

    case "$opt_ssl" in
      1)
        read -r -p "  ➜ Dominio: " DOMINIO_SSL
        if [[ -n "$DOMINIO_SSL" ]]; then
          apt-get install -y certbot 2>/dev/null
          certbot certonly --standalone -d "$DOMINIO_SSL" --non-interactive --agree-tos -m admin@"$DOMINIO_SSL"
          info "✅ Certificado generado para $DOMINIO_SSL"
        fi
        ;;
      2)
        echo -e "\n  ${CYAN}🔍 Verificando certificados...${NC}"
        certbot certificates 2>/dev/null || echo "No hay certificados"
        ;;
      3)
        certbot renew --dry-run
        info "✅ Renovación verificada"
        ;;
      4)
        if [[ -f "/etc/letsencrypt/live/$DOMINIO_ACTUAL/fullchain.pem" ]]; then
          openssl x509 -in "/etc/letsencrypt/live/$DOMINIO_ACTUAL/fullchain.pem" -text -noout
        else
          echo "No hay certificado disponible"
        fi
        ;;
      0) break ;;
    esac
    pause
  done
}

# =============================================
# 12. MÓDULO: SEGURIDAD AVANZADA
# =============================================
seguridad_menu() {
  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🛡️  SEGURIDAD AVANZADA${NC}                    ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}🔐 Cambiar puerto SSH${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}🚫 Bloquear IP${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}📋 Ver intentos fallidos${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🔄 Configurar fail2ban${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}📊 Ver logs de seguridad${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}🔍 Escanear puertos abiertos${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_sec

    case "$opt_sec" in
      1)
        read -r -p "  ➜ Nuevo puerto SSH (ej: 2222): " NEW_SSH_PORT
        if [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] && [[ "$NEW_SSH_PORT" -ge 1 ]] && [[ "$NEW_SSH_PORT" -le 65535 ]]; then
          sed -i "s/#Port 22/Port $NEW_SSH_PORT/g" /etc/ssh/sshd_config
          sed -i "s/Port 22/Port $NEW_SSH_PORT/g" /etc/ssh/sshd_config
          systemctl restart sshd
          info "✅ Puerto SSH cambiado a $NEW_SSH_PORT"
        fi
        ;;
      2)
        read -r -p "  ➜ IP a bloquear: " IP_BLOCK
        if [[ -n "$IP_BLOCK" ]]; then
          iptables -A INPUT -s $IP_BLOCK -j DROP
          iptables -A FORWARD -s $IP_BLOCK -j DROP
          info "✅ IP $IP_BLOCK bloqueada"
        fi
        ;;
      3)
        echo -e "\n  ${YELLOW}📋 Últimos intentos fallidos:${NC}"
        grep "Failed password" /var/log/auth.log | tail -10 || echo "No hay intentos fallidos"
        ;;
      4)
        apt-get install -y fail2ban 2>/dev/null
        systemctl enable fail2ban
        systemctl start fail2ban
        info "✅ fail2ban instalado"
        ;;
      5)
        echo -e "\n  ${YELLOW}📊 Logs de seguridad:${NC}"
        tail -20 /var/log/auth.log
        ;;
      6)
        echo -e "\n  ${CYAN}🔍 Puertos abiertos:${NC}"
        netstat -tulpn | grep LISTEN | column -t
        ;;
      0) break ;;
    esac
    pause
  done
}

# =============================================
# 13. MÓDULO: LIMPIEZA DEL SISTEMA
# =============================================
limpieza_menu() {
  while true; do
    draw_header
    echo -e "${PURPLE}  ╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${PURPLE}│${NC}        ${BOLD}${WHITE}🧹 LIMPIEZA DEL SISTEMA${NC}                    ${PURPLE}│${NC}"
    echo -e "${PURPLE}  ╰─────────────────────────────────────────────────────────╯${NC}\n"

    echo -e "  ${CYAN}[1]${NC} ${WHITE}🗑️  Limpiar caché de APT${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}📁 Limpiar logs antiguos${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}💾 Liberar espacio en disco${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}🧹 Limpiar paquetes huérfanos${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}📊 Ver uso de disco${NC}"
    echo -e "  ${YELLOW}[0]${NC} ${WHITE}⬅  Volver al Menú Principal${NC}"
    echo -en "\n  ${GREEN}❯❯❯ Selecciona una opción:${NC} "
    read -r opt_clean

    case "$opt_clean" in
      1) apt-get clean; apt-get autoclean; info "✅ Caché limpiado" ;;
      2) journalctl --vacuum-time=3d; info "✅ Logs antiguos eliminados" ;;
      3) apt-get autoremove -y; docker system prune -f 2>/dev/null || true; info "✅ Espacio liberado" ;;
      4) apt-get autoremove -y; info "✅ Paquetes huérfanos eliminados" ;;
      5) clear; df -h; echo -e "\n  ${CYAN}Directorios más pesados:${NC}"; du -sh /* 2>/dev/null | sort -hr | head -10 ;;
      0) break ;;
    esac
    pause
  done
}

# =============================================
# 14. MENÚ PRINCIPAL DEL SISTEMA (ACTUALIZADO)
# =============================================
main_menu() {
  while true; do
    display_header_main

    echo -e "  ${CYAN}[1]${NC} ${WHITE}🌐 Caddy Server${NC}          ${GRAY}(Instalar / Administrar)${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}⚡ V2Ray VMess${NC}           ${GRAY}(Instalar / Administrar)${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}🚀 SSH-Go Proxy${NC}          ${GRAY}(Instalar / Administrar)${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}📦 Instalar TODO de una vez${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}🛡️  Firewall${NC}               ${GRAY}(Administrar Seguridad)${NC}"
    echo -e "  ${CYAN}[6]${NC} ${WHITE}👥 SSH Panel${NC}               ${GRAY}(Gestión de usuarios SSH)${NC}"
    echo -e "  ${CYAN}[7]${NC} ${WHITE}📊 Monitoreo${NC}               ${GRAY}(Estado del sistema)${NC}"
    echo -e "  ${CYAN}[8]${NC} ${WHITE}💾 Backup${NC}                   ${GRAY}(Copias de seguridad)${NC}"
    echo -e "  ${CYAN}[9]${NC} ${WHITE}🔐 SSL Certificados${NC}        ${GRAY}(SSL/HTTPS)${NC}"
    echo -e "  ${CYAN}[10]${NC} ${WHITE}🛡️  Seguridad Avanzada${NC}     ${GRAY}(Protección extra)${NC}"
    echo -e "  ${CYAN}[11]${NC} ${WHITE}🧹 Limpieza del Sistema${NC}    ${GRAY}(Liberar espacio)${NC}"
    echo -e "  ${CYAN}[12]${NC} ${WHITE}🔰 XRay Panel${NC}              ${GRAY}(VLESS/VMess/Trojan)${NC}"
    echo -e "  ${CYAN}[13]${NC} ${WHITE}⚡ UDP Panel${NC}                ${GRAY}(Hysteria/Custom/ZI)${NC}"
    echo -e "  ${CYAN}[14]${NC} ${WHITE}🔄 Actualizar Panel${NC}       ${GRAY}(Última versión)${NC}"
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
        echo -e "\n  ${CYAN}📦 Instalando todos los servicios...${NC}"
        download_and_execute "install-caddy.sh"
        download_and_execute "install-v2ray.sh"
        download_and_execute "install-sshgo.sh"
        ;;
      5) firewall_menu ;;
      6) 
        echo -e "\n  ${YELLOW}📥 Instalando SSH Panel...${NC}"
        mkdir -p /usr/local/bin || true
        curl -fsSL "https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main/sshpanel.sh" -o /usr/local/bin/sshpanel.sh || true
        chmod +x /usr/local/bin/sshpanel.sh || true
        if ! grep -q "alias sshpanel=" ~/.bashrc 2>/dev/null; then echo "alias sshpanel='sudo /usr/local/bin/sshpanel.sh'" >> ~/.bashrc; fi
        info "SSH Panel instalado. Ejecuta: sshpanel"
        pause
        ;;
      7) monitoreo_menu ;;
      8) backup_menu ;;
      9) ssl_menu ;;
      10) seguridad_menu ;;
      11) limpieza_menu ;;
      12) xray_menu ;;
      13) udp_menu ;;
      14)
        echo -e "\n  ${CYAN}🔄 Actualizando panel...${NC}"
        curl -fsSL "$BASE_URL/menu.sh" -o /tmp/menu_update.sh
        if [[ -f /tmp/menu_update.sh ]]; then
          chmod +x /tmp/menu_update.sh
          mv /tmp/menu_update.sh /usr/local/bin/menu
          info "✅ Panel actualizado"
        else
          warn "Error al actualizar"
        fi
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
