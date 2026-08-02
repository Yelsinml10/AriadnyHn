#!/bin/bash
# =========================================================
#  SOCKS PROXY UNIVERSAL GO (TRADUCCIÓN EXACTA 1:1 DE PYTHON)
#  CON PANEL ADMINISTRATIVO Y SOPORTE MULTI-PUERTO
# =========================================================

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_PURPLE='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
BG_BLUE='\033[44m'
BG_GREEN='\033[42m'

clear
echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}     🚀 PROXY UNIVERSAL 100% GO (ENGINE PYTHON 1:1) 🚀     ${C_RESET} ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"

if [ "$EUID" -ne 0 ]; then
  echo -e "\n${C_RED}❌ Error: Por favor ejecuta este script como usuario root.${C_RESET}\n"
  exit 1
fi

# 1. Instalar Go y dependencias
echo -e "\n${C_YELLOW}[1/4] Instalando Go y herramientas del sistema...${C_RESET}"
apt update -y && apt install -y golang-go curl wget net-tools openssh-server systemd > /dev/null 2>&1

systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null

mkdir -p /opt/vpn-proxy
CONFIG_FILE="/opt/vpn-proxy/config.json"

# 2. Configuración Interactiva
echo -e "\n${C_YELLOW}[2/4] Configuración inicial de puerto...${C_RESET}"
read -p "$(echo -e "${C_WHITE}${C_BOLD}ESCRIBE EL PUERTO A ABRIR [8080]: ${C_RESET}")" LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}

if [ ! -f "$CONFIG_FILE" ]; then
cat > "$CONFIG_FILE" << EOF
{
    "ports": [$LISTEN_PORT],
    "ssh_port": 22,
    "http_code": "101"
}
EOF
fi

# 3. Código Fuente en Go (Traducción 1:1 de proxy.py)
echo -e "\n${C_YELLOW}[3/4] Compilando binario de Go con motor optimizado...${C_RESET}"
cat > /opt/vpn-proxy/main.go << 'EOF'
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	BUFLEN      = 16384
	CONFIG_PATH = "/opt/vpn-proxy/config.json"
)

type Config struct {
	Ports        []int  `json:"ports"`
	SSHPort      int    `json:"ssh_port"`
	ResponseCode string `json:"http_code"`
}

func loadConfig() Config {
	file, err := os.ReadFile(CONFIG_PATH)
	if err != nil {
		return Config{Ports: []int{8080}, SSHPort: 22, ResponseCode: "101"}
	}
	var cfg Config
	if err := json.Unmarshal(file, &cfg); err != nil || len(cfg.Ports) == 0 {
		return Config{Ports: []int{8080}, SSHPort: 22, ResponseCode: "101"}
	}
	if cfg.SSHPort <= 0 {
		cfg.SSHPort = 22
	}
	if cfg.ResponseCode == "" {
		cfg.ResponseCode = "101"
	}
	return cfg
}

func (c *Config) save() error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(CONFIG_PATH, data, 0644)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--daemon" {
		runDaemon()
	} else {
		runPanel()
	}
}

// --- DAEMON PROXY GO (LÓGICA EXACTA DE PYTHON) ---

func runDaemon() {
	cfg := loadConfig()
	fmt.Printf("⚡ Proxy Engine SSH-Go iniciado. Puertos: %v | SSH Local: %d | Modo: HTTP %s\n", cfg.Ports, cfg.SSHPort, cfg.ResponseCode)

	for _, port := range cfg.Ports {
		go func(p int) {
			listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", p))
			if err != nil {
				fmt.Printf("❌ Error escuchando en puerto %d: %v\n", p, err)
				return
			}
			for {
				client, err := listener.Accept()
				if err != nil {
					continue
				}
				go handleConnection(client)
			}
		}(port)
	}
	select {}
}

