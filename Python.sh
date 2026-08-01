#!/bin/bash
# =========================================================
#  SOCKS PROXY UNIVERSAL + PANEL PREMIUM (ACCESO CON 'python')
# =========================================================

# Definición de Colores ANSI
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

# Colores de Texto
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_PURPLE='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;90m'

# Fondos
BG_BLUE='\033[44m'
BG_CYAN='\033[46m'
BG_PURPLE='\033[45m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'

clear
echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}   🚀 INSTALADOR SOCKS PROXY UNIVERSAL + PANEL PREMIUM 🚀  ${C_RESET} ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"

# Verificar si es root
if [ "$EUID" -ne 0 ]; then
  echo -e "\n${C_RED}❌ Error: Por favor ejecuta este script como usuario root.${C_RESET}\n"
  exit 1
fi

# 1. Actualizar e instalar dependencias
echo -e "\n${C_YELLOW}[1/5] Actualizando el sistema e instalando dependencias...${C_RESET}"
apt update -y && apt install -y python3 python3-pip curl wget net-tools openssh-server systemd > /dev/null 2>&1

# 2. Configuración Interactiva Simplificada
echo -e "${C_YELLOW}[2/5] Configurando el protocolo Proxy WebSocket Custom...${C_RESET}"

echo -e "\n${C_RED}======================================================${C_RESET}"
echo -e "${C_RED}${C_BOLD}   SOCKS DIRECTO-PY  |  CUSTOM${C_RESET}"
echo -e "${C_RED}======================================================${C_RESET}\n"

read -p "$(echo -e "${C_WHITE}${C_BOLD}ESCRIBE SU PUERTO: ${C_RESET}")" LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}

read -p "$(echo -e "\n${C_WHITE}${C_BOLD}Digite Un Puerto SSH/DROPBEAR activo [22]: ${C_RESET}")" SSH_PORT
SSH_PORT=${SSH_PORT:-22}

read -p "$(echo -e "\n${C_WHITE}${C_BOLD}Escribe El HTTP Response? 101|200|300 [101]: ${C_RESET}")" HTTP_CODE
HTTP_CODE=${HTTP_CODE:-101}

CONFIG_FILE="/root/socks_config.json"
cat > "$CONFIG_FILE" << EOF
{
    "ports": [$LISTEN_PORT],
    "ssh_port": $SSH_PORT,
    "http_code": "$HTTP_CODE"
}
EOF

# 3. Backend de Python
echo -e "\n${C_YELLOW}[3/5] Instalando Engine de Proxy en Python...${C_RESET}"
cat > /root/proxy.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import socket
import threading
import select
import time
import json
import os
import sys
import signal

CONFIG_FILE = "/root/socks_config.json"
BUFLEN = 4096 * 8

def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            log(f"Error cargando config: {e}")
    return {"ports": [8080], "ssh_port": 22, "http_code": "101"}

def build_response(code):
    c = str(code).strip()
    if c == "101":
        return b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'
    elif c == "200":
        return b'HTTP/1.1 200 Connection Established\r\n\r\n'
    elif c == "200-WS":
        return b'HTTP/1.1 200 OK\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'
    elif c == "300":
        return b'HTTP/1.1 300 Multiple Choices\r\n\r\n'
    else:
        return b'HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1\r\n\r\n'

def parse_target_host(data, default_ssh_port):
    target_host = '127.0.0.1'
    target_port = default_ssh_port
    is_http = False

    try:
        header_text = data.decode('utf-8', errors='ignore')
        lines = header_text.split('\r\n')
        if not lines or not lines[0]:
            lines = header_text.split('\n')
        
        first_line = lines[0].strip().split()
        
        if len(first_line) >= 2:
            method = first_line[0].upper()
            uri = first_line[1]
            
            if method in ['GET', 'POST', 'CONNECT', 'OPTIONS', 'HEAD', 'PUT', 'DELETE', 'PATCH', 'TRACE', 'PROPPROMPT']:
                is_http = True

            if method == 'CONNECT':
                if ':' in uri:
                    h, p = uri.split(':', 1)
                    target_host = h
                    try: target_port = int(p)
                    except: pass
                else:
                    target_host = uri
            else:
                for line in lines[1:]:
                    if line.lower().startswith('host:'):
                        host_val = line.split(':', 1)[1].strip()
                        if ':' in host_val:
                            h, p = host_val.split(':', 1)
                            target_host = h
                            try: target_port = int(p)
                            except: pass
                        else:
                            target_host = host_val
                        break
    except Exception:
        pass

    return target_host, target_port, is_http

