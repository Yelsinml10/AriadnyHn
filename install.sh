#!/bin/bash

# =============================================
# PANEL MAESTRO VPN - INSTALADOR Y ADMINISTRADOR
# =============================================

# (Eliminadas las reglas estrictas 'set -e' para evitar cierres repentinos)

# =============================================
# 1. VARIABLES GLOBALES Y COLORES
# =============================================
RED='\033[0;31m'
L_RED='\033[1;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

TITLE="PANEL VPN COMPLETO 🚀"
TOKEN="${TOKEN:-}"
BASE_URL="https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main"

# =============================================
# 2. FUNCIONES DE SISTEMA Y UTILIDADES
# =============================================
info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

pause() {
  echo -e "\n${CYAN}Presiona ENTER para continuar...${NC}"
  read -r
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[✗] Ejecuta como root: sudo bash $0${NC}"
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
  echo -e "\n${CYAN}Descargando $script_name...${NC}"
  if curl -fsSL "$BASE_URL/$script_name" > "$script_name"; then
    chmod +x "$script_name"
    echo -e "${GREEN}Ejecutando $script_name...${NC}"
    "./$script_name"
    rm -f "$script_name"
    echo -e "\n${GREEN}Operación finalizada.${NC}"
    pause
  else
    echo -e "${RED}[✗] Error al descargar $script_name.${NC}"
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

display_header_main() {
  get_vps_info
  clear
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo -e "           ${WHITE}${TITLE}${NC}"
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo -e "${CYAN} OS  :${NC} ${GREEN}${VPS_OS}${NC}"
  echo -e "${CYAN} IP  :${NC} ${GREEN}${VPS_IP}${NC}"
  echo -e "${CYAN} RAM :${NC} ${GREEN}${VPS_RAM}${NC}"
  echo -e "${CYAN} CPU :${NC} ${GREEN}${VPS_CPU} (Load)${NC}"
  echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
  echo ""
}

# =============================================
# 3. MÓDULO: CADDY SERVER (ADMINISTRACIÓN COMPLETA)
# =============================================
caddy_menu() {
  CADDY_CONF="/etc/caddy/Caddyfile"
  while true; do
    if systemctl is-active --quiet caddy; then CADDY_STATUS="${GREEN}● SERVICIO: ACTIVO${NC}"; else CADDY_STATUS="${RED}● SERVICIO: INACTIVO${NC}"; fi
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

    clear
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "           ${WHITE}ADMINISTRADOR CADDY SERVER${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${CYAN} DOMINIO  :${NC} ${GREEN}${DOMINIO_ACTUAL}${NC}"
    echo -e "${CYAN} HTTP     :${NC} ${GREEN}${PUERTOS_HTTP}${NC}"
    echo -e "${CYAN} HTTPS    :${NC} ${GREEN}${PUERTOS_HTTPS}${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e " ${CADDY_STATUS}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}[1] > ${GREEN}ESTADO DEL SERVICIO${NC}"
    echo -e "${CYAN}[2] > ${GREEN}CAMBIAR DOMINIO ACTUAL${NC}"
    echo -e "${CYAN}[3] > ${GREEN}CAMBIAR PUERTOS HTTP${NC}"
    echo -e "${CYAN}[4] > ${GREEN}CAMBIAR PUERTOS HTTPS${NC}"
    echo -e "${CYAN}[5] > ${GREEN}VER LOGS EN TIEMPO REAL${NC}"
    echo -e "${CYAN}[6] > ${GREEN}REINICIAR CADDY${NC}"
    echo -e "${CYAN}[7] > ${RED}DESINSTALAR CADDY${NC}"
    echo -e "\n${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}[0] VOLVER AL MENÚ PRINCIPAL${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -en "\n${GREEN}Ingresa una Opcion: ${NC}"
    read -r opt_caddy

    case "$opt_caddy" in
      1) clear; systemctl status caddy --no-pager || true; pause ;;
      2) 
        echo -e "\n${YELLOW}Dominio actual: ${WHITE}$DOMINIO_ACTUAL${NC}"
        read -r -p "➜ Ingresa el NUEVO dominio para Caddy: " NUEVO_DOMINIO
        if [[ -n "$NUEVO_DOMINIO" && "$DOMINIO_ACTUAL" != "No detectado" && -f "$CADDY_CONF" ]]; then
            sed -i "s/$DOMINIO_ACTUAL/$NUEVO_DOMINIO/g" "$CADDY_CONF" 2>/dev/null || true
            systemctl restart caddy 2>/dev/null || true
            echo -e "${GREEN}[✓] Dominio actualizado exitosamente a: $NUEVO_DOMINIO${NC}"
        fi
        pause ;;
      3) 
        echo -e "\n${YELLOW}=== CAMBIAR PUERTOS HTTP DE CADDY ===${NC}"
        echo -e "${CYAN}Introduce los nuevos puertos HTTP separados por comas (Ej: 80, 8880, 2052)${NC}"
        read -r -p "➜ Nuevos puertos HTTP: " NUEVOS_HTTP
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
                echo -e "${GREEN}[✓] Puertos HTTP actualizados correctamente.${NC}"
            else
                echo -e "${RED}[✗] Formato de puertos HTTP inválido.${NC}"
            fi
        fi
        pause ;;
      4) 
        echo -e "\n${YELLOW}=== CAMBIAR PUERTOS HTTPS DE CADDY ===${NC}"
        echo -e "${CYAN}Introduce la nueva lista de puertos separados por comas (Ej: 443, 8443, 2053)${NC}"
        read -r -p "➜ Nuevos puertos HTTPS: " NUEVOS_PUERTOS
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
                echo -e "${GREEN}[✓] Puertos HTTPS actualizados correctamente.${NC}"
            else
                echo -e "${RED}[✗] Formato de puertos HTTPS inválido.${NC}"
            fi
        fi
        pause ;;
      5) clear; journalctl -u caddy -f || true; pause ;;
      6) systemctl restart caddy || true; echo -e "${GREEN}[✓] Caddy reiniciado.${NC}"; sleep 1 ;;
      7) 
        echo -e "\n${RED}⚠️ ¿Estás seguro de desinstalar Caddy por completo? (s/N)${NC}"
        read -r -p "➜ " conf_caddy
        if [[ "$conf_caddy" =~ ^[sS]$ ]]; then
          systemctl stop caddy 2>/dev/null || true
          systemctl disable caddy 2>/dev/null || true
          apt-get purge -y caddy 2>/dev/null || true
          rm -rf /etc/caddy 2>/dev/null || true
          echo -e "${GREEN}[✓] Caddy desinstalado por completo.${NC}"
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
  if ! command -v jq >/dev/null 2>&1; then apt-get install -y jq -qq || true; fi
  V2RAY_CONF="/usr/local/etc/v2ray/config.json"
  
  while true; do
    if systemctl is-active --quiet v2ray; then V2RAY_STATUS="${GREEN}● SERVICIO: ACTIVO${NC}"; else V2RAY_STATUS="${RED}● SERVICIO: INACTIVO${NC}"; fi
    V2RAY_PORT=$(jq -r '.inbounds[0].port' "$V2RAY_CONF" 2>/dev/null || echo "N/A")
    V2RAY_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$V2RAY_CONF" 2>/dev/null || echo "N/A")
    V2RAY_USERS=$(jq '.inbounds[0].settings.clients | length' "$V2RAY_CONF" 2>/dev/null || echo "0")

    clear
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "           ${WHITE}ADMINISTRADOR V2RAY (VMESS)${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${CYAN} PUERTO   :${NC} ${GREEN}${V2RAY_PORT} (Local)${NC}"
    echo -e "${CYAN} PATH     :${NC} ${GREEN}${V2RAY_PATH}${NC}"
    echo -e "${CYAN} USUARIOS :${NC} ${GREEN}${V2RAY_USERS} Activos${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e " ${V2RAY_STATUS}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}[1] > ${GREEN}LISTAR USUARIOS (UUIDs)${NC}"
    echo -e "${CYAN}[2] > ${GREEN}AÑADIR NUEVO USUARIO${NC}"
    echo -e "${CYAN}[3] > ${GREEN}ELIMINAR USUARIO${NC}"
    echo -e "${CYAN}[4] > ${GREEN}CAMBIAR PUERTO${NC}"
    echo -e "${CYAN}[5] > ${GREEN}CAMBIAR PATH (Ruta Websocket)${NC}"
    echo -e "${CYAN}[6] > ${GREEN}VER LOGS EN TIEMPO REAL${NC}"
    echo -e "${CYAN}[7] > ${GREEN}REINICIAR V2RAY${NC}"
    echo -e "${CYAN}[8] > ${RED}DESINSTALAR V2RAY${NC}"
    echo -e "\n${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}[0] VOLVER AL MENÚ PRINCIPAL${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -en "\n${GREEN}Ingresa una Opcion: ${NC}"
    read -r opt_v2ray

    case "$opt_v2ray" in
      1) echo -e "\n${YELLOW}=== USUARIOS ===${NC}"; jq -r '.inbounds[0].settings.clients | to_entries[] | "[\(.key)] UUID: \(.value.id)"' "$V2RAY_CONF" 2>/dev/null || true; pause ;;
      2) 
        NUEVO_UUID=$(cat /proc/sys/kernel/random/uuid)
        jq --arg uuid "$NUEVO_UUID" '.inbounds[0].settings.clients += [{"id": $uuid, "alterId": 0}]' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
        systemctl restart v2ray || true
        echo -e "${GREEN}[✓] Añadido: $NUEVO_UUID${NC}"; pause ;;
      3) 
        jq -r '.inbounds[0].settings.clients | to_entries[] | "[\(.key)] \(.value.id)"' "$V2RAY_CONF" 2>/dev/null || true
        read -r -p "Ingresa el número [#] a eliminar (q para salir): " IDX
        if [[ "$IDX" =~ ^[0-9]+$ ]]; then
          jq "del(.inbounds[0].settings.clients[$IDX])" "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          echo -e "${GREEN}[✓] Eliminado.${NC}"
        fi
        pause ;;
      4) 
        echo -e "\n${YELLOW}Puerto actual: ${WHITE}$V2RAY_PORT${NC}"
        read -r -p "➜ Ingresa el nuevo puerto: " NUEVO_PUE
        if [[ "$NUEVO_PUE" =~ ^[0-9]+$ ]]; then
          jq --argjson p "$NUEVO_PUE" '.inbounds[0].port = $p' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          echo -e "${GREEN}[✓] Puerto cambiado a $NUEVO_PUE exitosamente.${NC}"
        else
          echo -e "${RED}[✗] Puerto inválido.${NC}"
        fi
        pause ;;
      5) 
        echo -e "\n${YELLOW}Path actual: ${WHITE}$V2RAY_PATH${NC}"
        read -r -p "➜ Ingresa el nuevo path (Ej: /v2ray o /): " NUEVO_PATH
        if [[ -n "$NUEVO_PATH" ]]; then
          jq --arg path "$NUEVO_PATH" '.inbounds[0].streamSettings.wsSettings.path = $path' "$V2RAY_CONF" > /tmp/v2.json 2>/dev/null && mv /tmp/v2.json "$V2RAY_CONF" 2>/dev/null || true
          systemctl restart v2ray || true
          echo -e "${GREEN}[✓] Path cambiado a $NUEVO_PATH exitosamente.${NC}"
        else
          echo -e "${RED}[✗] Path no válido.${NC}"
        fi
        pause ;;
      6) clear; journalctl -u v2ray -f || true; pause ;;
      7) systemctl restart v2ray || true; echo -e "${GREEN}[✓] V2Ray reiniciado.${NC}"; sleep 1 ;;
      8) 
        echo -e "\n${RED}⚠️ ¿Estás seguro de desinstalar V2Ray por completo? (s/N)${NC}"
        read -r -p "➜ " conf_v2
        if [[ "$conf_v2" =~ ^[sS]$ ]]; then
          systemctl stop v2ray 2>/dev/null || true
          systemctl disable v2ray 2>/dev/null || true
          rm -rf /usr/local/etc/v2ray /usr/local/share/v2ray /var/log/v2ray /etc/systemd/system/v2ray.service 2>/dev/null || true
          systemctl daemon-reload 2>/dev/null || true
          echo -e "${GREEN}[✓] V2Ray desinstalado por completo.${NC}"
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
  while true; do
    if systemctl is-active --quiet "$PROXY_SVC"; then PROXY_STATUS="${GREEN}● SERVICIO: ACTIVO${NC}"; else PROXY_STATUS="${RED}● SERVICIO: INACTIVO${NC}"; fi
    if [[ -f "$PROXY_DIR/main.go" ]]; then
      PUERTOS_ACTUALES=$(grep -E 'puertos\s*:=\s*\[\]int' "$PROXY_DIR/main.go" 2>/dev/null | grep -o '{[^}]*}' | tr -d '{} ' || echo "8080")
      [[ -z "$PUERTOS_ACTUALES" ]] && PUERTOS_ACTUALES="8080"
    else
      PUERTOS_ACTUALES="No instalado"
    fi

    clear
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "           ${WHITE}ADMINISTRADOR SSH-GO PROXY${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${CYAN} PUERTOS  :${NC} ${GREEN}${PUERTOS_ACTUALES}${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e " ${PROXY_STATUS}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}[1] > ${GREEN}AGREGAR / QUITAR / CAMBIAR PUERTOS${NC}"
    echo -e "${CYAN}[2] > ${GREEN}PRUEBA DE CONEXIÓN (Test HTTP/SSH)${NC}"
    echo -e "${CYAN}[3] > ${GREEN}VER LOGS EN TIEMPO REAL${NC}"
    echo -e "${CYAN}[4] > ${GREEN}REINICIAR PROXY${NC}"
    echo -e "${CYAN}[5] > ${RED}DESINSTALAR SSH-GO PROXY${NC}"
    echo -e "\n${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}[0] VOLVER AL MENÚ PRINCIPAL${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -en "\n${GREEN}Ingresa una Opcion: ${NC}"
    read -r opt_sshgo

    case "$opt_sshgo" in
      1) 
        echo -e "\n${YELLOW}=== GESTIÓN DE PUERTOS SSH-GO ===${NC}"
        echo -e "Puertos actuales: ${WHITE}$PUERTOS_ACTUALES${NC}"
        read -r -p "➜ Ingresa los nuevos puertos separados por comas (Ej: 8080, 80, 443): " NUEVOS_PUERTOS
        if [[ -n "$NUEVOS_PUERTOS" && -f "$PROXY_DIR/main.go" ]]; then
            FORMATTED_ARRAY=""
            IFS=',' read -ra ADDR <<< "$NUEVOS_PUERTOS"
            for i in "${ADDR[@]}"; do
                clean_p=$(echo "$i" | xargs)
                if [[ "$clean_p" =~ ^[0-9]+$ ]]; then
                    if [[ -z "$FORMATTED_ARRAY" ]]; then
                        FORMATTED_ARRAY="$clean_p"
                    else
                        FORMATTED_ARRAY="${FORMATTED_ARRAY}, $clean_p"
                    fi
                fi
            done
            if [[ -n "$FORMATTED_ARRAY" ]]; then
                echo -e "${BLUE}Actualizando código fuente y recompilando binario...${NC}"
                sed -i -E "s/puertos\s*:=\s*\[\]int\{[^}]+\}/puertos := []int{$FORMATTED_ARRAY}/g" "$PROXY_DIR/main.go" 2>/dev/null
                cd "$PROXY_DIR"
                export PATH=$PATH:/usr/local/go/bin
                go build -ldflags="-s -w" -o vpn-proxy main.go 2>/dev/null
                chmod +x vpn-proxy
                systemctl restart "$PROXY_SVC" 2>/dev/null || true
                echo -e "${GREEN}[✓] Puertos actualizados y binario recompilado.${NC}"
            else
                echo -e "${RED}[✗] Puertos no válidos.${NC}"
            fi
        fi
        pause ;;
      2) 
        RESP=$(curl -s -i -H 'X-Real-Host: 127.0.0.1:22' http://localhost:8080 2>/dev/null | head -n 1 || echo "Error")
        echo -e "\n${WHITE}Respuesta local: $RESP${NC}"; pause ;;
      3) clear; journalctl -u "$PROXY_SVC" -f || true; pause ;;
      4) systemctl restart "$PROXY_SVC" || true; echo -e "${GREEN}[✓] Proxy reiniciado.${NC}"; sleep 1 ;;
      5) 
        echo -e "\n${RED}⚠️ ¿Estás seguro de desinstalar SSH-Go Proxy? (s/N)${NC}"
        read -r -p "➜ " conf_s
        if [[ "$conf_s" =~ ^[sS]$ ]]; then
          systemctl stop "$PROXY_SVC" 2>/dev/null || true
          systemctl disable "$PROXY_SVC" 2>/dev/null || true
          rm -f "/etc/systemd/system/${PROXY_SVC}.service" 2>/dev/null
          systemctl daemon-reload 2>/dev/null || true
          rm -rf "$PROXY_DIR" 2>/dev/null
          echo -e "${GREEN}[✓] SSH-Go desinstalado.${NC}"
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
  while true; do
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then FW_STATUS="${GREEN}● SERVICIO: ACTIVO (Filtrando)${NC}"; else FW_STATUS="${RED}● SERVICIO: INACTIVO (Abierto)${NC}"; fi
    clear
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "           ${WHITE}ADMINISTRADOR DE FIREWALL${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e " ${FW_STATUS}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}[1] > ${GREEN}VER ESTADO Y REGLAS (UFW)${NC}"
    echo -e "${CYAN}[2] > ${GREEN}ABRIR TODOS LOS PUERTOS (TCP/UDP)${NC} ${YELLOW}[RECOMENDADO]${NC}"
    echo -e "${CYAN}[3] > ${GREEN}CONFIGURACIÓN SEGURA (22, 80, 443)${NC}"
    echo -e "${CYAN}[4] > ${GREEN}DESACTIVAR FIREWALL POR COMPLETO${NC}"
    echo -e "\n${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}[0] VOLVER AL MENÚ PRINCIPAL${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo -en "\n${GREEN}Ingresa una Opcion: ${NC}"
    read -r opt_fw

    case "$opt_fw" in
      1) clear; ufw status verbose || echo "UFW no está instalado."; pause ;;
      2) ufw --force disable >/dev/null 2>&1 || true; echo -e "${GREEN}[✓] Todos los puertos abiertos.${NC}"; pause ;;
      3) 
        if ! command -v ufw >/dev/null 2>&1; then apt-get install -y ufw || true; fi
        ufw allow 22/tcp >/dev/null 2>&1 || true
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || true
        echo -e "${GREEN}[✓] Configuración Segura Activada.${NC}"; pause ;;
      4) ufw --force disable >/dev/null 2>&1 || true; echo -e "${YELLOW}[!] Firewall desactivado.${NC}"; pause ;;
      0) break ;;
    esac
  done
}

