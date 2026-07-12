#!/bin/bash

# =============================================
# Autoinstalador VPN SSH-Go Proxy (Solo 8080)
# CON PERSISTENCIA FORZADA
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

# Verificar root
[[ $EUID -ne 0 ]] && error "Ejecutar como root: sudo bash $0"

# =============================================
# 0. Verificar puertos libres
# =============================================
step "Verificando puerto disponible..."
PUERTOS=(8080)
for p in "${PUERTOS[@]}"; do
    if ss -tlnp | grep -q ":$p "; then
        error "Puerto $p ya está en uso. Libera el puerto o cambia el script."
    fi
done
info "El puerto 8080 está libre"

# =============================================
# 1. Instalar Go y dependencias
# =============================================
step "Verificando/Instalando Go..."

# Instalar herramientas necesarias
apt update -qq
apt install -y -qq wget tar gcc make curl net-tools

if ! command -v go &>/dev/null; then
    GO_VERSION="1.21.5"
    cd /usr/local
    
    # Detectar arquitectura
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
# 2. Crear directorio y código mejorado
# =============================================
step "Compilando proxy VPN..."

mkdir -p /opt/vpn-proxy
cd /opt/vpn-proxy

# Limpiar módulo anterior si existe
rm -f go.mod go.sum

# Inicializar módulo Go
go mod init vpn-proxy 2>/dev/null

# =============================================
# CÓDIGO GO MEJORADO (con logs y manejo de errores)
# =============================================
cat > main.go << 'GOMAIN'
package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"time"
)

const (
	BUFLEN       = 4096 * 4
	DEFAULT_HOST = "127.0.0.1:22"
	READ_TIMEOUT = 30 * time.Second
)

func main() {
	// Configurar logs a archivo y consola
	logFile, err := os.OpenFile("/var/log/vpn-proxy.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err == nil {
		log.SetOutput(logFile)
		defer logFile.Close()
	}
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)

	puertos := []int{8080}
	log.Printf("Iniciando proxy VPN en puertos: %v", puertos)

	for _, p := range puertos {
		go func(port int) {
			listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", port))
			if err != nil {
				log.Printf("ERROR: No se pudo escuchar en puerto %d: %v", port, err)
				return
			}
			defer listener.Close()
			log.Printf("Escuchando en :%d", port)

			for {
				client, err := listener.Accept()
				if err != nil {
					log.Printf("Error aceptando conexión en puerto %d: %v", port, err)
					continue
				}
				go handleConnection(client)
			}
		}(p)
	}

	// Mantener vivo
	select {}
}

func handleConnection(client net.Conn) {
	defer client.Close()

	// Timeout para leer el primer paquete
	client.SetReadDeadline(time.Now().Add(READ_TIMEOUT))

	buf := make([]byte, BUFLEN)
	n, err := client.Read(buf)
	if err != nil {
		log.Printf("Error leyendo desde %s: %v", client.RemoteAddr(), err)
		return
	}

	clientBuffer := string(buf[:n])
	targetHost := findHeader(clientBuffer, "X-Real-Host")
	if targetHost == "" {
		targetHost = DEFAULT_HOST
		log.Printf("Cliente %s usando host por defecto: %s", client.RemoteAddr(), DEFAULT_HOST)
	} else {
		log.Printf("Cliente %s → %s", client.RemoteAddr(), targetHost)
	}

	// Conectar al destino
	target, err := net.DialTimeout("tcp", targetHost, 10*time.Second)
	if err != nil {
		log.Printf("ERROR: No se pudo conectar a %s: %v", targetHost, err)
		return
	}
	defer target.Close()

	// Escribir respuesta según tipo de conexión
	if strings.Contains(clientBuffer, "Upgrade: websocket") {
		// Respuesta para WebSocket
		response := "HTTP/1.1 101 Switching Protocols\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Accept: " + generateWebSocketAccept(clientBuffer) + "\r\n\r\n"
		client.Write([]byte(response))
		log.Printf("WebSocket upgrade para %s", client.RemoteAddr())
	} else {
		// Respuesta HTTP estándar
		client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	}

	// Quitar timeout después del handshake
	client.SetReadDeadline(time.Time{})

	// Bidireccional copy
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
	log.Printf("Conexión cerrada: %s", client.RemoteAddr())
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
	return strings.TrimSpace(head[start : start+end])
}

