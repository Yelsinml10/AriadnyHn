#!/bin/bash

# =========================================================
#  AUTONINSTALADOR VPN PROXY SSH-GO + PANEL ADMINISTRATIVO
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

BG_BLUE='\033[44m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

# Verificar root
[[ $EUID -ne 0 ]] && error "Ejecutar como root: sudo bash $0"

clear
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC} ${BG_BLUE}${WHITE}${BOLD}   🚀 AUTOINSTALADOR PROXY SSH-GO + PANEL PREMIUM 🚀      ${NC} ${CYAN}│${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"

# =============================================
# 1. Instalar Go y dependencias
# =============================================
step "Verificando/Instalando Go y dependencias..."

apt update -qq
apt install -y -qq wget tar gcc make curl net-tools jq > /dev/null 2>&1

if ! command -v go &>/dev/null; then
    GO_VERSION="1.21.5"
    cd /usr/local
    
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        GO_ARCH="arm64"
    else
        GO_ARCH="amd64"
    fi
    
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O go.tar.gz
    tar -xzf go.tar.gz
    rm go.tar.gz
    
    cat > /etc/profile.d/go.sh << 'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF
    
    export PATH=$PATH:/usr/local/go/bin
    info "Go instalado: $(go version)"
else
    info "Go ya instalado: $(go version)"
fi

# =============================================
# 2. Captura Interactiva de Parámetros
# =============================================
echo -e "\n${RED}======================================================${NC}"
echo -e "${RED}${BOLD}   SOCKS DIRECTO-PY  |  CUSTOM (GO ENGINE)${NC}"
echo -e "${RED}======================================================${NC}\n"

read -p "$(echo -e "${WHITE}${BOLD}ESCRIBE SU PUERTO: ${NC}")" LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}

read -p "$(echo -e "\n${WHITE}${BOLD}Digite Un Puerto SSH/DROPBEAR activo [22]: ${NC}")" SSH_PORT
SSH_PORT=${SSH_PORT:-22}

read -p "$(echo -e "\n${WHITE}${BOLD}Escribe El HTTP Response? 101|200|300 [101]: ${NC}")" HTTP_CODE
HTTP_CODE=${HTTP_CODE:-101}

step "Verificando disponibilidad del puerto $LISTEN_PORT..."
if ss -tlnp | grep -q ":$LISTEN_PORT "; then
    error "El puerto $LISTEN_PORT ya está en uso. Libéralo o elige otro."
fi
info "El puerto $LISTEN_PORT está libre"

# =============================================
# 3. Crear proyecto Go y archivo de configuración
# =============================================
step "Creando estructura de archivos..."

mkdir -p /opt/vpn-proxy
cd /opt/vpn-proxy

cat > /opt/vpn-proxy/config.json << EOF
{
    "ports": [$LISTEN_PORT],
    "ssh_port": $SSH_PORT,
    "http_code": "$HTTP_CODE"
}
EOF

rm -f go.mod go.sum
go mod init vpn-proxy 2>/dev/null

cat > main.go << 'GOMAIN'
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"
)

const BUFLEN = 4096 * 4

type Config struct {
	Ports    []int  `json:"ports"`
	SSHPort  int    `json:"ssh_port"`
	HTTPCode string `json:"http_code"`
}

func loadConfig() Config {
	cfg := Config{Ports: []int{8080}, SSHPort: 22, HTTPCode: "101"}
	file, err := os.Open("/opt/vpn-proxy/config.json")
	if err == nil {
		defer file.Close()
		json.NewDecoder(file).Decode(&cfg)
	}
	return cfg
}

