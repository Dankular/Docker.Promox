# Proxmox Docker Setup Scripts

Automated deployment scripts for running Proxmox VE in Docker with QEMU virtualization.

## 📋 Overview

These scripts automate the complete setup of Proxmox VE running in a Docker container with:
- **Automatic resource detection** (CPU, RAM, disk)
- **SSL-enabled nginx reverse proxy** (self-signed certificates)
- **Firewall configuration** (iptables rules)
- **Network routing** (Docker bridge to VM network)
- **Complete documentation** (README, access scripts)

## 🚀 Quick Start

### 1. Run the Setup Script

```bash
chmod +x proxmox-docker.sh
./proxmox-docker.sh [project_dir] [public_ip]
```

**Parameters** (both optional):
- `project_dir` - Installation directory (default: `~/proxmox-qemu`)
- `public_ip` - Public IP address (default: auto-detected)

**Example:**
```bash
./proxmox-docker.sh ~/my-proxmox
```

### 2. Follow the Interactive Setup

The script will:
1. ✓ Check prerequisites (Docker, OpenSSL, iptables)
2. ✓ **Auto-detect system resources** (CPU, RAM, disk)
3. ✓ **Interactive configuration** - Choose preset or customize resources
4. ✓ Configure firewall rules
5. ✓ Create project directory
6. ✓ Generate SSL certificates
7. ✓ Create nginx configuration
8. ✓ Create docker-compose.yml
9. ✓ Create README documentation
10. ✓ Start Docker containers
11. ✓ Wait for initialization
12. ✓ Detect container IP
13. ✓ Verify services
14. ✓ Configure network routing

### 3. Access Your Proxmox Installation

After setup completes, you'll see:

```
Access Information:

  Proxmox Web UI (HTTPS):
    https://YOUR_IP:8006

  Proxmox VNC Console:
    http://YOUR_IP:8008

  Proxmox VM SSH (from host):
    ssh root@172.30.0.4
```

## 💻 Interactive Resource Configuration

The script detects system resources and offers **4 configuration modes**:

### 1. Conservative (50%)
Leaves half of resources for host system:
- **CPU**: 50% of cores
- **RAM**: 50% of total (min 4GB)
- **Disk**: 50% of available (min 64GB)

**Example:** 6 cores, 12GB RAM, 100GB disk → 3 cores, 6GB, 50GB

### 2. Recommended (75%) - Default
Balanced allocation for most use cases:
- **CPU**: 75% of cores (or total-1 for ≤4 cores)
- **RAM**: 75% of total (always leaves 2GB for host)
- **Disk**: 80% of available (capped at 500GB)

**Example:** 6 cores, 12GB RAM, 100GB disk → 4 cores, 9GB, 80GB

### 3. Maximum (Nearly All)
Dedicates almost everything to Proxmox:
- **CPU**: All cores - 1 (or all for ≤2 cores)
- **RAM**: Total - 2GB (or total for ≤6GB)
- **Disk**: Total - 10GB

**Example:** 6 cores, 12GB RAM, 100GB disk → 5 cores, 10GB, 90GB

### 4. Custom Configuration
Full manual control:
- **CPU**: Enter cores (1 to max detected)
- **RAM**: Enter as GB (8G) or MB (8192M)
- **Disk**: Enter in GB (minimum 32GB)

**Interactive prompts with validation** ensure valid configurations.

### Detection Process

The script automatically detects:
1. **CPU Cores**: Via `nproc` command
2. **Total RAM**: From `/proc/meminfo` (shown in GB and MB)
3. **Available Disk**: From `df` in project directory

After showing detected values, you choose a preset or customize each resource individually.

## 🔥 Firewall Management

### Automatic Configuration
The setup script automatically:
- Opens required ports (8006, 8008, 5900)
- Enables IP forwarding
- Saves rules persistently

### Manual Firewall Check
```bash
chmod +x firewall-check.sh
./firewall-check.sh
```

This interactive tool shows:
1. IP forwarding status
2. Firewall rules for Proxmox ports
3. Network routes
4. Docker container status
5. Connectivity tests
6. Port listening status

### Quick Actions
```
a) Enable IP forwarding
b) Open all firewall ports
c) Add VM network route
d) Apply all fixes
s) Show detailed iptables rules
q) Quit
```

## 📂 Generated Files

After running the setup script:

```
~/proxmox-qemu/
├── docker-compose.yml          # Container orchestration
├── nginx-proxmox.conf          # nginx reverse proxy config
├── nginx-selfsigned.crt        # SSL certificate
├── nginx-selfsigned.key        # SSL private key
├── README.md                   # Complete documentation
├── access.sh                   # Quick access menu script
└── proxmox-data/               # Proxmox VM storage
```