// Genera respuesta WebSocket básica (para compatibilidad)
func generateWebSocketAccept(data string) string {
	// Buscar Sec-WebSocket-Key
	key := findHeader(data, "Sec-WebSocket-Key")
	if key == "" {
		return "dGhlIHNhbXBsZSBub25jZQ=="
	}
	return "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
}
GOMAIN

# =============================================
# 3. Compilar con optimizaciones
# =============================================
step "Compilando binario..."

# Descargar dependencias
go mod tidy

# Compilar con flags de optimización
go build -ldflags="-s -w" -o vpn-proxy main.go
chmod +x vpn-proxy

# Verificar que se creó el binario
if [ ! -f vpn-proxy ]; then
    error "Error: No se pudo compilar el proxy"
fi

info "Proxy compilado exitosamente ($(du -h vpn-proxy | cut -f1))"

# =============================================
# 4. Crear servicio systemd - PERSISTENCIA FORZADA
# =============================================
step "Creando servicio systemd con persistencia forzada..."

# Detener servicio si existe
systemctl stop vpn-proxy 2>/dev/null

# Crear archivo de servicio
cat > /etc/systemd/system/vpn-proxy.service << 'EOF'
[Unit]
Description=VPN Proxy SSH-Go
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vpn-proxy
ExecStart=/opt/vpn-proxy/vpn-proxy
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
LimitNOFILE=65536
LimitNPROC=65536
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vpn-proxy

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd
systemctl daemon-reload

# FORZAR habilitación del servicio
systemctl enable vpn-proxy
systemctl enable vpn-proxy --now 2>/dev/null || true

# Iniciar el servicio
systemctl restart vpn-proxy

sleep 3

# Verificar estado
if systemctl is-active --quiet vpn-proxy; then
    info "Servicio activo"
else
    error "El servicio no pudo iniciarse. Revisa: journalctl -u vpn-proxy"
fi

# =============================================
# 5. VERIFICAR PERSISTENCIA
# =============================================
step "Verificando persistencia..."

# Verificar que esté habilitado
if systemctl is-enabled vpn-proxy &>/dev/null; then
    info "✅ Servicio habilitado para iniciar automáticamente en cada reboot"
else
    # FORZAR nuevamente si falló
    systemctl enable vpn-proxy --now
    if systemctl is-enabled vpn-proxy &>/dev/null; then
        info "✅ Servicio habilitado forzosamente"
    else
        error "⚠️ El servicio NO está habilitado. Ejecuta manualmente: systemctl enable vpn-proxy"
    fi
fi

# =============================================
# 6. Mostrar resumen
# =============================================
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     ✅ VPN Proxy SSH-Go Instalado! 🚀           ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}🔌 Puerto activo:${NC}"
echo "   • 8080 (Proxy Interno)"
echo ""
echo -e "${BLUE}📋 Comandos útiles:${NC}"
echo "   systemctl status vpn-proxy     # Estado del servicio"
echo "   systemctl restart vpn-proxy    # Reiniciar"
echo "   journalctl -u vpn-proxy -f     # Ver logs en tiempo real"
echo "   tail -f /var/log/vpn-proxy.log # Logs del programa"
echo ""
echo -e "${BLUE}📁 Archivos:${NC}"
echo "   Código fuente: /opt/vpn-proxy/main.go"
echo "   Binario:       /opt/vpn-proxy/vpn-proxy"
echo "   Logs:          /var/log/vpn-proxy.log"
echo ""
echo -e "${GREEN}✅ PERSISTENCIA CONFIGURADA Y VERIFICADA:${NC}"
echo "   El servicio se iniciará automáticamente después de cada reboot"
echo ""
echo -e "${YELLOW}🧪 Prueba de conexión:${NC}"
echo "   curl -H 'X-Real-Host: 127.0.0.1:22' http://localhost:8080"
echo ""

info "Instalación completada exitosamente!"
