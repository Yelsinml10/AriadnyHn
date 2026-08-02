#!/bin/bash
# =========================================================
#  SOCKS PROXY UNIVERSAL - 100% PURE RUST (COMANDO 'rust')
#  VERSIÓN CORREGIDA - TRADUCCIÓN EXACTA 1:1 DE PYTHON
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
echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}   🦀 INSTALADOR PROXY + PANEL 100% RUST (COMANDO rust) 🦀  ${C_RESET} ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"

if [ "$EUID" -ne 0 ]; then
  echo -e "\n${C_RED}❌ Error: Por favor ejecuta este script como usuario root.${C_RESET}\n"
  exit 1
fi

# 1. Instalar dependencias puras en Rust
echo -e "\n${C_YELLOW}[1/4] Instalando compilador Rust (rustc) y herramientas...${C_RESET}"
apt update -y && apt install -y rustc curl wget net-tools openssh-server systemd > /dev/null 2>&1

# Asegurar servicio SSH activo
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null

# 2. Configuración Interactiva
echo -e "\n${C_YELLOW}[2/4] Configurando el protocolo Proxy WebSocket Custom...${C_RESET}"

read -p "$(echo -e "${C_WHITE}${C_BOLD}ESCRIBE EL PUERTO PROXY A ABRIR [8080]: ${C_RESET}")" LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}

SSH_PORT=22
HTTP_CODE="101"

CONFIG_FILE="/root/socks_config.json"
cat > "$CONFIG_FILE" << EOF
{
    "ports": [$LISTEN_PORT],
    "ssh_port": $SSH_PORT,
    "http_code": "$HTTP_CODE"
}
EOF

