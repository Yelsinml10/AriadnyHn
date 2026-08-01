#!/bin/bash
# =========================================================
#  SOCKS PROXY UNIVERSAL - 100% GO (CON PANEL ADMIN)
# =========================================================

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
BG_BLUE='\033[44m'
BG_GREEN='\033[42m'

clear
echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}     🚀 PROXY + PANEL ADMINISTRATIVO 100% GO 🚀            ${C_RESET} ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"

if [ "$EUID" -ne 0 ]; then
  echo -e "\n${C_RED}❌ Error: Por favor ejecuta este script como usuario root.${C_RESET}\n"
  exit 1
fi

# 1. Instalar Go y dependencias
echo -e "\n${C_YELLOW}[1/3] Verificando e instalando Go y herramientas...${C_RESET}"
apt update -y && apt install -y golang-go curl wget net-tools openssh-server systemd > /dev/null 2>&1

mkdir -p /opt/vpn-proxy
CONFIG_FILE="/opt/vpn-proxy/config.json"

# 2. Configurar puerto inicial
echo -e "\n${C_YELLOW}[2/3] Configuración de puerto inicial...${C_RESET}"
read -p "$(echo -e "${C_WHITE}${C_BOLD}ESCRIBE EL PUERTO A ABRIR [8080]: ${C_RESET}")" LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}

cat > "$CONFIG_FILE" << EOF
{
    "ports": [$LISTEN_PORT]
}
EOF

# 3. Código Fuente en Go (Proxy + Panel)
echo -e "\n${C_YELLOW}[3/3] Compilando binario principal '/usr/local/bin/sshgo'...${C_RESET}"
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
	BUFLEN       = 16384
	DEFAULT_HOST = "127.0.0.1:22"
	CONFIG_PATH  = "/opt/vpn-proxy/config.json"
)

type Config struct {
	Ports []int `json:"ports"`
}

func loadConfig() Config {
	file, err := os.ReadFile(CONFIG_PATH)
	if err != nil {
		return Config{Ports: []int{8080}}
	}
	var cfg Config
	if err := json.Unmarshal(file, &cfg); err != nil || len(cfg.Ports) == 0 {
		return Config{Ports: []int{8080}}
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

// --- PROXY BACKEND DAEMON ---

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--daemon" {
		runDaemon()
	} else {
		runPanel()
	}
}