class ConnectionHandler(threading.Thread):
    def __init__(self, client, addr, ssh_port, response):
        super().__init__()
        self.client = client
        self.addr = addr
        self.ssh_port = ssh_port
        self.response = response
        self.daemon = True

    def run(self):
        try:
            data = self.client.recv(BUFLEN)
            if not data:
                return

            target_host, target_port, is_http = parse_target_host(data, self.ssh_port)

            remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            remote_sock.settimeout(10)
            
            connected = False
            try:
                remote_sock.connect((target_host, target_port))
                connected = True
            except:
                try:
                    remote_sock.connect(('127.0.0.1', self.ssh_port))
                    connected = True
                except:
                    pass

            if not connected:
                if is_http:
                    self.client.send(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
                self.client.close()
                return

            remote_sock.settimeout(None)

            if is_http:
                self.client.send(self.response)
            else:
                remote_sock.send(data)

            self.tunnel(self.client, remote_sock)

        except Exception:
            pass
        finally:
            try: self.client.close()
            except: pass

    def tunnel(self, client, remote):
        sockets = [client, remote]
        while True:
            try:
                r, _, _ = select.select(sockets, [], sockets, 120)
                if not r:
                    break
                for sock in r:
                    data = sock.recv(BUFLEN)
                    if not data:
                        return
                    if sock is client:
                        remote.send(data)
                    else:
                        client.send(data)
            except:
                break

class ProxyServer(threading.Thread):
    def __init__(self, port, ssh_port, response):
        super().__init__()
        self.port = port
        self.ssh_port = ssh_port
        self.response = response
        self.running = True
        self.daemon = True
        self.sock = None

    def run(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sock.bind(('0.0.0.0', self.port))
            self.sock.listen(200)
            log(f"✅ Proxy activo en puerto {self.port} -> SSH Local:{self.ssh_port}")
            
            while self.running:
                try:
                    client, addr = self.sock.accept()
                    handler = ConnectionHandler(client, addr, self.ssh_port, self.response)
                    handler.start()
                except:
                    if not self.running:
                        break
        except Exception as e:
            log(f"❌ Error en puerto {self.port}: {e}")
        finally:
            if self.sock:
                self.sock.close()

    def stop(self):
        self.running = False
        if self.sock:
            try: self.sock.close()
            except: pass

servers = []

def main():
    global servers
    cfg = load_config()
    ports = cfg.get("ports", [8080])
    ssh_port = cfg.get("ssh_port", 22)
    code = cfg.get("http_code", "101")
    response = build_response(code)

    log("Iniciando SOCKS Proxy Engine...")
    for port in ports:
        server = ProxyServer(port, ssh_port, response)
        server.start()
        servers.append(server)

    def signal_handler(sig, frame):
        log("Deteniendo servicio...")
        for s in servers:
            s.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
EOF

chmod +x /root/proxy.py

# 4. Crear Servicio Systemd
echo -e "${C_YELLOW}[4/5] Creando servicio systemd (socks-proxy.service)...${C_RESET}"
cat > /etc/systemd/system/socks-proxy.service << 'EOF'
[Unit]
Description=SOCKS Universal Multi-Host Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /root/proxy.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable socks-proxy > /dev/null 2>&1
systemctl restart socks-proxy

# 5. Crear Panel Administrativo Visual en /usr/local/bin/proxy
echo -e "${C_YELLOW}[5/5] Creando interfaz gráfica para el Panel...${C_RESET}"
cat > /usr/local/bin/proxy << 'EOF'
#!/bin/bash

# Colores de Texto
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

# Fondos
BG_BLUE='\033[44m'
BG_CYAN='\033[46m'
BG_PURPLE='\033[45m'
BG_RED='\033[41m'

CONFIG_FILE="/root/socks_config.json"

get_ip() {
    IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
    echo "$IP"
}

get_status() {
    if systemctl is-active --quiet socks-proxy; then
        echo -e "${C_GREEN}${C_BOLD}● ACTIVO (Running)${C_RESET}"
    else
        echo -e "${C_RED}${C_BOLD}● DETENIDO (Stopped)${C_RESET}"
    fi
}

get_ports() {
    python3 -c "import json; cfg=json.load(open('$CONFIG_FILE')); print(', '.join(map(str, cfg.get('ports', []))))" 2>/dev/null
}

get_ssh_port() {
    python3 -c "import json; cfg=json.load(open('$CONFIG_FILE')); print(cfg.get('ssh_port', 22))" 2>/dev/null
}

get_http_code() {
    python3 -c "import json; cfg=json.load(open('$CONFIG_FILE')); print(cfg.get('http_code', '101'))" 2>/dev/null
}

show_header() {
    clear
    echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}     🚀 PANEL DE CONTROL - SOCKS PROXY UNIVERSAL 🚀     ${C_RESET} ${C_CYAN}│${C_RESET}"
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
        python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
ports = set(cfg.get('ports', []))
ports.add($NEW_PORT)
cfg['ports'] = sorted(list(ports))
json.dump(cfg, open('$CONFIG_FILE', 'w'), indent=4)
"
        echo -e "${C_GREEN}│ ✅ Puerto $NEW_PORT agregado correctamente.${C_RESET}"
        systemctl restart socks-proxy
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
        python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
ports = cfg.get('ports', [])
if $DEL_PORT in ports:
    if len(ports) <= 1:
        print('ERROR_LAST')
    else:
        ports.remove($DEL_PORT)
        cfg['ports'] = ports
        json.dump(cfg, open('$CONFIG_FILE', 'w'), indent=4)
        print('OK')
else:
    print('NOT_FOUND')
" > /tmp/proxy_res
        RES=$(cat /tmp/proxy_res)
        if [ "$RES" == "OK" ]; then
            echo -e "${C_GREEN}│ ✅ Puerto $DEL_PORT eliminado correctamente.${C_RESET}"
            systemctl restart socks-proxy
            echo -e "${C_GREEN}│ ✅ Servicio reiniciado exitosamente.${C_RESET}"
        elif [ "$RES" == "ERROR_LAST" ]; then
            echo -e "${C_RED}│ ❌ No se puede borrar. Debe mantener al menos 1 puerto proxy.${C_RESET}"
        else
            echo -e "${C_RED}│ ❌ El puerto $DEL_PORT no está en uso actualmente.${C_RESET}"
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
        python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['ssh_port'] = $SSH_P
json.dump(cfg, open('$CONFIG_FILE', 'w'), indent=4)
"
        echo -e "${C_GREEN}│ ✅ Puerto SSH local cambiado a $SSH_P.${C_RESET}"
        systemctl restart socks-proxy
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
    echo -e "${C_PURPLE}│${C_RESET}  ${C_RED}[4]${C_RESET} ${C_BOLD}HTTP 302${C_RESET}  ➜ Found / Redirect"
    echo -e "${C_PURPLE}│${C_RESET}"
    read -p "$(echo -e "${C_PURPLE}└───❯${C_RESET} ${C_BOLD}${C_YELLOW}Seleccione una opción [1-4]: ${C_RESET}")" CODE_OPT
    case $CODE_OPT in
        1) HCODE="101" ;;
        2) HCODE="200" ;;
        3) HCODE="200-WS" ;;
        4) HCODE="302" ;;
        *) echo -e "${C_RED}❌ Opción inválida.${C_RESET}"; sleep 1; return ;;
    esac

    python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['http_code'] = '$HCODE'
