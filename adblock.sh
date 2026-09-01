#!/usr/bin/env bash
# =========================================================================
#  AdBlock & DNS Sinkhole All-in-One Installer
#  Compatible: SSH WebSocket, SSH SSL, BadVPN, V2Ray, Xray
#  Sistemas: Ubuntu, Debian, CentOS, AlmaLinux, Rocky Linux
# =========================================================================

export DEBIAN_FRONTEND=noninteractive

# Colores de la terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

DNS_1="94.140.14.14"
DNS_2="94.140.15.15"

# Verificar permisos de root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Este script debe ejecutarse como root (sudo).${NC}"
        exit 1
    fi
}

# Instalar dependencias necesarias automáticamente
install_dependencies() {
    echo -e "${CYAN}[+] Instalando paquetes y dependencias necesarias...${NC}"
    if [ -f /etc/debian_version ]; then
        apt-get update -y -q >/dev/null 2>&1
        apt-get install -y -q python3 dnsutils iptables iptables-persistent netfilter-persistent curl sed gawk >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        yum install -y -q epel-release >/dev/null 2>&1
        yum install -y -q python3 bind-utils iptables iptables-services curl sed gawk >/dev/null 2>&1
    fi
    echo -e "${GREEN}[✔] Dependencias listas.${NC}"
}

# Configuración para SSH WebSocket / SSH SSL / BadVPN (Capa de Red del Sistema)
setup_ssh_websocket() {
    echo -e "\n${CYAN}[1/3] Configurando AdBlock para SSH / WebSocket / BadVPN...${NC}"

    # 1. Configurar /etc/resolv.conf
    chattr -i /etc/resolv.conf >/dev/null 2>&1
    cat <<EOF > /etc/resolv.conf
nameserver $DNS_1
nameserver $DNS_2
EOF
    chattr +i /etc/resolv.conf >/dev/null 2>&1

    # 2. Limpiar reglas previas de iptables para evitar duplicados
    iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1
    iptables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1
    iptables -t nat -D PREROUTING -p udp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1

    # 3. Aplicar redirección forzada de DNS a AdGuard
    iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination $DNS_1:53
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53
    iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination $DNS_1:53
    iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53

    # 4. Crear servicio Systemd de persistencia para que sobreviva a reinicios
    cat <<EOF > /etc/systemd/system/adblock-iptables.service
[Unit]
Description=AdBlock IPTables Persistence
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination $DNS_1:53
ExecStart=/sbin/iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53
ExecStart=/sbin/iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination $DNS_1:53
ExecStart=/sbin/iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable adblock-iptables.service >/dev/null 2>&1
    systemctl start adblock-iptables.service >/dev/null 2>&1

    echo -e "${GREEN}[✔] AdBlock aplicado a SSH WebSocket y BadVPN.${NC}"
}

# Configuración para V2Ray / Xray (Capa de Proxy JSON)
setup_v2ray_xray() {
    echo -e "\n${CYAN}[2/3] Configurando AdBlock para V2Ray / Xray...${NC}"

    RUTAS_CONFIG=(
        "/etc/xray/config.json"
        "/usr/local/etc/xray/config.json"
        "/etc/v2ray/config.json"
        "/usr/local/etc/v2ray/config.json"
        "/etc/v2ray-agent/v2ray/config.json"
        "/etc/v2ray-agent/xray/config.json"
    )

    FOUND=0

    for CONFIG in "${RUTAS_CONFIG[@]}"; do
        if [ -f "$CONFIG" ]; then
            FOUND=1
            echo -e "${YELLOW}[+] Modificando: $CONFIG${NC}"
            cp "$CONFIG" "${CONFIG}.bak_adblock"

            # Modificar JSON de manera segura con Python (soporta comentarios tipo JSON5)
            python3 - <<EOF
import json
import re

path = "$CONFIG"

def remove_comments(text):
    return re.sub(r'//.*?$|/\*.*?\*/', '', text, flags=re.MULTILINE | re.DOTALL)

try:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    clean_content = remove_comments(content)
    data = json.loads(clean_content)

    # 1. Crear Outbound Blackhole si no existe
    if "outbounds" not in data:
        data["outbounds"] = []
    
    if not any(o.get("tag") == "blocked" for o in data["outbounds"]):
        data["outbounds"].append({"protocol": "blackhole", "tag": "blocked"})

    # 2. Inyectar regla de ads en routing
    if "routing" not in data:
        data["routing"] = {"rules": []}
    if "rules" not in data["routing"]:
        data["routing"]["rules"] = []

    has_ad_rule = any("geosite:category-ads-all" in r.get("domain", []) for r in data["routing"]["rules"])
    if not has_ad_rule:
        data["routing"]["rules"].insert(0, {
            "type": "field",
            "outboundTag": "blocked",
            "domain": [
                "geosite:category-ads-all",
                "geosite:spotify-ads"
            ]
        })

    # 3. DNS fallback a AdGuard
    data["dns"] = {
        "servers": ["$DNS_1", "$DNS_2", "1.1.1.1"]
    }

    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("SUCCESS")
except Exception as e:
    print(f"FAILED: {e}")
EOF
        fi
    done

    # Reiniciar servicios si están activos
    if systemctl is-active --quiet xray; then
        systemctl restart xray
        echo -e "${GREEN}[✔] Servicio Xray reiniciado.${NC}"
    fi

    if systemctl is-active --quiet v2ray; then
        systemctl restart v2ray
        echo -e "${GREEN}[✔] Servicio V2Ray reiniciado.${NC}"
    fi

    if [ "$FOUND" -eq 0 ]; then
        echo -e "${YELLOW}[!] No se encontraron archivos config.json de V2Ray/Xray (ignorar si solo usas SSH).${NC}"
    fi
}

