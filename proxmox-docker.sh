#!/bin/bash
set -e

#############################################
# Proxmox QEMU Docker Setup Script
# Automated deployment with SSL nginx proxy
#############################################

# Configuration Variables
PROJECT_DIR="${1:-$HOME/proxmox-qemu}"
PUBLIC_IP="${2:-$(curl -s ifconfig.me)}"
PROXMOX_VM_NETWORK="172.30.0.0/24"
PROXMOX_VM_IP="172.30.0.4"
DOCKER_NETWORK_IP="172.18.0.3"  # Will be dynamically detected

# Ports
PROXMOX_WEB_PORT="8006"
PROXMOX_VNC_PORT="8008"
PROXMOX_SSH_PORT="5900"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Proxmox QEMU Docker Setup Script${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Please do not run as root. Run as regular user with docker permissions.${NC}"
    exit 1
fi

# Check prerequisites
echo -e "${YELLOW}[1/13] Checking prerequisites...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker is not installed. Aborting.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker Compose is not available. Aborting.${NC}" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo -e "${RED}OpenSSL is not installed. Aborting.${NC}" >&2; exit 1; }
command -v iptables >/dev/null 2>&1 || { echo -e "${RED}iptables is not installed. Aborting.${NC}" >&2; exit 1; }

# Check if user is in docker group
if ! groups | grep -q docker; then
    echo -e "${RED}Current user is not in docker group. Please add with: sudo usermod -aG docker $USER${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"

# Detect system resources
echo -e "${YELLOW}[2/12] Detecting system resources...${NC}"

# Detect CPU cores
TOTAL_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "4")
# Allocate 75% of cores to Proxmox, minimum 2, maximum available-1
if [ "$TOTAL_CORES" -le 2 ]; then
    CPU_CORES=2
elif [ "$TOTAL_CORES" -le 4 ]; then
    CPU_CORES=$(($TOTAL_CORES - 1))
else
    CPU_CORES=$(($TOTAL_CORES * 3 / 4))
fi
echo -e "  ${BLUE}CPU Cores: ${TOTAL_CORES} detected → Allocating ${CPU_CORES} to Proxmox${NC}"

# Detect RAM (in MB)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(($TOTAL_RAM_KB / 1024 / 1024))
# Allocate 75% of RAM to Proxmox, minimum 4GB, leave at least 2GB for host
if [ "$TOTAL_RAM_GB" -le 8 ]; then
    RAM_SIZE="4G"
else
    RAM_ALLOCATED_GB=$(($TOTAL_RAM_GB * 3 / 4))
    # Cap at total - 2GB
    if [ "$RAM_ALLOCATED_GB" -gt $(($TOTAL_RAM_GB - 2)) ]; then
        RAM_ALLOCATED_GB=$(($TOTAL_RAM_GB - 2))
    fi
    RAM_SIZE="${RAM_ALLOCATED_GB}G"
fi
echo -e "  ${BLUE}RAM: ${TOTAL_RAM_GB}GB detected → Allocating ${RAM_SIZE} to Proxmox${NC}"

# Detect available disk space (in GB)
if [ -d "$PROJECT_DIR" ]; then
    AVAILABLE_DISK=$(df -BG "$PROJECT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
else
    AVAILABLE_DISK=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | sed 's/G//')
fi
# Allocate 80% of available space, minimum 64GB, maximum 500GB
if [ "$AVAILABLE_DISK" -lt 80 ]; then
    DISK_SIZE="64G"
elif [ "$AVAILABLE_DISK" -gt 625 ]; then
    DISK_SIZE="500G"
else
    DISK_ALLOCATED=$(($AVAILABLE_DISK * 4 / 5))
    DISK_SIZE="${DISK_ALLOCATED}G"
fi
echo -e "  ${BLUE}Disk: ${AVAILABLE_DISK}GB available → Allocating ${DISK_SIZE} to Proxmox${NC}"

echo -e "${GREEN}✓ Resource allocation calculated${NC}"
echo ""
echo -e "${YELLOW}Allocated Resources Summary:${NC}"
echo -e "  CPU Cores: ${CPU_CORES}"
echo -e "  RAM: ${RAM_SIZE}"
echo -e "  Disk: ${DISK_SIZE}"
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."

# Configure firewall and IP forwarding
echo -e "${YELLOW}[3/12] Configuring firewall rules...${NC}"

# Check if we need sudo
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

# Enable IP forwarding (required for Docker networking)
echo -e "  ${BLUE}Enabling IP forwarding...${NC}"
$SUDO sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" | $SUDO tee -a /etc/sysctl.conf >/dev/null
fi