json.dump(cfg, open('$CONFIG_FILE', 'w'), indent=4)
"
    echo -e "${C_GREEN}✅ Respuesta HTTP cambiada a $HCODE con éxito.${C_RESET}"
    systemctl restart socks-proxy
    read -p "Presione ENTER para continuar..."
}

restart_service() {
    echo -e "\n${C_YELLOW}🔄 Reiniciando servicio Proxy...${C_RESET}"
    systemctl restart socks-proxy
    sleep 1.2
    echo -e "${C_GREEN}✅ Servicio reiniciado correctamente.${C_RESET}"
    sleep 1
}

toggle_service() {
    if systemctl is-active --quiet socks-proxy; then
        systemctl stop socks-proxy
        echo -e "\n${C_RED}⛔ Servicio proxy detenido.${C_RESET}"
    else
        systemctl start socks-proxy
        echo -e "\n${C_GREEN}▶️ Servicio proxy iniciado.${C_RESET}"
    fi
    sleep 1.2
}

view_logs() {
    clear
    echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET} ${BG_CYAN}${C_WHITE}${C_BOLD}       📋 MONITOR DE LOGS EN TIEMPO REAL (Ctrl+C salir)     ${C_RESET} ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}\n"
    journalctl -u socks-proxy -f -n 50
}