func buildResponse(code string) []byte {
	switch strings.TrimSpace(code) {
	case "101":
		return []byte("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
	case "200":
		return []byte("HTTP/1.1 200 Connection Established\r\n\r\n")
	case "200-WS":
		return []byte("HTTP/1.1 200 OK\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
	case "300":
		return []byte("HTTP/1.1 300 Multiple Choices\r\n\r\n")
	default:
		return []byte("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
	}
}

func main() {
	cfg := loadConfig()
	defaultHost := fmt.Sprintf("0.0.0.0:%d", cfg.SSHPort)
	response := buildResponse(cfg.HTTPCode)

	for _, p := range cfg.Ports {
		go func(port int) {
			listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", port))
			if err != nil {
				return
			}
			for {
				client, err := listener.Accept()
				if err != nil {
					continue
				}
				go handleConnection(client, defaultHost, response)
			}
		}(p)
	}
	select {}
}

func handleConnection(client net.Conn, defaultHost string, response []byte) {
	defer client.Close()

	client.SetReadDeadline(time.Now().Add(15 * time.Second))

	buf := make([]byte, BUFLEN)
	n, err := client.Read(buf)
	if err != nil {
		return
	}

	clientBuffer := string(buf[:n])
	targetHost := findHeader(clientBuffer, "X-Real-Host")
	if targetHost == "" {
		targetHost = defaultHost
	}

	target, err := net.DialTimeout("tcp", targetHost, 10*time.Second)
	if err != nil {
		target, err = net.DialTimeout("tcp", defaultHost, 10*time.Second)
		if err != nil {
			return
		}
	}
	defer target.Close()

	client.Write(response)
	client.SetReadDeadline(time.Time{})

	done := make(chan struct{})
	go func() {
		io.Copy(target, client)
		done <- struct{}{}
	}()
	go func() {
		io.Copy(client, target)
		done <- struct{}{}
	}()
	<-done
}

func findHeader(head, header string) string {
	key := header + ": "
	idx := strings.Index(head, key)
	if idx == -1 {
		return ""
	}
	start := idx + len(key)
	end := strings.Index(head[start:], "\r\n")
	if end == -1 {
		return ""
	}
	return head[start : start+end]
}
GOMAIN

# =============================================
# 4. Compilar binario en Go
# =============================================
step "Compilando binario de SSH-Go..."

go mod tidy
go build -ldflags="-s -w" -o vpn-proxy main.go
chmod +x vpn-proxy

if [ ! -f vpn-proxy ]; then
    error "Error: No se pudo compilar el proxy en Go"
fi

info "Proxy compilado exitosamente"

# =============================================
# 5. Crear Servicio Systemd con Persistencia
# =============================================
step "Configurando servicio systemd..."

systemctl stop vpn-proxy 2>/dev/null

cat > /etc/systemd/system/vpn-proxy.service << 'EOF'
[Unit]
Description=VPN Proxy SSH-Go Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vpn-proxy
ExecStart=/opt/vpn-proxy/vpn-proxy
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=3
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn-proxy > /dev/null 2>&1
systemctl restart vpn-proxy

# =============================================
# 6. Crear Panel Administrativo Visual
# =============================================
step "Creando interfaz del Panel Administrativo..."

cat > /usr/local/bin/proxy << 'EOF'
#!/bin/bash

# Colores
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_PURPLE='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;90m'

BG_BLUE='\033[44m'
BG_CYAN='\033[46m'
BG_PURPLE='\033[45m'
BG_RED='\033[41m'

CONFIG_FILE="/opt/vpn-proxy/config.json"

get_ip() {
    curl -s https://api.ipify.org || hostname -I | awk '{print $1}'
}

get_status() {
    if systemctl is-active --quiet vpn-proxy; then
        echo -e "${C_GREEN}${C_BOLD}● ACTIVO (Running)${C_RESET}"
    else
        echo -e "${C_RED}${C_BOLD}● DETENIDO (Stopped)${C_RESET}"
    fi
}

get_ports() {
    jq -r '.ports | join(", ")' "$CONFIG_FILE" 2>/dev/null
}

get_ssh_port() {
    jq -r '.ssh_port' "$CONFIG_FILE" 2>/dev/null
}

get_http_code() {
    jq -r '.http_code' "$CONFIG_FILE" 2>/dev/null
}

show_header() {
    clear
    echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}     🚀 PANEL DE CONTROL - SSH-GO PROXY ENGINE 🚀        ${C_RESET} ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}├─────────────────────────────────────────────────────────────┤${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}🌐 IP Servidor   :${C_RESET} ${C_CYAN}${C_BOLD}$(get_ip)${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}⚡ Estado        :${C_RESET} $(get_status)"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}🔌 Puertos Proxy :${C_RESET} ${C_YELLOW}${C_BOLD}$(get_ports)${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}🔑 Puerto SSH    :${C_RESET} ${C_GREEN}${C_BOLD}$(get_ssh_port)${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}📡 Respuesta HTTP:${C_RESET} ${C_PURPLE}${C_BOLD}HTTP $(get_http_code)${C_RESET}"
    echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
}

add_port() {
    show_header
    echo -e "\n${C_CYAN}┌─── [ ➕ AGREGAR PUERTO PROXY ]${C_RESET}"
    read -p "$(echo -e "${C_CYAN}│${C_RESET} ${C_BOLD}${C_YELLOW}📌 Ingrese el nuevo puerto a escuchar: ${C_RESET}")" NEW_PORT
    if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -gt 0 ] && [ "$NEW_PORT" -le 65535 ]; then
        jq ".ports = (.ports + [$NEW_PORT] | unique | sort)" "$CONFIG_FILE" > /tmp/cfg.json && mv /tmp/cfg.json "$CONFIG_FILE"
        echo -e "${C_GREEN}│ ✅ Puerto $NEW_PORT agregado correctamente.${C_RESET}"
        systemctl restart vpn-proxy
        echo -e "${C_GREEN}│ ✅ Servicio reiniciado exitosamente.${C_RESET}"
    else
        echo -e "${C_RED}│ ❌ Error: Puerto inválido.${C_RESET}"
    fi
    echo -e "${C_CYAN}└───────────────────────────────────────${C_RESET}"
    read -p "Presione ENTER para continuar..."
}