func handleConnection(client net.Conn) {
	defer client.Close()

	cfg := loadConfig()
	sshPort := cfg.SSHPort
	if sshPort <= 0 {
		sshPort = 22
	}

	client.SetReadDeadline(time.Now().Add(15 * time.Second))

	buf := make([]byte, BUFLEN)
	n, err := client.Read(buf)
	if err != nil || n == 0 {
		return
	}

	clientBuffer := string(buf[:n])

	// 1. Parsear X-Real-Host exactamente igual a Python
	targetHostStr := findHeader(clientBuffer, "X-Real-Host")
	var targetHost string
	var targetPort int

	if targetHostStr != "" {
		if strings.Contains(targetHostStr, ":") {
			parts := strings.SplitN(targetHostStr, ":", 2)
			targetHost = parts[0]
			p, err := strconv.Atoi(parts[1])
			if err == nil && p > 0 {
				targetPort = p
			} else {
				targetPort = sshPort
			}
		} else {
			targetHost = targetHostStr
			targetPort = sshPort
		}
	} else {
		targetHost = "127.0.0.1"
		targetPort = sshPort
	}

	// 2. Conectar al host destino con fallback a 127.0.0.1:SSHPort
	targetAddr := fmt.Sprintf("%s:%d", targetHost, targetPort)
	target, err := net.DialTimeout("tcp", targetAddr, 10*time.Second)
	if err != nil {
		localAddr := fmt.Sprintf("127.0.0.1:%d", sshPort)
		target, err = net.DialTimeout("tcp", localAddr, 5*time.Second)
		if err != nil {
			return
		}
	}
	defer target.Close()

	client.SetReadDeadline(time.Time{})

	// 3. Respuesta HTTP configurable según el Panel
	var resp []byte
	switch cfg.ResponseCode {
	case "101":
		resp = []byte("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
	case "200":
		resp = []byte("HTTP/1.1 200 Connection Established\r\n\r\n")
	case "200-WS":
		resp = []byte("HTTP/1.1 200 OK\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
	case "302":
		resp = []byte("HTTP/1.1 302 Found\r\nLocation: https://google.com\r\n\r\n")
	default: // AUTO
		if strings.Contains(clientBuffer, "Upgrade: websocket") || strings.Contains(strings.ToLower(clientBuffer), "websocket") {
			resp = []byte("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
		} else {
			resp = []byte("HTTP/1.1 200 Connection Established\r\n\r\n")
		}
	}

	client.Write(resp)

	// 4. Copia bidireccional de sockets
	done := make(chan struct{}, 2)
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

func findHeader(head, headerName string) string {
	key := headerName + ": "
	idx := strings.Index(head, key)
	if idx == -1 {
		key = headerName + ":"
		idx = strings.Index(head, key)
		if idx == -1 {
			return ""
		}
	}
	start := idx + len(key)
	rest := head[start:]
	end := strings.IndexAny(rest, "\r\n")
	if end == -1 {
		return strings.TrimSpace(rest)
	}
	return strings.TrimSpace(rest[:end])
}

// --- PANEL ADMINISTRATIVO VISUAL ---

func getIP() string {
	out, err := exec.Command("curl", "-s", "--max-time", "3", "https://api.ipify.org").Output()
	if err == nil {
		ip := strings.TrimSpace(string(out))
		if ip != "" {
			return ip
		}
	}
	return "127.0.0.1"
}

func isActive() bool {
	err := exec.Command("systemctl", "is-active", "--quiet", "vpn-proxy").Run()
	return err == nil
}

func pause() {
	fmt.Print("\nPresione ENTER para continuar...")
	reader := bufio.NewReader(os.Stdin)
	reader.ReadString('\n')
}

func showHeader(cfg *Config) {
	fmt.Print("\x1B[2J\x1B[1;1H")
	fmt.Println("\x1B[1;36m┌─────────────────────────────────────────────────────────────┐\x1B[0m")
	fmt.Println("\x1B[1;36m│\x1B[0m \x1B[44m\x1B[1;37m     🚀 PANEL DE CONTROL - SOCKS PROXY UNIVERSAL 🚀     \x1B[0m \x1B[1;36m│\x1B[0m")
	fmt.Println("\x1B[1;36m├─────────────────────────────────────────────────────────────┤\x1B[0m")
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m🌐 IP Servidor   :\x1B[0m \x1B[1;36m%s\x1B[0m\n", getIP())

	statusStr := "\x1B[1;31m● DETENIDO (Stopped)\x1B[0m"
	if isActive() {
		statusStr = "\x1B[1;32m● ACTIVO (Running)\x1B[0m"
	}
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m⚡ Estado        :\x1B[0m %s\n", statusStr)
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔌 Puertos Proxy :\x1B[0m \x1B[1;33m%v\x1B[0m\n", cfg.Ports)
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔑 Puerto SSH    :\x1B[0m \x1B[1;32m%d\x1B[0m\n", cfg.SSHPort)
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m📡 Respuesta HTTP:\x1B[0m \x1B[1;35mHTTP %s\x1B[0m\n", cfg.ResponseCode)
	fmt.Println("\x1B[1;36m└─────────────────────────────────────────────────────────────┘\x1B[0m")
}

func restartService() {
	fmt.Println("\n\x1B[1;33m🔄 Reiniciando servicio Proxy...\x1B[0m")
	exec.Command("systemctl", "restart", "vpn-proxy").Run()
	time.Sleep(1 * time.Second)
	fmt.Println("\x1B[1;32m✅ Servicio reiniciado correctamente.\x1B[0m")
}

func toggleService() {
	if isActive() {
		exec.Command("systemctl", "stop", "vpn-proxy").Run()
		fmt.Println("\n\x1B[1;31m⛔ Servicio proxy detenido.\x1B[0m")
	} else {
		exec.Command("systemctl", "start", "vpn-proxy").Run()
		fmt.Println("\n\x1B[1;32m▶️ Servicio proxy iniciado.\x1B[0m")
	}
	time.Sleep(1200 * time.Millisecond)
}

func runPanel() {
	reader := bufio.NewReader(os.Stdin)

	for {
		cfg := loadConfig()
		showHeader(&cfg)

		fmt.Println("\x1B[1;35m┌─── [ 🛠️ CONFIGURACIÓN DE PUERTOS Y PROTOCOLO ]\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m  \x1B[1;32m[1]\x1B[0m \x1B[1m➕ Agregar Puerto Proxy\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m  \x1B[1;31m[2]\x1B[0m \x1B[1m➖ Quitar Puerto Proxy\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m  \x1B[1;36m[3]\x1B[0m \x1B[1m🔑 Cambiar Puerto SSH Destino\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m  \x1B[1;33m[4]\x1B[0m \x1B[1m🌐 Cambiar Código Response HTTP\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m")
		fmt.Println("\x1B[1;34m├─── [ ⚡ CONTROL Y MANTENIMIENTO DEL SERVICIO ]\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m  \x1B[1;33m[5]\x1B[0m \x1B[1m🔄 Reiniciar Servicio Proxy\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m  \x1B[1;32m[6]\x1B[0m \x1B[1m⏯️  Iniciar / Detener Servicio\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m  \x1B[1;36m[7]\x1B[0m \x1B[1m📋 Ver Logs en Tiempo Real\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m")
		fmt.Println("\x1B[1;31m└─── [ ❌ OTROS ]\x1B[0m")
		fmt.Println("   \x1B[1;31m[8]\x1B[0m \x1B[1;31m🗑️  Desinstalar Proxy Completamente\x1B[0m")
		fmt.Println("   \x1B[1;37m[0]\x1B[0m \x1B[1m🚪 Salir del Panel\x1B[0m")
		fmt.Println("\n\x1B[0;90m─────────────────────────────────────────────────────────────\x1B[0m")

		fmt.Print("\x1B[1;33m ❯ Seleccione una opción [0-8]: \x1B[0m")
		input, _ := reader.ReadString('\n')
		choice := strings.TrimSpace(input)

		switch choice {
		case "1":
			showHeader(&cfg)
			fmt.Print("\n\x1B[1;36m📌 Ingrese el nuevo puerto a escuchar: \x1B[0m")
			pIn, _ := reader.ReadString('\n')
			p, err := strconv.Atoi(strings.TrimSpace(pIn))
			if err == nil && p > 0 && p <= 65535 {
				exists := false
				for _, port := range cfg.Ports {
					if port == p {
						exists = true
						break
					}
				}
				if !exists {
					cfg.Ports = append(cfg.Ports, p)
					sort.Ints(cfg.Ports)
					cfg.save()
					fmt.Printf("\x1B[1;32m✅ Puerto %d agregado correctamente.\x1B[0m\n", p)
					restartService()
				} else {
					fmt.Println("\x1B[1;31m❌ El puerto ya está configurado.\x1B[0m")
				}
			} else {
				fmt.Println("\x1B[1;31m❌ Puerto inválido.\x1B[0m")
			}
			pause()

		case "2":
			showHeader(&cfg)
			fmt.Print("\n\x1B[1;31m📌 Ingrese el puerto a eliminar: \x1B[0m")
			pIn, _ := reader.ReadString('\n')
			p, err := strconv.Atoi(strings.TrimSpace(pIn))
			if err == nil {
				if len(cfg.Ports) <= 1 {
					fmt.Println("\x1B[1;31m❌ Debe mantener al menos 1 puerto proxy activo.\x1B[0m")
				} else {
					newPorts := []int{}
					found := false
					for _, port := range cfg.Ports {
						if port == p {
							found = true
						} else {
							newPorts = append(newPorts, port)
						}
					}
					if found {
						cfg.Ports = newPorts
						cfg.save()
						fmt.Printf("\x1B[1;32m✅ Puerto %d eliminado correctamente.\x1B[0m\n", p)
						restartService()
					} else {
						fmt.Println("\x1B[1;31m❌ El puerto no está en uso.\x1B[0m")
					}
				}
			} else {
				fmt.Println("\x1B[1;31m❌ Puerto inválido.\x1B[0m")
			}
			pause()

		case "3":
			showHeader(&cfg)
			fmt.Print("\n\x1B[1;36m📌 Ingrese el nuevo puerto SSH local (ej: 22): \x1B[0m")
			sIn, _ := reader.ReadString('\n')
			sp, err := strconv.Atoi(strings.TrimSpace(sIn))
			if err == nil && sp > 0 && sp <= 65535 {
				cfg.SSHPort = sp
				cfg.save()
				fmt.Printf("\x1B[1;32m✅ Puerto SSH local cambiado a %d.\x1B[0m\n", sp)
				restartService()
			} else {
				fmt.Println("\x1B[1;31m❌ Puerto SSH inválido.\x1B[0m")
			}
			pause()

		case "4":
			showHeader(&cfg)
			fmt.Println("\n\x1B[1;36m📌 SELECCIONE EL MODO DE RESPUESTA HTTP:\x1B[0m")
			fmt.Println("  \x1B[1;32m[1]\x1B[0m HTTP 101  ➜ Switching Protocols (Recomendado WebSocket)")
			fmt.Println("  \x1B[1;33m[2]\x1B[0m HTTP 200  ➜ Connection Established (Estándar Directo)")
			fmt.Println("  \x1B[1;35m[3]\x1B[0m HTTP 200-WS➜ 200 OK con Upgrade WebSocket")
			fmt.Println("  \x1B[1;31m[4]\x1B[0m HTTP 302  ➜ Found / Redirect")
			fmt.Println("  \x1B[1;36m[5]\x1B[0m Modo AUTO ➜ Autodetect")
			fmt.Print("\n\x1B[1;33m ❯ Seleccione una opción [1-5]: \x1B[0m")
			mIn, _ := reader.ReadString('\n')
			switch strings.TrimSpace(mIn) {
			case "1":
				cfg.ResponseCode = "101"
			case "2":
				cfg.ResponseCode = "200"
			case "3":
				cfg.ResponseCode = "200-WS"
			case "4":
				cfg.ResponseCode = "302"
			case "5":
				cfg.ResponseCode = "AUTO"
			default:
				fmt.Println("\x1B[1;31m❌ Opción no válida.\x1B[0m")
				pause()
				continue
			}
			cfg.save()
			fmt.Printf("\x1B[1;32m✅ Respuesta HTTP cambiada a %s.\x1B[0m\n", cfg.ResponseCode)
			restartService()
			pause()

		case "5":
			restartService()
			time.Sleep(500 * time.Millisecond)

		case "6":
			toggleService()

		case "7":
			fmt.Print("\x1B[2J\x1B[1;1H")
			fmt.Println("\x1B[1;36m📋 MONITOR DE LOGS EN TIEMPO REAL (Ctrl+C para salir)\x1B[0m\n")
			cmd := exec.Command("journalctl", "-u", "vpn-proxy", "-f", "-n", "50")
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			cmd.Stdin = os.Stdin
			cmd.Run()

		case "8":
			showHeader(&cfg)
			fmt.Print("\n\x1B[1;31m❓ ¿Desea eliminar por completo el Proxy? (s/N): \x1B[0m")
			confirm, _ := reader.ReadString('\n')
			if strings.EqualFold(strings.TrimSpace(confirm), "s") {
				fmt.Println("\n\x1B[1;33m🛑 Eliminando servicio...\x1B[0m")
				exec.Command("systemctl", "stop", "vpn-proxy").Run()
				exec.Command("systemctl", "disable", "vpn-proxy").Run()
				os.Remove("/etc/systemd/system/vpn-proxy.service")
				exec.Command("systemctl", "daemon-reload").Run()

				os.RemoveAll("/opt/vpn-proxy")
				os.Remove("/usr/local/bin/sshgo")
				os.Remove("/usr/local/bin/proxy")

				fmt.Println("\n\x1B[1;32m✅ Desinstalación terminada correctamente. ¡Hasta luego!\x1B[0m\n")
				os.Exit(0)
			} else {
				fmt.Println("\x1B[1;33mOperación cancelada.\x1B[0m")
				pause()
			}

		case "0":
			fmt.Print("\x1B[2J\x1B[1;1H")
			fmt.Println("\x1B[1;32m👋 ¡Hasta pronto!\x1B[0m\n")
			return

		default:
			fmt.Println("\x1B[1;31m❌ Opción no válida.\x1B[0m")
			time.Sleep(500 * time.Millisecond)
		}
	}
}
EOF

# Compilar binario de Go
go build -ldflags="-s -w" -o /usr/local/bin/sshgo /opt/vpn-proxy/main.go
chmod +x /usr/local/bin/sshgo
ln -sf /usr/local/bin/sshgo /usr/local/bin/proxy

# 4. Configurar Servicio Systemd
echo -e "${C_YELLOW}[4/4] Creando servicio systemd (vpn-proxy.service)...${C_RESET}"
cat > /etc/systemd/system/vpn-proxy.service << 'EOF'
[Unit]
Description=VPN Proxy SSH-Go Engine Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sshgo --daemon
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn-proxy > /dev/null 2>&1
systemctl restart vpn-proxy

# Aliases para el menú interactivo
grep -q "alias sshgo=" /root/.bashrc || echo "alias sshgo='/usr/local/bin/sshgo'" >> /root/.bashrc
grep -q "alias proxy=" /root/.bashrc || echo "alias proxy='/usr/local/bin/sshgo'" >> /root/.bashrc
hash -r 2>/dev/null

echo -e "\n${C_GREEN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_GREEN}│${C_RESET} ${BG_GREEN}${C_WHITE}${C_BOLD}       ¡INSTALACIÓN DE PROXY EN GO COMPLETADA!            ${C_RESET} ${C_GREEN}│${C_RESET}"
echo -e "${C_GREEN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo -e "\n📌 Puedes abrir el panel administrativo escribiendo cualquiera de los comandos:"
echo -e "   - ${C_BOLD}${C_YELLOW}sshgo${C_RESET}"
echo -e "   - ${C_BOLD}${C_YELLOW}proxy${C_RESET}\n"

read -p "$(echo -e "${C_BOLD}${C_CYAN}¿Deseas abrir el Panel Administrativo ahora? (S/n): ${C_RESET}")" RUN_NOW
if [[ "$RUN_NOW" =~ ^[sS]$ ]] || [ -z "$RUN_NOW" ]; then
    /usr/local/bin/sshgo
fi