## 🛠️ Management Commands

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
cd ~/proxmox-qemu
./access.sh
```

Menu options:
1. Open Proxmox Web UI (HTTPS)
2. Open Proxmox VNC Console
3. SSH to Proxmox VM
4. View container logs
5. Restart containers
6. Stop containers
7. Start containers

## 🔒 Security Notes

### SSL Certificate
- Self-signed certificate is generated automatically
- Browser will show security warning (normal)
- Click "Advanced" → "Proceed" to continue
- For production: Replace with Let's Encrypt or proper CA cert

### Firewall Rules
- Rules are saved persistently
- Ports are exposed on all interfaces (0.0.0.0)
- Consider restricting to specific IPs in production

### Default Credentials
- Set during Proxmox installation
- Realm: "Linux PAM standard authentication"
- Always use strong passwords

## 🐛 Troubleshooting

### Run Firewall Check
```bash
./firewall-check.sh
```

### Common Issues

**401 Authentication Errors**
- Clear browser cookies
- Use incognito/private mode
- Ensure accessing via HTTPS (not HTTP)

**Cannot Access Proxmox VM from Host**
- Check route: `ip route | grep 172.30.0.0`
- Verify container running: `docker ps`
- Apply fixes: `./firewall-check.sh` → option `d`

**nginx Proxy Fails to Start**
- Check logs: `docker compose logs nginx-proxy`
- Verify SSL certs exist
- Check port 8006 not in use: `sudo netstat -tlnp | grep 8006`

**Resource Detection Issues**
- Manually edit `docker-compose.yml`
- Adjust `RAM_SIZE`, `CPU_CORES`, `DISK_SIZE` environment variables

## 📊 System Requirements

### Minimum
- **CPU**: 2 cores
- **RAM**: 6GB (4GB for Proxmox + 2GB for host)
- **Disk**: 64GB available
- **OS**: Linux with KVM support
- **Software**: Docker, docker-compose, OpenSSL, iptables

### Recommended
- **CPU**: 4+ cores
- **RAM**: 12GB+
- **Disk**: 128GB+
- **Network**: Public IP with open ports

## 📝 Installation Steps for Proxmox

1. **Access VNC Console**: http://YOUR_IP:8008
2. **Download ISO** (if not pre-downloaded):
   ```bash
   cd ~/proxmox-qemu
   wget https://enterprise.proxmox.com/iso/proxmox-ve_8.2-1.iso -O proxmox.iso
   ```
3. **Mount ISO** (edit docker-compose.yml):
   ```yaml
   volumes:
     - ./proxmox-data:/storage
     - ./proxmox.iso:/boot.iso  # Add this line
   ```
4. **Restart container**:
   ```bash
   docker compose restart proxmox-qemu
   ```
5. **Install Proxmox** via VNC console
6. **Remove ISO mount** after installation and delete file:
   ```bash
   rm proxmox.iso
   # Remove ISO line from docker-compose.yml
   docker compose up -d
   ```

## 🌐 Network Architecture

```
Internet
    ↓
VPS Public IP (51.254.142.47)
    ↓
Port 8006 (HTTPS) → nginx-proxy container
    ↓
SSL Termination
    ↓
Proxmox Container (172.18.0.3)
    ↓
Internal Network Bridge
    ↓
Proxmox VM (172.30.0.4:8006)
```

## 🔄 Upgrade/Rebuild

To rebuild with new settings:
```bash
cd ~/proxmox-qemu
docker compose down
rm -rf proxmox-data/  # WARNING: Deletes all VMs!
./proxmox-docker.sh ~/proxmox-qemu
```

To keep data but update configuration:
```bash
cd ~/proxmox-qemu
# Edit docker-compose.yml
docker compose up -d
```

## 📞 Support

**Check Documentation:**
- Project README: `~/proxmox-qemu/README.md`
- This guide: `SETUP-GUIDE.md`

**Verify Setup:**
- Firewall: `./firewall-check.sh`
- Resources: `docker stats`
- Network: `ip route | grep 172.30.0.0`

**Logs:**
- Proxmox: `docker compose logs proxmox-qemu`
- nginx: `docker compose logs nginx-proxy`
- System: `journalctl -xe`

## 📜 License

Scripts are provided as-is for educational and production use.

---

**Created for:** Automated Proxmox VE deployment in Docker  
**Features:** Auto resource detection, SSL proxy, firewall config, full automation  
**Version:** 1.0 with dynamic resource allocation