remove_port() {
    show_header
    echo -e "\n${C_RED}┌─── [ ➖ QUITAR PUERTO PROXY ]${C_RESET}"
    echo -e "${C_RED}│${C_RESET} Puertos activos actuales: ${C_YELLOW}${C_BOLD}$(get_ports)${C_RESET}"
    read -p "$(echo -e "${C_RED}│${C_RESET} ${C_BOLD}${C_YELLOW}📌 Ingrese el puerto a eliminar: ${C_RESET}")" DEL_PORT
    if [[ "$DEL_PORT" =~ ^[0-9]+$ ]]; then
        COUNT=$(jq '.ports | length' "$CONFIG_FILE")
        if [ "$COUNT" -le 1 ]; then
            echo -e "${C_RED}│ ❌ No se puede borrar. Debe mantener al menos 1 puerto activo.${C_RESET}"
        else
            jq ".ports = (.ports - [$DEL_PORT])" "$CONFIG_FILE" > /tmp/cfg.json && mv /tmp/cfg.json "$CONFIG_FILE"
            echo -e "${C_GREEN}│ ✅ Puerto $DEL_PORT eliminado correctamente.${C_RESET}"
            systemctl restart vpn-proxy
            echo -e "${C_GREEN}│ ✅ Servicio reiniciado exitosamente.${C_RESET}"
        fi
    else
        echo -e "${C_RED}│ ❌ Error: Puerto inválido.${C_RESET}"
    fi
    echo -e "${C_RED}└───────────────────────────────────────${C_RESET}"
    read -p "Presione ENTER para continuar..."
}

change_ssh_port() {
    show_header
    echo -e "\n${C_GREEN}┌─── [ 🔑 CAMBIAR PUERTO SSH DESTINO ]${C_RESET}"
    read -p "$(echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}${C_YELLOW}📌 Ingrese el nuevo puerto SSH local (ej: 22): ${C_RESET}")" SSH_P
    if [[ "$SSH_P" =~ ^[0-9]+$ ]] && [ "$SSH_P" -gt 0 ] && [ "$SSH_P" -le 65535 ]; then
        jq ".ssh_port = $SSH_P" "$CONFIG_FILE" > /tmp/cfg.json && mv /tmp/cfg.json "$CONFIG_FILE"
        echo -e "${C_GREEN}│ ✅ Puerto SSH local cambiado a $SSH_P.${C_RESET}"
        systemctl restart vpn-proxy
        echo -e "${C_GREEN}│ ✅ Servicio reiniciado exitosamente.${C_RESET}"
    else
        echo -e "${C_RED}│ ❌ Error: Puerto SSH inválido.${C_RESET}"
    fi
    echo -e "${C_GREEN}└───────────────────────────────────────${C_RESET}"
    read -p "Presione ENTER para continuar..."
}