# 3. Código Fuente en Rust (Traducción 1:1 de Python)
echo -e "\n${C_YELLOW}[3/4] Compilando binario nativo principal '/usr/local/bin/rust'...${C_RESET}"
cat > /root/proxy.rs << 'EOF'
use std::env;
use std::fs::File;
use std::io::{self, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::process::Command;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

#[derive(Clone, Debug)]
struct Config {
    ports: Vec<u16>,
    ssh_port: u16,
    http_code: String,
}

impl Config {
    fn load() -> Self {
        let mut ports = vec![8080];
        let mut ssh_port = 22;
        let mut http_code = String::from("101");

        if let Ok(mut file) = File::open("/root/socks_config.json") {
            let mut content = String::new();
            if file.read_to_string(&mut content).is_ok() {
                if let Some(p_start) = content.find("\"ports\"") {
                    if let Some(arr_start) = content[p_start..].find('[') {
                        if let Some(arr_end) = content[p_start + arr_start..].find(']') {
                            let arr_str = &content[p_start + arr_start + 1..p_start + arr_start + arr_end];
                            let parsed: Vec<u16> = arr_str
                                .split(',')
                                .filter_map(|s| s.trim().parse().ok())
                                .collect();
                            if !parsed.is_empty() {
                                ports = parsed;
                            }
                        }
                    }
                }

                if let Some(s_start) = content.find("\"ssh_port\"") {
                    let sub = &content[s_start..];
                    if let Some(colon) = sub.find(':') {
                        let val_str: String = sub[colon + 1..]
                            .chars()
                            .take_while(|c| c.is_digit(10) || c.is_whitespace())
                            .collect();
                        if let Ok(p) = val_str.trim().parse() {
                            ssh_port = p;
                        }
                    }
                }

                if let Some(c_start) = content.find("\"http_code\"") {
                    let sub = &content[c_start..];
                    if let Some(colon) = sub.find(':') {
                        let val_str = sub[colon + 1..].lines().next().unwrap_or("");
                        if val_str.contains("101") {
                            http_code = "101".to_string();
                        } else if val_str.contains("200-WS") {
                            http_code = "200-WS".to_string();
                        } else if val_str.contains("200") {
                            http_code = "200".to_string();
                        } else if val_str.contains("302") {
                            http_code = "302".to_string();
                        }
                    }
                }
            }
        }
        Config { ports, ssh_port, http_code }
    }

    fn save(&self) -> io::Result<()> {
        let ports_str = format!("{:?}", self.ports);
        let json = format!(
            "{{\n    \"ports\": {},\n    \"ssh_port\": {},\n    \"http_code\": \"{}\"\n}}",
            ports_str, self.ssh_port, self.http_code
        );
        let mut file = File::create("/root/socks_config.json")?;
        file.write_all(json.as_bytes())
    }
}

// --- PARSER DE CABECERAS EXACTO A PYTHON ---
fn find_header(head: &str, header_name: &str) -> String {
    let head_lower = head.to_lowercase();
    let key = format!("{}:", header_name.to_lowercase());
    if let Some(idx) = head_lower.find(&key) {
        let start = idx + key.len();
        let rest = &head[start..];
        let end1 = rest.find("\r\n");
        let end2 = rest.find('\n');
        let end = match (end1, end2) {
            (Some(e1), Some(e2)) => std::cmp::min(e1, e2),
            (Some(e1), None) => e1,
            (None, Some(e2)) => e2,
            (None, None) => rest.len(),
        };
        return rest[..end].trim().to_string();
    }
    String::new()
}

fn tunnel(mut client: TcpStream, mut remote: TcpStream) {
    let _ = client.set_read_timeout(None);
    let _ = remote.set_read_timeout(None);

    let mut client_read = match client.try_clone() {
        Ok(s) => s,
        Err(_) => return,
    };
    let mut remote_write = match remote.try_clone() {
        Ok(s) => s,
        Err(_) => return,
    };

    let t1 = thread::spawn(move || {
        let mut buf = [0u8; 16384];
        while let Ok(n) = client_read.read(&mut buf) {
            if n == 0 { break; }
            if remote_write.write_all(&buf[..n]).is_err() { break; }
        }
    });

    let mut remote_read = remote;
    let mut client_write = client;

    let t2 = thread::spawn(move || {
        let mut buf = [0u8; 16384];
        while let Ok(n) = remote_read.read(&mut buf) {
            if n == 0 { break; }
            if client_write.write_all(&buf[..n]).is_err() { break; }
        }
    });

    let _ = t1.join();
    let _ = t2.join();
}

fn handle_client(mut client: TcpStream, ssh_port: u16, http_code: String) {
    let _ = client.set_read_timeout(Some(Duration::from_secs(15)));

    let mut buf = [0u8; 16384];
    let n = match client.read(&mut buf) {
        Ok(n) if n > 0 => n,
        _ => return,
    };

    let client_buffer = String::from_utf8_lossy(&buf[..n]);

    // 1. Extraer Host Destino idéntico a Python
    let mut target_host_str = find_header(&client_buffer, "X-Real-Host");
    if target_host_str.is_empty() {
        target_host_str = find_header(&client_buffer, "X-Forwarded-For");
    }
    if target_host_str.is_empty() {
        target_host_str = find_header(&client_buffer, "X-Online-Host");
    }

    let (target_host, target_port) = if !target_host_str.is_empty() {
        if let Some((h, p)) = target_host_str.split_once(':') {
            let parsed_p = p.trim().parse::<u16>().unwrap_or(ssh_port);
            (h.trim().to_string(), parsed_p)
        } else {
            (target_host_str.trim().to_string(), ssh_port)
        }
    } else {
        ("127.0.0.1".to_string(), ssh_port)
    };

    // 2. Conectar al destino con fallback idéntico a Python
    let remote = TcpStream::connect((target_host.as_str(), target_port))
        .or_else(|_| TcpStream::connect(("127.0.0.1", ssh_port)));

    let mut remote_stream = match remote {
        Ok(s) => s,
        Err(_) => return,
    };

    // 3. Respuesta HTTP seleccionada (idéntica a Python)
    let lower_buf = client_buffer.to_lowercase();
    let resp = match http_code.as_str() {
        "101" => b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".to_vec(),
        "200" => b"HTTP/1.1 200 Connection Established\r\n\r\n".to_vec(),
        "200-WS" => b"HTTP/1.1 200 OK\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".to_vec(),
        "302" => b"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1\r\n\r\n".to_vec(),
        _ => {
            if lower_buf.contains("websocket") || lower_buf.contains("upgrade") {
                b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".to_vec()
            } else {
                b"HTTP/1.1 200 Connection Established\r\n\r\n".to_vec()
            }
        }
    };

    if client.write_all(&resp).is_err() {
        return;
    }

    // 4. Tunelizado bidireccional de sockets
    tunnel(client, remote_stream);
}

fn run_daemon() {
    let config = Config::load();
    let ssh_port = config.ssh_port;
    let http_code = config.http_code;

    println!("⚡ Daemon Proxy Rust iniciado. Puertos: {:?}", config.ports);

    let mut handles = vec![];
    for &port in &config.ports {
        let code_clone = http_code.clone();
        let handle = thread::spawn(move || {
            let listener = match TcpListener::bind(("0.0.0.0", port)) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("❌ Error escuchando puerto {}: {}", port, e);
                    return;
                }
            };
            for stream in listener.incoming() {
                if let Ok(client) = stream {
                    let code_c = code_clone.clone();
                    thread::spawn(move || {
                        handle_client(client, ssh_port, code_c);
                    });
                }
            }
        });
        handles.push(handle);
    }
    for h in handles {
        let _ = h.join();
    }
}

