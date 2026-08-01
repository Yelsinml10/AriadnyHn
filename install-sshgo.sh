#!/bin/bash
# =========================================================
#  SOCKS PROXY UNIVERSAL - RUST AUTOMÁTICO
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
echo -e "${C_CYAN}│${C_RESET} ${BG_BLUE}${C_WHITE}${C_BOLD}     🦀 PROXY + PANEL AUTOMÁTICO 100% RUST 🦀            ${C_RESET} ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"

if [ "$EUID" -ne 0 ]; then
  echo -e "\n${C_RED}❌ Error: Por favor ejecuta este script como usuario root.${C_RESET}\n"
  exit 1
fi

# 1. Instalar dependencias puras en Rust
echo -e "\n${C_YELLOW}[1/3] Instalando dependencias del sistema y Rust...${C_RESET}"
apt update -y && apt install -y rustc curl wget net-tools openssh-server systemd > /dev/null 2>&1

# 2. Puerto inicial
echo -e "\n${C_YELLOW}[2/3] Configuración de puerto inicial...${C_RESET}"
read -p "$(echo -e "${C_WHITE}${C_BOLD}ESCRIBE EL PUERTO A ABRIR [8080]: ${C_RESET}")" LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}

CONFIG_FILE="/root/socks_config.json"
cat > "$CONFIG_FILE" << EOF
{
    "ports": [$LISTEN_PORT]
}
EOF

# 3. Código Fuente en Rust (Proxy Automático + Panel)
echo -e "\n${C_YELLOW}[3/3] Compilando binario '/usr/local/bin/rust'...${C_RESET}"
cat > /root/proxy.rs << 'EOF'
use std::env;
use std::fs::File;
use std::io::{self, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[derive(Clone, Debug)]
struct Config {
    ports: Vec<u16>,
}

impl Config {
    fn load() -> Self {
        let mut ports = vec![8080];
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
            }
        }
        Config { ports }
    }

    fn save(&self) -> io::Result<()> {
        let ports_str = format!("{:?}", self.ports);
        let json = format!("{{\n    \"ports\": {}\n}}", ports_str);
        let mut file = File::create("/root/socks_config.json")?;
        file.write_all(json.as_bytes())
    }
}

fn find_header(buffer: &[u8], header_name: &str) -> Option<String> {
    let text = String::from_utf8_lossy(buffer);
    let key = format!("{}:", header_name.to_lowercase());
    
    for line in text.lines() {
        if line.to_lowercase().starts_with(&key) {
            if let Some((_, val)) = line.split_once(':') {
                return Some(val.trim().to_string());
            }
        }
    }
    None
}