change_http_code() {
    show_header
    echo -e "\n${C_PURPLE}┌─── [ 🌐 SELECCIONAR CÓDIGO RESPUESTA HTTP ]${C_RESET}"
    echo -e "${C_PURPLE}│${C_RESET}  ${C_CYAN}[1]${C_RESET} ${C_BOLD}HTTP 101${C_RESET}  ➜ Switching Protocols (Recomendado WebSocket)"
    echo -e "${C_PURPLE}│${C_RESET}  ${C_GREEN}[2]${C_RESET} ${C_BOLD}HTTP 200${C_RESET}  ➜ Connection Established (Estándar Directo)"
    echo -e "${C_PURPLE}│${C_RESET}  ${C_YELLOW}[3]${C_RESET} ${C_BOLD}HTTP 200-WS${C_RESET}➜ 200 OK con Upgrade WebSocket"
    echo -e "${C_PURPLE}│${C_RESET}  ${C_RED}[4]${C_RESET} ${C_BOLD}HTTP 300${C_RESET}  ➜ Multiple Choices"
    echo -e "${C_PURPLE}│${C_RESET}"
    read -p "$(echo -e "${C_PURPLE}└───❯${C_RESET} ${C_BOLD}${C_YELLOW}Seleccione una opción [1-4]: ${C_RESET}")" CODE_OPT
    case $CODE_OPT in
        1) HCODE="101" ;;
        2) HCODE="200" ;;
        3) HCODE="200-WS" ;;
        4) HCODE="300" ;;
        *) echo -e "${C_RED}❌ Opción inválida.${C_RESET}"; sleep 1; return ;;
    esac

    jq ".http_code = \"$HCODE\"" "$CONFIG_FILE" > /tmp/cfg.json && mv /tmp/cfg.json "$CONFIG_FILE"
    echo -e "${C_GREEN}✅ Respuesta HTTP cambiada a $HCODE con éxito.${C_RESET}"
    systemctl restart vpn-proxy
    read -p "Presione ENTER para continuar..."
}

restart_service() {
    echo -e "\n${C_YELLOW}🔄 Reiniciando servicio Proxy...${C_RESET}"
    systemctl restart vpn-proxy
    sleep 1.2
    echo -e "${C_GREEN}✅ Servicio reiniciado correctamente.${C_RESET}"
    sleep 1
}

toggle_service() {
    if systemctl is-active --quiet vpn-proxy; then
        systemctl stop vpn-proxy
        echo -e "\n${C_RED}⛔ Servicio proxy detenido.${C_RESET}"
    else
        systemctl start vpn-proxy
        echo -e "\n${C_GREEN}▶️ Servicio proxy iniciado.${C_RESET}"
    fi
    sleep 1.2
}

view_logs() {
    clear
    echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET} ${BG_CYAN}${C_WHITE}${C_BOLD}       📋 MONITOR DE LOGS EN TIEMPO REAL (Ctrl+C salir)     ${C_RESET} ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}\n"
    journalctl -u vpn-proxy -f -n 50
}

uninstall_proxy() {
    show_header
    echo -e "\n${C_RED}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_RED}│${C_RESET} ${BG_RED}${C_WHITE}${C_BOLD}           ⚠️  DESINSTALACIÓN COMPLETA DEL PROXY  ⚠️          ${C_RESET} ${C_RED}│${C_RESET}"
    echo -e "${C_RED}└─────────────────────────────────────────────────────────────┘${C_RESET}"
    read -p "$(echo -e "\n${C_BOLD}${C_RED}❓ ¿Desea eliminar por completo SSH-Go Proxy? (s/N): ${C_RESET}")" CONFIRM
    if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
        echo -e "\n${C_YELLOW}🛑 Deteniendo y eliminando servicio...${C_RESET}"
        systemctl stop vpn-proxy > /dev/null 2>&1
        systemctl disable vpn-proxy > /dev/null 2>&1
        rm -f /etc/systemd/system/vpn-proxy.service
        systemctl daemon-reload

        echo -e "${C_YELLOW}🗑️ Borrando archivos e interfaz...${C_RESET}"
        rm -rf /opt/vpn-proxy
        rm -f /usr/local/bin/proxy
        rm -f /usr/local/bin/sshgo
        rm -f /usr/local/bin/python
        rm -f /usr/local/bin/menu

        echo -e "\n${C_GREEN}✅ Desinstalación terminada correctamente. ¡Hasta pronto!${C_RESET}\n"
        exit 0
    else
        echo -e "${C_YELLOW}Operación cancelada.${C_RESET}"
        read -p "Presione ENTER para continuar..."
    fi
}

