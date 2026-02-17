# Proxmox QEMU Docker Setup

Automated deployment scripts for running Proxmox VE in Docker containers with QEMU virtualization, SSL nginx proxy, and automatic resource detection.

## 🚀 Features

- **Interactive Resource Configuration** - Choose from presets (Conservative/Recommended/Maximum) or customize CPU, RAM, and disk allocation
- **Automatic Resource Detection** - Detects system resources and calculates optimal allocations
- **Dynamic IP Detection** - Automatically detects Proxmox VM IP and configures nginx proxy
- **SSL-Enabled nginx Proxy** - Self-signed certificates with HTTPS support
- **Firewall Configuration** - Automatic iptables rules for required ports
- **Network Routing** - Docker bridge to VM network routing setup
- **Complete Automation** - One command to deploy entire stack
- **Interactive Management** - Firewall checker and quick access scripts included

## 📋 Quick Start

### Prerequisites

- Linux host with KVM support
- Docker and Docker Compose installed
- OpenSSL and iptables installed
- Non-root user in docker group

### Installation

```bash
chmod +x proxmox-docker.sh
./proxmox-docker.sh [project_dir] [public_ip]
```

**Parameters (optional):**
- `project_dir` - Installation directory (default: `~/proxmox-qemu`)
- `public_ip` - Public IP address (default: auto-detected)

### Example

```bash
./proxmox-docker.sh ~/my-proxmox
```

## 📂 Files Included

| File | Description |
|------|-------------|
| `proxmox-docker.sh` | Main setup script - automates entire deployment |
| `firewall-check.sh` | Interactive firewall and network verification tool |
| `nginx-proxmox.conf` | nginx reverse proxy configuration template |
| `docker-compose.yml` | Docker container orchestration template |
| `SETUP-GUIDE.md` | Comprehensive setup and troubleshooting guide |

## 💻 Interactive Resource Configuration

The setup script detects system resources and offers flexible allocation options:

### Configuration Modes

**1. Conservative (50%)**
- Leaves plenty of resources for host system
- Ideal for shared servers or development

**2. Recommended (75%)** - Default
- Balanced allocation for most use cases
- Leaves adequate resources for host operations

**3. Maximum (Nearly All)**
- Allocates maximum resources to Proxmox
- Ideal for dedicated virtualization servers

**4. Custom**
- Full control over each resource
- CPU: Choose 1 to all cores
- RAM: Specify in GB (e.g., 8G) or MB (e.g., 8192M)
- Disk: Specify in GB (minimum 32GB)

### Auto-Detection Logic

**CPU**: Detects total cores via `nproc`  
**RAM**: Reads from `/proc/meminfo` (displayed in GB and MB)  
**Disk**: Checks available space in project directory

## 🔥 Firewall Management

### Automatic Configuration
The script automatically:
- Opens ports 8006 (Web UI), 8008 (VNC), 5900 (SSH)
- Enables IP forwarding
- Saves rules persistently

### Manual Check
```bash
./firewall-check.sh
```

Interactive menu provides:
- Status verification
- Quick fixes
- Detailed rule inspection

## 🌐 Network Architecture

```
Internet
    ↓
Public IP:8006 (HTTPS)
    ↓
nginx Proxy Container (SSL termination)
    ↓
Proxmox QEMU Container (172.18.0.x)
    ↓
Proxmox VM (172.30.0.x:8006 - dynamically detected)
```

### Dynamic IP Detection

The Proxmox VM IP is **automatically detected** when the VM boots. The setup script:
1. Waits for the VM to acquire an IP address (172.30.0.0/24 network)
2. Detects the actual IP by querying the container's network interfaces
3. Updates the nginx configuration with the correct IP
4. Reloads nginx to apply the changes

**This ensures the proxy always forwards to the correct IP**, even if it changes between deployments.

## 📝 Access URLs

After setup completes:

- **Proxmox Web UI**: `https://YOUR_IP:8006` (HTTPS)
- **Proxmox VNC Console**: `http://YOUR_IP:8008`
- **Proxmox VM SSH**: `ssh root@<DETECTED_IP>` (from host)

**Note**: The Proxmox VM IP is displayed at the end of the setup. Check the generated `README.md` in your project directory for the exact IP.

**Default Credentials**: Set during Proxmox installation  
**Realm**: Linux PAM standard authentication

## 🛠️ Management

### Start/Stop Services
```bash
cd ~/proxmox-qemu
docker compose up -d        # Start
docker compose down         # Stop
docker compose restart      # Restart
```

### View Logs
```bash
docker compose logs -f proxmox-qemu
docker compose logs -f nginx-proxy
```

### Quick Access Menu
```bash
./access.sh
```

## 📖 Documentation

- **SETUP-GUIDE.md** - Comprehensive setup guide with troubleshooting
- **Generated README.md** - Instance-specific documentation created in project directory

## 🐛 Troubleshooting

### Run Firewall Check
```bash
./firewall-check.sh
```

### Common Issues

**401 Authentication Errors**
- Clear browser cookies
- Use incognito mode
- Access via HTTPS (not HTTP)

**Cannot Access VM**
- Run: `./firewall-check.sh` → option `d` (apply all fixes)
- Check route: `ip route | grep 172.30.0.0`

**Resource Detection Issues**
- Manually edit generated `docker-compose.yml`
- Adjust `RAM_SIZE`, `CPU_CORES`, `DISK_SIZE`

## 🔒 Security Notes

- Self-signed SSL certificate (browser warning is normal)
- For production: Replace with Let's Encrypt or proper CA cert
- Firewall rules expose ports on all interfaces
- Always use strong passwords

## 📊 System Requirements

### Minimum
- **CPU**: 2 cores
- **RAM**: 6GB (4GB for Proxmox + 2GB for host)
- **Disk**: 64GB available
- **OS**: Linux with KVM support

### Recommended
- **CPU**: 4+ cores
- **RAM**: 12GB+
- **Disk**: 128GB+

## 📜 License

MIT License - Free for personal and commercial use

## 🤝 Contributing

Feel free to open issues or submit pull requests for improvements.

---

**Version**: 1.0 with auto resource detection  
**Created**: 2026  
**Tested on**: Debian, Ubuntu with Docker 20+