func runDaemon() {
	cfg := loadConfig()
	fmt.Printf("⚡ Daemon Proxy Go iniciado. Puertos: %v\n", cfg.Ports)

	for _, port := range cfg.Ports {
		go func(p int) {
			listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", p))
			if err != nil {
				fmt.Printf("❌ Error escuchando puerto %d: %v\n", p, err)
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

	client.SetReadDeadline(time.Now().Add(15 * time.Second))

	buf := make([]byte, BUFLEN)
	n, err := client.Read(buf)
	if err != nil || n == 0 {
		return
	}

	clientBuffer := string(buf[:n])

	targetHost := findHeader(clientBuffer, "X-Real-Host")
	if targetHost == "" {
		targetHost = findHeader(clientBuffer, "X-Forwarded-For")
	}
	if targetHost == "" {
		targetHost = DEFAULT_HOST
	}
	if !strings.Contains(targetHost, ":") {
		targetHost = targetHost + ":22"
	}

	target, err := net.DialTimeout("tcp", targetHost, 10*time.Second)
	if err != nil {
		target, err = net.DialTimeout("tcp", DEFAULT_HOST, 5*time.Second)
		if err != nil {
			client.Write([]byte("HTTP/1.1 502 Bad Gateway\r\n\r\n"))
			return
		}
	}
	defer target.Close()

	// Respuesta dinámica (101 si solicita WebSocket, 200 en caso contrario)
	if strings.Contains(strings.ToLower(clientBuffer), "upgrade: websocket") {
		client.Write([]byte("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"))
	} else {
		client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	}

	client.SetReadDeadline(time.Time{})

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

func findHeader(head, header string) string {
	key := strings.ToLower(header) + ":"
	lines := strings.Split(head, "\r\n")
	for _, line := range lines {
		if strings.HasPrefix(strings.ToLower(line), key) {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				return strings.TrimSpace(parts[1])
			}
		}
	}
	return ""
}

// --- PANEL ADMINISTRATIVO EN GO ---

func getIP() string {
	out, err := exec.Command("curl", "-s", "https://api.ipify.org").Output()
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
	fmt.Println("\x1B[1;36m│\x1B[0m \x1B[44m\x1B[1;37m      🚀 PANEL DE CONTROL AUTOMÁTICO - ENGINE GO 🚀      \x1B[0m \x1B[1;36m│\x1B[0m")
	fmt.Println("\x1B[1;36m├─────────────────────────────────────────────────────────────┤\x1B[0m")
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m🌐 IP Servidor   :\x1B[0m \x1B[1;36m%s\x1B[0m\n", getIP())

	statusStr := "\x1B[1;31m● DETENIDO (Stopped)\x1B[0m"
	if isActive() {
		statusStr = "\x1B[1;32m● ACTIVO (Comando: sshgo)\x1B[0m"
	}
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m⚡ Estado        :\x1B[0m %s\n", statusStr)
	fmt.Printf("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔌 Puertos Proxy :\x1B[0m \x1B[1;33m%v\x1B[0m\n", cfg.Ports)
	fmt.Println("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔑 Puerto SSH    :\x1B[0m \x1B[1;32m22 (Automático)\x1B[0m")
	fmt.Println("\x1B[1;36m│\x1B[0m  \x1B[1;37m📡 Respuesta HTTP:\x1B[0m \x1B[1;35mAUTO (Dynamic 101/200)\x1B[0m")
	fmt.Println("\x1B[1;36m└─────────────────────────────────────────────────────────────┘\x1B[0m")
}

func restartService() {
	fmt.Println("\n\x1B[1;33m🔄 Reiniciando servicio Proxy...\x1B[0m")
	exec.Command("systemctl", "restart", "vpn-proxy").Run()
	time.Sleep(1 * time.Second)
	fmt.Println("\x1B[1;32m✅ Servicio reiniciado correctamente.\x1B[0m")
}

func runPanel() {
	reader := bufio.NewReader(os.Stdin)

	for {
		cfg := loadConfig()
		showHeader(&cfg)

		fmt.Println("\x1B[1;35m┌─── [ 🛠️ GESTIÓN DE PUERTOS ]\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m  \x1B[1;32m[1]\x1B[0m \x1B[1m➕ Agregar Nuevo Puerto Proxy\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m  \x1B[1;31m[2]\x1B[0m \x1B[1m➖ Quitar Puerto Proxy\x1B[0m")
		fmt.Println("\x1B[1;35m│\x1B[0m")
		fmt.Println("\x1B[1;34m├─── [ ⚡ SERVICIO Y LOGS ]\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m  \x1B[1;33m[3]\x1B[0m \x1B[1m🔄 Reiniciar Servicio\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m  \x1B[1;36m[4]\x1B[0m \x1B[1m📋 Ver Logs en Tiempo Real\x1B[0m")
		fmt.Println("\x1B[1;34m│\x1B[0m")
		fmt.Println("\x1B[1;31m└─── [ ❌ OTROS ]\x1B[0m")
		fmt.Println("   \x1B[1;31m[5]\x1B[0m \x1B[1;31m🗑️  Desinstalar Proxy\x1B[0m")
		fmt.Println("   \x1B[1;37m[0]\x1B[0m \x1B[1m🚪 Salir\x1B[0m")
		fmt.Println("\n\x1B[0;90m─────────────────────────────────────────────────────────────\x1B[0m")

		fmt.Print("\x1B[1;33m ❯ Seleccione una opción [0-5]: \x1B[0m")
		input, _ := reader.ReadString('\n')
		choice := strings.TrimSpace(input)

		switch choice {
		case "1":
			showHeader(&cfg)
			fmt.Print("\n\x1B[1;36m📌 Ingrese el nuevo puerto a escuchar: \x1B[0m")
			pIn, _ := reader.ReadString('\n')
			p, err := strconv.Atoi(strings.TrimSpace(pIn))
			if err == nil && p > 0 {
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
			restartService()
			time.Sleep(500 * time.Millisecond)

		case "4":
			fmt.Print("\x1B[2J\x1B[1;1H")
			fmt.Println("\x1B[1;36m📋 MONITOR DE LOGS (Presione Ctrl+C para salir)\x1B[0m\n")
			cmd := exec.Command("journalctl", "-u", "vpn-proxy", "-f", "-n", "50")
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			cmd.Stdin = os.Stdin
			cmd.Run()

		case "5":
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
				os.Remove("/usr/local/bin/menu")

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

# Compilar binario ejecutable
go build -ldflags="-s -w" -o /usr/local/bin/sshgo /opt/vpn-proxy/main.go
chmod +x /usr/local/bin/sshgo

# Crear enlace simbólico para el comando 'menu'
ln -sf /usr/local/bin/sshgo /usr/local/bin/menu

# 4. Configurar Servicio Systemd
echo -e "${C_YELLOW}Configurando servicio systemd para Go...${C_RESET}"
cat > /etc/systemd/system/vpn-proxy.service << 'EOF'
[Unit]
Description=VPN Proxy SSH-Go Service
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

# Alias para bash
echo "alias sshgo='/usr/local/bin/sshgo'" >> /root/.bashrc
echo "alias menu='/usr/local/bin/sshgo'" >> /root/.bashrc
hash -r 2>/dev/null

echo -e "\n${C_GREEN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_GREEN}│${C_RESET} ${BG_GREEN}${C_WHITE}${C_BOLD}    ¡INSTALACIÓN COMPLETADA! COMANDO PRINCIPAL: sshgo       ${C_RESET} ${C_GREEN}│${C_RESET}"
echo -e "${C_GREEN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo -e "\n📌 Escribe la palabra ${C_BOLD}${C_YELLOW}sshgo${C_RESET} o ${C_BOLD}${C_YELLOW}menu${C_RESET} en tu terminal para abrir el panel.\n"

read -p "$(echo -e "${C_BOLD}${C_CYAN}¿Deseas abrir el Panel Administrativo en Go ahora? (S/n): ${C_RESET}")" RUN_NOW
if [[ "$RUN_NOW" =~ ^[sS]$ ]] || [ -z "$RUN_NOW" ]; then
    /usr/local/bin/sshgo
fi