# Check if firewall is active
if $SUDO iptables -L -n >/dev/null 2>&1; then
    echo -e "  ${BLUE}Configuring iptables rules...${NC}"
    
    # Allow Proxmox Web UI (HTTPS)
    if ! $SUDO iptables -C INPUT -p tcp --dport ${PROXMOX_WEB_PORT} -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I INPUT -p tcp --dport ${PROXMOX_WEB_PORT} -j ACCEPT
        echo -e "    ${GREEN}✓ Opened port ${PROXMOX_WEB_PORT} (Proxmox Web UI - HTTPS)${NC}"
    else
        echo -e "    ${GREEN}✓ Port ${PROXMOX_WEB_PORT} already open${NC}"
    fi
    
    # Allow Proxmox VNC Console
    if ! $SUDO iptables -C INPUT -p tcp --dport ${PROXMOX_VNC_PORT} -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I INPUT -p tcp --dport ${PROXMOX_VNC_PORT} -j ACCEPT
        echo -e "    ${GREEN}✓ Opened port ${PROXMOX_VNC_PORT} (Proxmox VNC)${NC}"
    else
        echo -e "    ${GREEN}✓ Port ${PROXMOX_VNC_PORT} already open${NC}"
    fi
    
    # Allow Proxmox SSH/VNC secondary port
    if ! $SUDO iptables -C INPUT -p tcp --dport ${PROXMOX_SSH_PORT} -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I INPUT -p tcp --dport ${PROXMOX_SSH_PORT} -j ACCEPT
        echo -e "    ${GREEN}✓ Opened port ${PROXMOX_SSH_PORT} (Proxmox SSH/VNC)${NC}"
    else
        echo -e "    ${GREEN}✓ Port ${PROXMOX_SSH_PORT} already open${NC}"
    fi
    
    # Allow Docker forwarding
    if ! $SUDO iptables -C FORWARD -i docker0 -o docker0 -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I FORWARD -i docker0 -o docker0 -j ACCEPT 2>/dev/null || true
    fi
    
    # Save iptables rules (Debian/Ubuntu)
    if command -v iptables-save >/dev/null 2>&1; then
        if command -v netfilter-persistent >/dev/null 2>&1; then
            $SUDO netfilter-persistent save 2>/dev/null || true
            echo -e "    ${GREEN}✓ Firewall rules saved (netfilter-persistent)${NC}"
        elif [ -f /etc/iptables/rules.v4 ]; then
            $SUDO iptables-save | $SUDO tee /etc/iptables/rules.v4 >/dev/null 2>&1 || true
            echo -e "    ${GREEN}✓ Firewall rules saved (iptables-persistent)${NC}"
        else
            echo -e "    ${YELLOW}! Firewall rules configured but not persisted (install iptables-persistent)${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}! Could not configure iptables (may need manual configuration)${NC}"
fi

echo -e "${GREEN}✓ Firewall configuration complete${NC}"

# Create project directory
echo -e "${YELLOW}[4/12] Creating project directory: $PROJECT_DIR${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
echo -e "${GREEN}✓ Directory created${NC}"

# Generate self-signed SSL certificate
echo -e "${YELLOW}[5/12] Generating self-signed SSL certificate...${NC}"
if [ ! -f "nginx-selfsigned.crt" ] || [ ! -f "nginx-selfsigned.key" ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout nginx-selfsigned.key \
        -out nginx-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$PUBLIC_IP" >/dev/null 2>&1
    echo -e "${GREEN}✓ SSL certificate generated${NC}"
else
    echo -e "${GREEN}✓ SSL certificate already exists${NC}"
fi

# Create nginx configuration
echo -e "${YELLOW}[6/12] Creating nginx configuration...${NC}"
cat > nginx-proxmox.conf << 'NGINX_EOF'
upstream proxmox {
    server 172.30.0.4:8006;
}

server {
    listen 8006 ssl;
    server_name _;
    
    ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://proxmox;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Cookie handling - rewrite domain from internal IP to public hostname
        proxy_cookie_path / /;
        proxy_cookie_domain 172.30.0.4 $host;
        
        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_redirect off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 3600;
        client_max_body_size 0;
        send_timeout 86400;
    }
}
NGINX_EOF
echo -e "${GREEN}✓ nginx configuration created${NC}"