// --- PANEL ADMINISTRATIVO EN RUST ---
fn get_ip() -> String {
    let output = Command::new("curl").args(&["-s", "https://api.ipify.org"]).output();
    if let Ok(o) = output {
        let ip = String::from_utf8_lossy(&o.stdout).trim().to_string();
        if !ip.is_empty() { return ip; }
    }
    "127.0.0.1".to_string()
}

fn is_active() -> bool {
    let status = Command::new("systemctl")
        .args(&["is-active", "--quiet", "socks-proxy"])
        .status();
    match status {
        Ok(s) => s.success(),
        Err(_) => false,
    }
}

fn pause() {
    print!("\nPresione ENTER para continuar...");
    let _ = io::stdout().flush();
    let mut buf = String::new();
    let _ = io::stdin().read_line(&mut buf);
}

fn show_header(cfg: &Config) {
    print!("\x1B[2J\x1B[1;1H");
    println!("\x1B[1;36m┌─────────────────────────────────────────────────────────────┐\x1B[0m");
    println!("\x1B[1;36m│\x1B[0m \x1B[44m\x1B[1;37m     🦀 PANEL DE CONTROL - 100% PURE RUST ENGINE 🦀     \x1B[0m \x1B[1;36m│\x1B[0m");
    println!("\x1B[1;36m├─────────────────────────────────────────────────────────────┤\x1B[0m");
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m🌐 IP Servidor   :\x1B[0m \x1B[1;36m{}\x1B[0m", get_ip());
    
    let status_str = if is_active() {
        "\x1B[1;32m● ACTIVO (Comando: rust)\x1B[0m"
    } else {
        "\x1B[1;31m● DETENIDO (Stopped)\x1B[0m"
    };
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m⚡ Estado        :\x1B[0m {}", status_str);
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔌 Puertos Proxy :\x1B[0m \x1B[1;33m{:?}\x1B[0m", cfg.ports);
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔑 Puerto SSH    :\x1B[0m \x1B[1;32m{}\x1B[0m", cfg.ssh_port);
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m📡 Respuesta HTTP:\x1B[0m \x1B[1;35mHTTP {}\x1B[0m", cfg.http_code);
    println!("\x1B[1;36m└─────────────────────────────────────────────────────────────┘\x1B[0m");
}

fn restart_service() {
    println!("\n\x1B[1;33m🔄 Reiniciando servicio Proxy en Rust...\x1B[0m");
    let _ = Command::new("systemctl").args(&["restart", "socks-proxy"]).status();
    thread::sleep(Duration::from_millis(1000));
    println!("\x1B[1;32m✅ Servicio reiniciado correctamente.\x1B[0m");
}

fn run_panel() {
    loop {
        let mut cfg = Config::load();
        show_header(&cfg);

        println!("\x1B[1;35m┌─── [ 🛠️ CONFIGURACIÓN DE PUERTOS Y PROTOCOLO ]\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m  \x1B[1;32m[1]\x1B[0m \x1B[1m➕ Agregar Puerto Proxy\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m  \x1B[1;31m[2]\x1B[0m \x1B[1m➖ Quitar Puerto Proxy\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m  \x1B[1;36m[3]\x1B[0m \x1B[1m🔑 Cambiar Puerto SSH Destino\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m  \x1B[1;33m[4]\x1B[0m \x1B[1m🌐 Cambiar Código HTTP Response\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m");
        println!("\x1B[1;34m├─── [ ⚡ CONTROL Y MANTENIMIENTO DEL SERVICIO ]\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m  \x1B[1;33m[5]\x1B[0m \x1B[1m🔄 Reiniciar Servicio Proxy\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m  \x1B[1;32m[6]\x1B[0m \x1B[1m⏯️  Iniciar / Detener Servicio\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m  \x1B[1;36m[7]\x1B[0m \x1B[1m📋 Ver Logs en Tiempo Real\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m");
        println!("\x1B[1;31m└─── [ ❌ OTROS ]\x1B[0m");
        println!("   \x1B[1;31m[8]\x1B[0m \x1B[1;31m🗑️  Desinstalar Proxy Completamente\x1B[0m");
        println!("   \x1B[1;37m[0]\x1B[0m \x1B[1m🚪 Salir del Panel\x1B[0m");
        println!("\n\x1B[0;90m─────────────────────────────────────────────────────────────\x1B[0m");

        print!("\x1B[1;33m ❯ Seleccione una opción [0-8]: \x1B[0m");
        let _ = io::stdout().flush();
        let mut input = String::new();
        if io::stdin().read_line(&mut input).is_err() { break; }
        let choice = input.trim();

        match choice {
            "1" => {
                show_header(&cfg);
                print!("\n\x1B[1;36m📌 Ingrese el nuevo puerto a escuchar: \x1B[0m");
                let _ = io::stdout().flush();
                let mut p_in = String::new();
                let _ = io::stdin().read_line(&mut p_in);
                if let Ok(p) = p_in.trim().parse::<u16>() {
                    if p > 0 {
                        if !cfg.ports.contains(&p) {
                            cfg.ports.push(p);
                            cfg.ports.sort();
                            let _ = cfg.save();
                            println!("\x1B[1;32m✅ Puerto {} agregado correctamente.\x1B[0m", p);
                            restart_service();
                        }
                    }
                } else { println!("\x1B[1;31m❌ Puerto inválido.\x1B[0m"); }
                pause();
            }
            "2" => {
                show_header(&cfg);
                print!("\n\x1B[1;31m📌 Ingrese el puerto a eliminar: \x1B[0m");
                let _ = io::stdout().flush();
                let mut p_in = String::new();
                let _ = io::stdin().read_line(&mut p_in);
                if let Ok(p) = p_in.trim().parse::<u16>() {
                    if cfg.ports.contains(&p) {
                        if cfg.ports.len() <= 1 {
                            println!("\x1B[1;31m❌ Debe mantener al menos 1 puerto proxy activo.\x1B[0m");
                        } else {
                            cfg.ports.retain(|&x| x != p);
                            let _ = cfg.save();
                            println!("\x1B[1;32m✅ Puerto {} eliminado correctamente.\x1B[0m", p);
                            restart_service();
                        }
                    } else { println!("\x1B[1;31m❌ El puerto no está en uso.\x1B[0m"); }
                } else { println!("\x1B[1;31m❌ Puerto inválido.\x1B[0m"); }
                pause();
            }
            "3" => {
                show_header(&cfg);
                print!("\n\x1B[1;32m📌 Ingrese el nuevo puerto SSH local (ej: 22): \x1B[0m");
                let _ = io::stdout().flush();
                let mut p_in = String::new();
                let _ = io::stdin().read_line(&mut p_in);
                if let Ok(p) = p_in.trim().parse::<u16>() {
                    cfg.ssh_port = p;
                    let _ = cfg.save();
                    println!("\x1B[1;32m✅ Puerto SSH modificado a {}.\x1B[0m", p);
                    restart_service();
                } else { println!("\x1B[1;31m❌ Puerto inválido.\x1B[0m"); }
                pause();
            }
            "4" => {
                show_header(&cfg);
                println!("\n\x1B[1;35m[1] HTTP 101 (Switching Protocols - WebSocket)\x1B[0m");
                println!("\x1B[1;32m[2] HTTP 200 (Connection Established - Standard)\x1B[0m");
                println!("\x1B[1;33m[3] HTTP 200-WS (200 OK + Upgrade WebSocket)\x1B[0m");
                println!("\x1B[1;31m[4] HTTP 302 (Found / Redirect)\x1B[0m");
                print!("\n\x1B[1;33m❯ Seleccione una opción [1-4]: \x1B[0m");
                let _ = io::stdout().flush();
                let mut c_in = String::new();
                let _ = io::stdin().read_line(&mut c_in);
                let code = match c_in.trim() {
                    "1" => "101",
                    "2" => "200",
                    "3" => "200-WS",
                    "4" => "302",
                    _ => "",
                };
                if !code.is_empty() {
                    cfg.http_code = code.to_string();
                    let _ = cfg.save();
                    println!("\x1B[1;32m✅ Respuesta HTTP cambiada a {}.\x1B[0m", code);
                    restart_service();
                } else { println!("\x1B[1;31m❌ Opción inválida.\x1B[0m"); }
                pause();
            }
            "5" => { restart_service(); thread::sleep(Duration::from_millis(500)); }
            "6" => {
                if is_active() {
                    let _ = Command::new("systemctl").args(&["stop", "socks-proxy"]).status();
                    println!("\n\x1B[1;31m⛔ Servicio detenido.\x1B[0m");
                } else {
                    let _ = Command::new("systemctl").args(&["start", "socks-proxy"]).status();
                    println!("\n\x1B[1;32m▶️ Servicio iniciado.\x1B[0m");
                }
                thread::sleep(Duration::from_millis(1000));
            }
            "7" => {
                print!("\x1B[2J\x1B[1;1H");
                println!("\x1B[1;36m📋 MONITOR DE LOGS (Presione Ctrl+C para salir)\x1B[0m\n");
                let _ = Command::new("journalctl")
                    .args(&["-u", "socks-proxy", "-f", "-n", "50"])
                    .status();
            }
            "8" => {
                show_header(&cfg);
                print!("\n\x1B[1;31m❓ ¿Desea eliminar por completo el Proxy? (s/N): \x1B[0m");
                let _ = io::stdout().flush();
                let mut confirm = String::new();
                let _ = io::stdin().read_line(&mut confirm);
                if confirm.trim().eq_ignore_ascii_case("s") {
                    println!("\n\x1B[1;33m🛑 Eliminando servicio...\x1B[0m");
                    let _ = Command::new("systemctl").args(&["stop", "socks-proxy"]).status();
                    let _ = Command::new("systemctl").args(&["disable", "socks-proxy"]).status();
                    let _ = std::fs::remove_file("/etc/systemd/system/socks-proxy.service");
                    let _ = Command::new("systemctl").arg("daemon-reload").status();

                    let _ = std::fs::remove_file("/root/proxy.rs");
                    let _ = std::fs::remove_file("/root/socks_config.json");
                    let _ = std::fs::remove_file("/usr/local/bin/rust");

                    println!("\n\x1B[1;32m✅ Desinstalación terminada correctamente. ¡Hasta luego!\x1B[0m\n");
                    std::process::exit(0);
                } else {
                    println!("\x1B[1;33mOperación cancelada.\x1B[0m");
                    pause();
                }
            }
            "0" => {
                print!("\x1B[2J\x1B[1;1H");
                println!("\x1B[1;32m👋 ¡Hasta pronto!\x1B[0m\n");
                break;
            }
            _ => { println!("\x1B[1;31m❌ Opción no válida.\x1B[0m"); thread::sleep(Duration::from_millis(500)); }
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 && args[1] == "--daemon" {
        run_daemon();
    } else {
        run_panel();
    }
}
EOF

# Compilar ejecutable binario nativo en /usr/local/bin/rust
rustc -O /root/proxy.rs -o /usr/local/bin/rust
chmod +x /usr/local/bin/rust

# 4. Configurar Servicio Systemd
echo -e "${C_YELLOW}[4/4] Configurando servicio systemd para Rust...${C_RESET}"
cat > /etc/systemd/system/socks-proxy.service << 'EOF'
[Unit]
Description=SOCKS Universal Multi-Host Proxy Service (Pure Rust)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/rust --daemon
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable socks-proxy > /dev/null 2>&1
systemctl restart socks-proxy

# Agregar alias exclusivo al entorno bash
grep -q "alias rust=" /root/.bashrc || echo "alias rust='/usr/local/bin/rust'" >> /root/.bashrc
hash -r 2>/dev/null

echo -e "\n${C_GREEN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_GREEN}│${C_RESET} ${BG_GREEN}${C_WHITE}${C_BOLD}    ¡INSTALACIÓN COMPLETADA! COMANDO PRINCIPAL: rust         ${C_RESET} ${C_GREEN}│${C_RESET}"
echo -e "${C_GREEN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo -e "\n📌 Escribe la palabra ${C_BOLD}${C_YELLOW}rust${C_RESET} en tu terminal para abrir el panel.\n"

read -p "$(echo -e "${C_BOLD}${C_CYAN}¿Deseas abrir el Panel Administrativo en Rust ahora? (S/n): ${C_RESET}")" RUN_NOW
if [[ "$RUN_NOW" =~ ^[sS]$ ]] || [ -z "$RUN_NOW" ]; then
    /usr/local/bin/rust
fi