fn tunnel(mut client: TcpStream, mut remote: TcpStream) {
    let _ = client.set_read_timeout(Some(Duration::from_secs(120)));
    let _ = remote.set_read_timeout(Some(Duration::from_secs(120)));

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

fn handle_client(mut client: TcpStream) {
    let _ = client.set_read_timeout(Some(Duration::from_secs(15)));

    let mut buf = [0u8; 16384];
    let n = match client.read(&mut buf) {
        Ok(n) if n > 0 => n,
        _ => return,
    };

    let req_str = String::from_utf8_lossy(&buf[..n]);

    let target_header = find_header(&buf[..n], "X-Real-Host")
        .or_else(|| find_header(&buf[..n], "X-Forwarded-For"));

    let target_host = match target_header {
        Some(host_str) if !host_str.is_empty() => host_str,
        _ => "127.0.0.1:22".to_string(),
    };

    let full_target = if !target_host.contains(':') {
        format!("{}:22", target_host)
    } else {
        target_host
    };

    let remote = TcpStream::connect_timeout(
        &full_target.parse().unwrap_or_else(|_| "127.0.0.1:22".parse().unwrap()),
        Duration::from_secs(10),
    ).or_else(|_| TcpStream::connect("127.0.0.1:22"));

    match remote {
        Ok(remote_stream) => {
            let response = if req_str.to_lowercase().contains("upgrade: websocket") {
                b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".to_vec()
            } else {
                b"HTTP/1.1 200 Connection Established\r\n\r\n".to_vec()
            };

            let _ = client.set_read_timeout(None);

            if client.write_all(&response).is_ok() {
                tunnel(client, remote_stream);
            }
        }
        Err(_) => {
            let _ = client.write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\n");
        }
    }
}

fn run_daemon() {
    let config = Config::load();
    println!("⚡ Daemon Proxy Rust iniciado. Puertos: {:?}", config.ports);

    let mut handles = vec![];
    for &port in &config.ports {
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
                    thread::spawn(move || {
                        handle_client(client);
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
    println!("\x1B[1;36m│\x1B[0m \x1B[44m\x1B[1;37m     🦀 PANEL DE CONTROL AUTOMÁTICO - RUST ENGINE 🦀     \x1B[0m \x1B[1;36m│\x1B[0m");
    println!("\x1B[1;36m├─────────────────────────────────────────────────────────────┤\x1B[0m");
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m🌐 IP Servidor   :\x1B[0m \x1B[1;36m{}\x1B[0m", get_ip());
    
    let status_str = if is_active() {
        "\x1B[1;32m● ACTIVO (Comando: rust)\x1B[0m"
    } else {
        "\x1B[1;31m● DETENIDO (Stopped)\x1B[0m"
    };
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m⚡ Estado        :\x1B[0m {}", status_str);
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔌 Puertos Proxy :\x1B[0m \x1B[1;33m{:?}\x1B[0m", cfg.ports);
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m🔑 Puerto SSH    :\x1B[0m \x1B[1;32m22 (Automático)\x1B[0m");
    println!("\x1B[1;36m│\x1B[0m  \x1B[1;37m📡 Respuesta HTTP:\x1B[0m \x1B[1;35mAUTO (Dynamic 101/200)\x1B[0m");
    println!("\x1B[1;36m└─────────────────────────────────────────────────────────────┘\x1B[0m");
}

fn restart_service() {
    println!("\n\x1B[1;33m🔄 Reiniciando servicio Proxy...\x1B[0m");
    let _ = Command::new("systemctl").args(&["restart", "socks-proxy"]).status();
    thread::sleep(Duration::from_millis(1000));
    println!("\x1B[1;32m✅ Servicio reiniciado correctamente.\x1B[0m");
}

fn run_panel() {
    loop {
        let mut cfg = Config::load();
        show_header(&cfg);

        println!("\x1B[1;35m┌─── [ 🛠️ GESTIÓN DE PUERTOS ]\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m  \x1B[1;32m[1]\x1B[0m \x1B[1m➕ Agregar Nuevo Puerto Proxy\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m  \x1B[1;31m[2]\x1B[0m \x1B[1m➖ Quitar Puerto Proxy\x1B[0m");
        println!("\x1B[1;35m│\x1B[0m");
        println!("\x1B[1;34m├─── [ ⚡ SERVICIO Y LOGS ]\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m  \x1B[1;33m[3]\x1B[0m \x1B[1m🔄 Reiniciar Servicio\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m  \x1B[1;36m[4]\x1B[0m \x1B[1m📋 Ver Logs en Tiempo Real\x1B[0m");
        println!("\x1B[1;34m│\x1B[0m");
        println!("\x1B[1;31m└─── [ ❌ OTROS ]\x1B[0m");
        println!("   \x1B[1;31m[5]\x1B[0m \x1B[1;31m🗑️  Desinstalar Proxy\x1B[0m");
        println!("   \x1B[1;37m[0]\x1B[0m \x1B[1m🚪 Salir\x1B[0m");
        println!("\n\x1B[0;90m─────────────────────────────────────────────────────────────\x1B[0m");

        print!("\x1B[1;33m ❯ Seleccione una opción [0-5]: \x1B[0m");
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
                    if p > 0 && !cfg.ports.contains(&p) {
                        cfg.ports.push(p);
                        cfg.ports.sort();
                        let _ = cfg.save();
                        println!("\x1B[1;32m✅ Puerto {} agregado correctamente.\x1B[0m", p);
                        restart_service();
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
            "3" => { restart_service(); thread::sleep(Duration::from_millis(500)); }
            "4" => {
                print!("\x1B[2J\x1B[1;1H");
                println!("\x1B[1;36m📋 MONITOR DE LOGS (Presione Ctrl+C para salir)\x1B[0m\n");
                let _ = Command::new("journalctl")
                    .args(&["-u", "socks-proxy", "-f", "-n", "50"])
                    .status();
            }
            "5" => {
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
                    let _ = std::fs::remove_file("/usr/local/bin/proxy");
                    let _ = std::fs::remove_file("/usr/local/bin/menu");

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

# Enlaces simbólicos directos para comandos
ln -sf /usr/local/bin/rust /usr/local/bin/proxy
ln -sf /usr/local/bin/rust /usr/local/bin/menu

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

# Agregar alias al entorno bash
echo "alias rust='/usr/local/bin/rust'" >> /root/.bashrc
echo "alias proxy='/usr/local/bin/rust'" >> /root/.bashrc
echo "alias menu='/usr/local/bin/rust'" >> /root/.bashrc
hash -r 2>/dev/null

echo -e "\n${C_GREEN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_GREEN}│${C_RESET} ${BG_GREEN}${C_WHITE}${C_BOLD}    ¡INSTALACIÓN COMPLETADA! COMANDO PRINCIPAL: rust         ${C_RESET} ${C_GREEN}│${C_RESET}"
echo -e "${C_GREEN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo -e "\n📌 Escribe la palabra ${C_BOLD}${C_YELLOW}rust${C_RESET} en tu terminal para abrir el panel en cualquier momento.\n"

read -p "$(echo -e "${C_BOLD}${C_CYAN}¿Deseas abrir el Panel Administrativo en Rust ahora? (S/n): ${C_RESET}")" RUN_NOW
if [[ "$RUN_NOW" =~ ^[sS]$ ]] || [ -z "$RUN_NOW" ]; then
    /usr/local/bin/rust
fi