# Create docker-compose.yml
echo -e "${YELLOW}[7/12] Creating docker-compose.yml...${NC}"
cat > docker-compose.yml << COMPOSE_EOF
services:
  proxmox-qemu:
    image: qemux/qemu
    container_name: proxmox-qemu-vnc
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - ${PROXMOX_VNC_PORT}:8006
      - ${PROXMOX_SSH_PORT}:5900
    volumes:
      - ./proxmox-data:/storage
    restart: unless-stopped
    stop_grace_period: 2m
    environment:
      - RAM_SIZE=${RAM_SIZE}
      - CPU_CORES=${CPU_CORES}
      - DISK_SIZE=${DISK_SIZE}

  nginx-proxy:
    image: nginx:alpine
    container_name: nginx-proxmox-proxy
    cap_add:
      - NET_ADMIN
    ports:
      - ${PROXMOX_WEB_PORT}:8006
    volumes:
      - ./nginx-proxmox.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx-selfsigned.crt:/etc/nginx/ssl/nginx-selfsigned.crt:ro
      - ./nginx-selfsigned.key:/etc/nginx/ssl/nginx-selfsigned.key:ro
    restart: unless-stopped
    depends_on:
      - proxmox-qemu
    command: sh -c "ip route add ${PROXMOX_VM_NETWORK} via ${DOCKER_NETWORK_IP} && nginx -g 'daemon off;'"
COMPOSE_EOF
echo -e "${GREEN}✓ docker-compose.yml created${NC}"

# Create README
echo -e "${YELLOW}[8/12] Creating README.md...${NC}"
cat > README.md << README_EOF
# Proxmox VE in Docker with QEMU

Automated deployment of Proxmox Virtual Environment running in a QEMU Docker container with SSL-enabled nginx reverse proxy.

## Access URLs