# =============================================
# 7. MENÚ PRINCIPAL
# =============================================
main_menu() {
  while true; do
    display_header_main

    echo -e "${CYAN}[1] > ${GREEN}Caddy Server (Instalar/Administrar)${NC}"
    echo -e "${CYAN}[2] > ${GREEN}V2Ray VMess (Instalar/Administrar)${NC}"
    echo -e "${CYAN}[3] > ${GREEN}SSH-Go Proxy (Instalar/Administrar)${NC}"
    echo -e "${CYAN}[4] > ${GREEN}Instalar todo de una vez${NC}"
    echo -e "${CYAN}[5] > ${GREEN}Firewall UFW (Administrador)${NC}"
    echo -e "${CYAN}[6] > ${GREEN}SSH Panel (Gestión de usuarios)${NC}"
    echo -e "\n${L_RED}──────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}[0] SALIR DEL PANEL${NC}"
    echo -e "${L_RED}──────────────────────────────────────────────────${NC}"
    echo ""

    echo -en "${GREEN}Ingresa una Opcion: ${NC}"
    read -r option

    case "$option" in
      1) 
        if command -v caddy >/dev/null 2>&1; then caddy_menu; else 
          download_and_execute "install-caddy.sh"
        fi ;;
      2) 
        if command -v v2ray >/dev/null 2>&1; then v2ray_menu; else 
          download_and_execute "install-v2ray.sh"
        fi ;;
      3) 
        if [[ -f /opt/vpn-proxy/vpn-proxy ]]; then sshgo_menu; else 
          download_and_execute "install-sshgo.sh"
        fi ;;
      4)
        echo -e "\n${BLUE}Instalando todos los servicios...${NC}"
        download_and_execute "install-caddy.sh"
        download_and_execute "install-v2ray.sh"
        download_and_execute "install-sshgo.sh"
        ;;
      5) firewall_menu ;;
      6) 
        echo -e "\n${YELLOW}📥 Instalando SSH Panel...${NC}"
        mkdir -p /usr/local/bin || true
        curl -fsSL "https://raw.githubusercontent.com/Yelsinml10/AriadnyHn/main/sshpanel.sh" -o /usr/local/bin/sshpanel.sh || true
        chmod +x /usr/local/bin/sshpanel.sh || true
        if ! grep -q "alias sshpanel=" ~/.bashrc 2>/dev/null; then echo "alias sshpanel='sudo /usr/local/bin/sshpanel.sh'" >> ~/.bashrc; fi
        echo -e "${GREEN}✅ SSH Panel instalado. Ejecuta: sshpanel${NC}"
        pause
        ;;
      0) clear; exit 0 ;;
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
