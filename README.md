# Proxmox QEMU Docker Setup

Automated deployment scripts for running Proxmox VE in Docker containers with QEMU virtualization, SSL nginx proxy, and automatic resource detection.

## 🚀 Features

- **Automatic Resource Detection** - Intelligently allocates CPU, RAM, and disk based on host system
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

## 💻 Resource Auto-Detection

The setup script automatically detects and allocates:

### CPU
- **≤2 cores**: Allocate 2 cores
- **3-4 cores**: Allocate total - 1
- **5+ cores**: Allocate 75% of total

### RAM
- **≤8GB**: Allocate 4GB
- **>8GB**: Allocate 75% (minimum 2GB reserved for host)

### Disk
- **<80GB available**: Allocate 64GB
- **80-625GB**: Allocate 80%
- **>625GB**: Cap at 500GB

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
Proxmox VM (172.30.0.4:8006)
```

## 📝 Access URLs

After setup completes:

- **Proxmox Web UI**: `https://YOUR_IP:8006` (HTTPS)
- **Proxmox VNC Console**: `http://YOUR_IP:8008`
- **Proxmox VM SSH**: `ssh root@172.30.0.4` (from host)

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