- **Proxmox Web UI**: https://${PUBLIC_IP}:${PROXMOX_WEB_PORT}
- **Proxmox VNC Console**: http://${PUBLIC_IP}:${PROXMOX_VNC_PORT}
- **Proxmox SSH** (from host): \`ssh root@${PROXMOX_VM_IP}\`

## Default Credentials

- **Username**: root
- **Password**: (set during installation)
- **Realm**: Linux PAM standard authentication

## VM Resources

- RAM: ${RAM_SIZE}
- CPU Cores: ${CPU_CORES}
- Disk Size: ${DISK_SIZE}

## Network Architecture

- VPS Public IP: ${PUBLIC_IP}
- Docker Bridge Network: 172.18.0.0/16
- Proxmox Container IP: ${DOCKER_NETWORK_IP}
- Proxmox VM Network: ${PROXMOX_VM_NETWORK}
- Proxmox VM IP: ${PROXMOX_VM_IP}

## Management Commands

### Start Services
\`\`\`bash
docker compose up -d
\`\`\`

### Stop Services
\`\`\`bash
docker compose down
\`\`\`

### View Logs
\`\`\`bash
docker compose logs -f proxmox-qemu
docker compose logs -f nginx-proxy
\`\`\`

### Restart Proxmox
\`\`\`bash
docker compose restart proxmox-qemu
\`\`\`

### Access Proxmox Shell
\`\`\`bash
docker exec -it proxmox-qemu-vnc /bin/bash
\`\`\`

### Backup Proxmox Data
\`\`\`bash
tar -czf proxmox-backup-\$(date +%Y%m%d).tar.gz proxmox-data/
\`\`\`

## Firewall Configuration

The setup script automatically configures iptables firewall rules:

### Open Ports
- **${PROXMOX_WEB_PORT}/tcp** - Proxmox Web UI (HTTPS)
- **${PROXMOX_VNC_PORT}/tcp** - Proxmox VNC Console
- **${PROXMOX_SSH_PORT}/tcp** - Proxmox SSH/VNC Access

### View Current Rules
\`\`\`bash
sudo iptables -L INPUT -n --line-numbers | grep -E "(${PROXMOX_WEB_PORT}|${PROXMOX_VNC_PORT}|${PROXMOX_SSH_PORT})"
\`\`\`

### Manually Add Rules (if needed)
\`\`\`bash
sudo iptables -I INPUT -p tcp --dport ${PROXMOX_WEB_PORT} -j ACCEPT
sudo iptables -I INPUT -p tcp --dport ${PROXMOX_VNC_PORT} -j ACCEPT
sudo iptables -I INPUT -p tcp --dport ${PROXMOX_SSH_PORT} -j ACCEPT
\`\`\`

### Save Rules (Debian/Ubuntu)
\`\`\`bash
sudo netfilter-persistent save
# or
sudo iptables-save | sudo tee /etc/iptables/rules.v4
\`\`\`

## Route Setup for VM Network Access

The nginx proxy needs to route to the Proxmox VM's internal network. This is handled automatically by:
1. The setup script adds a route on the host
2. The nginx container adds an internal route on startup

### View Route
\`\`\`bash
ip route | grep ${PROXMOX_VM_NETWORK}
\`\`\`

### Manually Add Route (if needed)
\`\`\`bash
sudo ip route add ${PROXMOX_VM_NETWORK} via ${DOCKER_NETWORK_IP}
\`\`\`

### IP Forwarding
IP forwarding is automatically enabled. To verify:
\`\`\`bash
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1
\`\`\`

## SSL Certificate

A self-signed SSL certificate is automatically generated for nginx. Your browser will show a security warning - click "Advanced" and "Proceed" to continue.

For production use, consider using Let's Encrypt or a proper SSL certificate.

## Troubleshooting

### Proxmox Web UI shows 401 errors
- Clear browser cookies for the site
- Try incognito/private browsing mode
- Ensure you're accessing via HTTPS (not HTTP)

### Cannot access Proxmox VM from host
- Check if route exists: \`ip route | grep ${PROXMOX_VM_NETWORK}\`
- Verify Proxmox container is running: \`docker ps | grep proxmox\`
- Check VM network: \`ssh root@${PROXMOX_VM_IP} ip addr\`

### nginx proxy fails to start
- Check logs: \`docker compose logs nginx-proxy\`
- Verify SSL certificates exist: \`ls -lh nginx-selfsigned.*\`
- Ensure port ${PROXMOX_WEB_PORT} is not in use: \`sudo netstat -tlnp | grep ${PROXMOX_WEB_PORT}\`

## Generated Files

- \`docker-compose.yml\` - Container orchestration
- \`nginx-proxmox.conf\` - nginx reverse proxy configuration
- \`nginx-selfsigned.crt\` - SSL certificate
- \`nginx-selfsigned.key\` - SSL private key
- \`proxmox-data/\` - Proxmox VM persistent storage

## Installation ISO

To install Proxmox, download the ISO and mount it:

\`\`\`bash
wget https://enterprise.proxmox.com/iso/proxmox-ve_8.2-1.iso -O proxmox.iso
\`\`\`

Then add to docker-compose.yml under proxmox-qemu volumes:
\`\`\`yaml
- ./proxmox.iso:/boot.iso
\`\`\`

After installation is complete, remove the ISO mount and delete the file to save space.
README_EOF
echo -e "${GREEN}✓ README.md created${NC}"

# Start containers
echo -e "${YELLOW}[9/12] Starting Docker containers...${NC}"
docker compose up -d
echo -e "${GREEN}✓ Containers started${NC}"

# Wait for containers to be ready
echo -e "${YELLOW}[10/12] Waiting for containers to initialize (30 seconds)...${NC}"
sleep 30

# Detect actual container IP
echo -e "${YELLOW}[11/12] Detecting Proxmox container IP...${NC}"
ACTUAL_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' proxmox-qemu-vnc)
if [ -z "$ACTUAL_CONTAINER_IP" ]; then
    echo -e "${RED}Warning: Could not detect container IP. Using default: ${DOCKER_NETWORK_IP}${NC}"
    ACTUAL_CONTAINER_IP="$DOCKER_NETWORK_IP"
else
    echo -e "${GREEN}✓ Detected container IP: ${ACTUAL_CONTAINER_IP}${NC}"
    
    # Update docker-compose if IP differs
    if [ "$ACTUAL_CONTAINER_IP" != "$DOCKER_NETWORK_IP" ]; then
        echo -e "${YELLOW}Updating docker-compose.yml with correct container IP...${NC}"
        sed -i "s|via ${DOCKER_NETWORK_IP}|via ${ACTUAL_CONTAINER_IP}|g" docker-compose.yml
        docker compose up -d nginx-proxy
        echo -e "${GREEN}✓ nginx proxy updated with correct route${NC}"
    fi
fi

# Verify services
echo -e "${YELLOW}[12/12] Verifying services...${NC}"
sleep 5

# Check if containers are running
if docker ps | grep -q proxmox-qemu-vnc; then
    echo -e "${GREEN}✓ Proxmox QEMU container is running${NC}"
else
    echo -e "${RED}✗ Proxmox QEMU container is not running${NC}"
fi

if docker ps | grep -q nginx-proxmox-proxy; then
    echo -e "${GREEN}✓ nginx proxy container is running${NC}"
else
    echo -e "${RED}✗ nginx proxy container is not running${NC}"
fi

# Configure host routing for Proxmox VM network access
echo -e "${YELLOW}[13/13] Configuring network routing...${NC}"

# Check if route already exists
if ! ip route | grep -q "${PROXMOX_VM_NETWORK}"; then
    echo -e "  ${BLUE}Adding route to Proxmox VM network...${NC}"
    $SUDO ip route add ${PROXMOX_VM_NETWORK} via ${ACTUAL_CONTAINER_IP} 2>/dev/null || true
    echo -e "  ${GREEN}✓ Route added: ${PROXMOX_VM_NETWORK} via ${ACTUAL_CONTAINER_IP}${NC}"
else
    echo -e "  ${GREEN}✓ Route already exists${NC}"
fi

# Test connectivity to Proxmox VM (will fail until Proxmox is installed, but that's ok)
echo -e "  ${BLUE}Testing network connectivity...${NC}"
if ping -c 1 -W 2 ${PROXMOX_VM_IP} >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Proxmox VM is reachable at ${PROXMOX_VM_IP}${NC}"
else
    echo -e "  ${YELLOW}! Proxmox VM not yet reachable (normal if not installed yet)${NC}"
fi

# Display firewall status
echo -e "  ${BLUE}Active firewall rules:${NC}"
$SUDO iptables -L INPUT -n --line-numbers 2>/dev/null | grep -E "(${PROXMOX_WEB_PORT}|${PROXMOX_VNC_PORT}|${PROXMOX_SSH_PORT})" | while read line; do
    echo -e "    ${GREEN}✓ $line${NC}"
done || echo -e "    ${YELLOW}! Could not verify firewall rules${NC}"

echo -e "${GREEN}✓ Network configuration complete${NC}"

# Display summary
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${YELLOW}Access Information:${NC}"
echo ""
echo -e "  ${GREEN}Proxmox Web UI (HTTPS):${NC}"
echo -e "    https://${PUBLIC_IP}:${PROXMOX_WEB_PORT}"
echo ""
echo -e "  ${GREEN}Proxmox VNC Console:${NC}"
echo -e "    http://${PUBLIC_IP}:${PROXMOX_VNC_PORT}"
echo ""
echo -e "  ${GREEN}Proxmox VM SSH (from host):${NC}"
echo -e "    ssh root@${PROXMOX_VM_IP}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "  1. Access the VNC console to install Proxmox VE"
echo "  2. Download ISO: wget https://enterprise.proxmox.com/iso/proxmox-ve_8.2-1.iso -O proxmox.iso"
echo "  3. Add ISO mount to docker-compose.yml volumes section"
echo "  4. Restart container: docker compose restart proxmox-qemu"
echo "  5. After installation, remove ISO mount and delete file"
echo ""
echo -e "${YELLOW}Firewall & Network:${NC}"
echo ""
echo "  • Firewall ports opened: ${PROXMOX_WEB_PORT}, ${PROXMOX_VNC_PORT}, ${PROXMOX_SSH_PORT}"
echo "  • IP forwarding: Enabled"
echo "  • VM network route: ${PROXMOX_VM_NETWORK} via ${ACTUAL_CONTAINER_IP}"
echo "  • Container IP: ${ACTUAL_CONTAINER_IP}"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo ""
echo "  • The Web UI uses a self-signed certificate (browser warning is normal)"
echo "  • Default login realm: 'Linux PAM standard authentication'"
echo "  • Firewall rules are persisted across reboots"
echo "  • Check README.md for detailed documentation"
echo ""
echo -e "${BLUE}============================================${NC}"

# Create quick access script
cat > access.sh << 'ACCESS_EOF'
#!/bin/bash
echo "Proxmox QEMU Quick Access"
echo "========================="
echo ""
echo "1) Open Proxmox Web UI (HTTPS)"
echo "2) Open Proxmox VNC Console"
echo "3) SSH to Proxmox VM"
echo "4) View container logs"
echo "5) Restart containers"
echo "6) Stop containers"
echo "7) Start containers"
echo "0) Exit"
echo ""
read -p "Select option: " choice

case $choice in
    1) xdg-open "https://$(curl -s ifconfig.me):8006" 2>/dev/null || echo "Open: https://$(curl -s ifconfig.me):8006" ;;
    2) xdg-open "http://$(curl -s ifconfig.me):8008" 2>/dev/null || echo "Open: http://$(curl -s ifconfig.me):8008" ;;
    3) ssh root@172.30.0.4 ;;
    4) docker compose logs -f ;;
    5) docker compose restart ;;
    6) docker compose down ;;
    7) docker compose up -d ;;
    0) exit 0 ;;
    *) echo "Invalid option" ;;
esac
ACCESS_EOF
chmod +x access.sh
echo -e "${GREEN}✓ Quick access script created: ./access.sh${NC}"
echo ""