main_menu() {
    while true; do
        show_header
        echo -e "${C_PURPLE}${C_BOLD}┌─── [ 🛠️ CONFIGURACIÓN DE PUERTOS Y PROTOCOLO ]${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET}  ${C_GREEN}[1]${C_RESET} ${C_BOLD}➕ Agregar Puerto Proxy${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET}  ${C_RED}[2]${C_RESET} ${C_BOLD}➖ Quitar Puerto Proxy${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET}  ${C_CYAN}[3]${C_RESET} ${C_BOLD}🔑 Cambiar Puerto SSH Destino${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET}  ${C_YELLOW}[4]${C_RESET} ${C_BOLD}🌐 Cambiar Código HTTP Response${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET}"
        echo -e "${C_BLUE}${C_BOLD}├─── [ ⚡ CONTROL Y MANTENIMIENTO DEL SERVICIO ]${C_RESET}"
        echo -e "${C_BLUE}│${C_RESET}  ${C_YELLOW}[5]${C_RESET} ${C_BOLD}🔄 Reiniciar Servicio Proxy${C_RESET}"
        echo -e "${C_BLUE}│${C_RESET}  ${C_GREEN}[6]${C_RESET} ${C_BOLD}⏯️  Iniciar / Detener Servicio${C_RESET}"
        echo -e "${C_BLUE}│${C_RESET}  ${C_CYAN}[7]${C_RESET} ${C_BOLD}📋 Ver Logs en Tiempo Real${C_RESET}"
        echo -e "${C_BLUE}│${C_RESET}"
        echo -e "${C_RED}${C_BOLD}└─── [ ❌ OTROS ]${C_RESET}"
        echo -e "${C_RED}   [8]${C_RESET} ${C_BOLD}${C_RED}🗑️  Desinstalar Proxy Completamente${C_RESET}"
        echo -e "${C_WHITE}   [0]${C_RESET} ${C_BOLD}🚪 Salir del Panel${C_RESET}"
        
        echo -e "\n${C_GRAY}─────────────────────────────────────────────────────────────${C_RESET}"
        read -p "$(echo -e "${C_BOLD}${C_YELLOW} ❯ Seleccione una opción [0-8]: ${C_RESET}")" OPT
        case $OPT in
            1) add_port ;;
            2) remove_port ;;
            3) change_ssh_port ;;
            4) change_http_code ;;
            5) restart_service ;;
            6) toggle_service ;;
            7) view_logs ;;
            8) uninstall_proxy ;;
            0) clear; echo -e "\n${C_GREEN}👋 ¡Hasta pronto!${C_RESET}\n"; exit 0 ;;
            *) echo -e "${C_RED}❌ Opción no válida.${C_RESET}"; sleep 1 ;;
        esac
    done
}

main_menu
EOF

chmod +x /usr/local/bin/proxy

# 7. Crear Enlaces Simbólicos y Aliases para los comandos
ln -sf /usr/local/bin/proxy /usr/local/bin/sshgo
ln -sf /usr/local/bin/proxy /usr/local/bin/menu
ln -sf /usr/local/bin/proxy /usr/local/bin/python

echo "alias sshgo='/usr/local/bin/proxy'" >> /root/.bashrc
echo "alias proxy='/usr/local/bin/proxy'" >> /root/.bashrc
echo "alias menu='/usr/local/bin/proxy'" >> /root/.bashrc
echo "alias python='/usr/local/bin/proxy'" >> /root/.bashrc

# =============================================
# 8. Mostrar Resumen de Instalación
# =============================================
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     ✅ VPN Proxy SSH-Go + Panel Instalado! 🚀   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "📌 Puedes abrir el panel administrativo escribiendo cualquiera de estos comandos:"
echo -e "   - ${BOLD}${YELLOW}sshgo${NC}"
echo -e "   - ${BOLD}${YELLOW}proxy${NC}"
echo -e "   - ${BOLD}${YELLOW}menu${NC}"
echo -e "   - ${BOLD}${YELLOW}python${NC}\n"

read -p "$(echo -e "${BOLD}${CYAN}¿Deseas abrir el Panel Administrativo ahora? (S/n): ${NC}")" RUN_NOW
if [[ "$RUN_NOW" =~ ^[sS]$ ]] || [ -z "$RUN_NOW" ]; then
    /usr/local/bin/proxy
fi