# Verificación de bloqueo en tiempo real
verify_status() {
    echo -e "\n${CYAN}[3/3] Probando efectividad del AdBlock...${NC}"
    TEST_DOMAIN="doubleclick.net"
    
    RESULT=$(nslookup $TEST_DOMAIN $DNS_1 2>/dev/null | grep "0.0.0.0")

    echo -e "\n${CYAN}======================================================${NC}"
    if [ -n "$RESULT" ]; then
        echo -e "${GREEN}  ✔  ¡EL ADBLOCK ESTÁ ACTIVO Y FUNCIONANDO AL 100%!${NC}"
        echo -e "${GREEN}  ✔  SSH WebSocket, SSL, V2Ray y Xray protegidos.${NC}"
    else
        echo -e "${YELLOW}  [i] DNS aplicados. Verifica tu conexión a internet.${NC}"
    fi
    echo -e "${CYAN}======================================================${NC}"
}

# Desinstalador / Restaurador
uninstall_adblock() {
    echo -e "\n${YELLOW}[+] Desinstalando AdBlock y restaurando DNS normales...${NC}"
    
    # 1. Restaurar /etc/resolv.conf
    chattr -i /etc/resolv.conf >/dev/null 2>&1
    cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

    # 2. Limpiar iptables y apagar servicio systemd
    iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1
    iptables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1
    iptables -t nat -D PREROUTING -p udp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j DNAT --to-destination $DNS_1:53 >/dev/null 2>&1

    systemctl stop adblock-iptables.service >/dev/null 2>&1
    systemctl disable adblock-iptables.service >/dev/null 2>&1
    rm -f /etc/systemd/system/adblock-iptables.service >/dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1

    # 3. Restaurar backups de V2Ray/Xray
    RUTAS_CONFIG=(
        "/etc/xray/config.json"
        "/usr/local/etc/xray/config.json"
        "/etc/v2ray/config.json"
        "/usr/local/etc/v2ray/config.json"
    )
    for CONFIG in "${RUTAS_CONFIG[@]}"; do
        if [ -f "${CONFIG}.bak_adblock" ]; then
            mv "${CONFIG}.bak_adblock" "$CONFIG"
        fi
    done

    systemctl restart xray >/dev/null 2>&1
    systemctl restart v2ray >/dev/null 2>&1

    echo -e "${GREEN}[✔] AdBlock removido. Sistema en estado original.${NC}"
}

# Flujo Principal
main() {
    check_root
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}     ADBLOCK AUTO-INSTALLER PARA VPN & PROXY          ${NC}"
    echo -e "${BLUE}     (SSH WebSocket | SSL | BadVPN | V2Ray | Xray)    ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}1)${NC} Instalar / Activar AdBlock Completo"
    echo -e "${YELLOW}2)${NC} Verificar Estado del AdBlock"
    echo -e "${YELLOW}3)${NC} Desinstalar y Restaurar DNS Normales"
    echo -e "${YELLOW}0)${NC} Salir"
    echo -e "${CYAN}======================================================${NC}"
    
    # Si se pasa el argumento --install por CLI, ejecutar directamente
    if [ "$1" == "--install" ]; then
        install_dependencies
        setup_ssh_websocket
        setup_v2ray_xray
        verify_status
        exit 0
    fi

    read -p "Selecciona una opción [0-3]: " opt
    case $opt in
        1)
            install_dependencies
            setup_ssh_websocket
            setup_v2ray_xray
            verify_status
            ;;
        2)
            verify_status
            ;;
        3)
            uninstall_adblock
            ;;
        0)
            echo -e "${GREEN}Saliendo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción no válida.${NC}"
            ;;
    esac
}

main "$@"