uninstall_proxy() {
    show_header
    echo -e "\n${C_RED}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_RED}│${C_RESET} ${BG_RED}${C_WHITE}${C_BOLD}           ⚠️  DESINSTALACIÓN COMPLETA DEL PROXY  ⚠️          ${C_RESET} ${C_RED}│${C_RESET}"
    echo -e "${C_RED}└─────────────────────────────────────────────────────────────┘${C_RESET}"
    read -p "$(echo -e "\n${C_BOLD}${C_RED}❓ ¿Desea eliminar por completo el Proxy y sus configuraciones? (s/N): ${C_RESET}")" CONFIRM
    if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
        echo -e "\n${C_YELLOW}🛑 Deteniendo y deshabilitando servicio systemd...${C_RESET}"
        systemctl stop socks-proxy > /dev/null 2>&1
        systemctl disable socks-proxy > /dev/null 2>&1
        rm -f /etc/systemd/system/socks-proxy.service
        systemctl daemon-reload

        echo -e "${C_YELLOW}🗑️ Borrando archivos e interfaz...${C_RESET}"
        rm -f /root/proxy.py
        rm -f /root/socks_config.json
        rm -f /usr/local/bin/proxy
        rm -f /usr/local/bin/python

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

# 6. Crear Wrapper y Alias para ingresar con 'python', 'proxy' y 'menu'
cat > /usr/local/bin/python << 'EOF'
#!/bin/bash
if [ $# -eq 0 ]; then
    exec /usr/local/bin/proxy
else
    exec /usr/bin/python3 "$@"
fi
EOF
chmod +x /usr/local/bin/python

echo "alias python='/usr/local/bin/proxy'" >> /root/.bashrc
echo "alias menu='/usr/local/bin/proxy'" >> /root/.bashrc

echo -e "\n${C_GREEN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_GREEN}│${C_RESET} ${BG_GREEN}${C_WHITE}${C_BOLD}       ¡INSTALACIÓN DE PROXY UNIVERSAL COMPLETADA!         ${C_RESET} ${C_GREEN}│${C_RESET}"
echo -e "${C_GREEN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo -e "\n📌 Puedes abrir el panel administrativo escribiendo cualquiera de estas palabras:"
echo -e "   - ${C_BOLD}${C_YELLOW}python${C_RESET}"
echo -e "   - ${C_BOLD}${C_YELLOW}proxy${C_RESET}"
echo -e "   - ${C_BOLD}${C_YELLOW}menu${C_RESET}\n"

read -p "$(echo -e "${C_BOLD}${C_CYAN}¿Deseas abrir el Panel Administrativo ahora? (S/n): ${C_RESET}")" RUN_NOW
if [[ "$RUN_NOW" =~ ^[sS]$ ]] || [ -z "$RUN_NOW" ]; then
    /usr/local/bin/proxy
fi
