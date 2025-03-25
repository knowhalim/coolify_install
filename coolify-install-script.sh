#!/bin/bash

# Coolify Installation Script for Ubuntu
# This script checks prerequisites, creates directories, and installs Coolify in a clean manner
# Works alongside existing services like Directus, Appsmith, and Buildbase

# Set terminal colors for better visibility
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}       Coolify Installation Script        ${NC}"
echo -e "${GREEN}===========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root or with sudo${NC}"
  exit 1
fi

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Check for Docker
if ! command_exists docker; then
  echo -e "${RED}Docker is not installed. Installing Docker...${NC}"
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
  echo -e "${GREEN}Docker installed successfully.${NC}"
else
  echo -e "${GREEN}Docker is already installed.${NC}"
fi

# Check for Docker Compose
if ! command_exists docker-compose; then
  echo -e "${RED}Docker Compose is not installed. Installing Docker Compose...${NC}"
  curl -L "https://github.com/docker/compose/releases/download/v2.18.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  echo -e "${GREEN}Docker Compose installed successfully.${NC}"
else
  echo -e "${GREEN}Docker Compose is already installed.${NC}"
fi

# Create directory for Coolify
echo -e "\n${YELLOW}Setting up Coolify directories...${NC}"
COOLIFY_DIR="/opt/coolify"

if [ -d "$COOLIFY_DIR" ]; then
  echo -e "${YELLOW}Coolify directory already exists. Creating backup...${NC}"
  BACKUP_DIR="${COOLIFY_DIR}_backup_$(date +%Y%m%d%H%M%S)"
  mv "$COOLIFY_DIR" "$BACKUP_DIR"
  echo -e "${GREEN}Backup created at $BACKUP_DIR${NC}"
fi

mkdir -p "$COOLIFY_DIR"
cd "$COOLIFY_DIR"

# Create a docker network for Coolify if it doesn't exist
echo -e "\n${YELLOW}Setting up Docker network...${NC}"
if ! docker network inspect coolify >/dev/null 2>&1; then
  docker network create coolify
  echo -e "${GREEN}Created Docker network: coolify${NC}"
else
  echo -e "${GREEN}Docker network 'coolify' already exists.${NC}"
fi

# Create docker-compose.yml for Coolify
echo -e "\n${YELLOW}Creating docker-compose configuration...${NC}"
cat > "$COOLIFY_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  coolify:
    image: coollabsio/coolify:latest
    container_name: coolify
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - coolify-db:/app/db
      - coolify-logs:/app/logs
      - coolify-backups:/app/backups
      - coolify-ssl:/app/ssl
    ports:
      - "8000:8000"
    networks:
      - coolify
    environment:
      - COOLIFY_DATABASE_URL=file:/app/db/prod.db
      - COOLIFY_APP_ID=unique-app-id-for-this-instance
      - COOLIFY_SECRET_KEY=your-secret-key-change-this
      - COOLIFY_HOSTED=false
      - COOLIFY_WHITE_LABELED=false
      - COOLIFY_WHITE_LABELED_ICON=
      - COOLIFY_USE_HTTPS=false

networks:
  coolify:
    external: true

volumes:
  coolify-db:
  coolify-logs:
  coolify-backups:
  coolify-ssl:
EOF

# Generate random strings for security
RANDOM_APP_ID=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
RANDOM_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)

# Update the docker-compose.yml with generated values
sed -i "s/unique-app-id-for-this-instance/$RANDOM_APP_ID/" "$COOLIFY_DIR/docker-compose.yml"
sed -i "s/your-secret-key-change-this/$RANDOM_SECRET_KEY/" "$COOLIFY_DIR/docker-compose.yml"

# Create a Coolify service file
echo -e "\n${YELLOW}Creating systemd service for Coolify...${NC}"
cat > /etc/systemd/system/coolify.service << EOF
[Unit]
Description=Coolify Service
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=$COOLIFY_DIR
ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0
Restart=on-failure
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
systemctl daemon-reload
systemctl enable coolify.service

# Start Coolify
echo -e "\n${YELLOW}Starting Coolify...${NC}"
systemctl start coolify.service

# Create a helper script for management
cat > "$COOLIFY_DIR/manage-coolify.sh" << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

case "$1" in
  start)
    echo -e "${GREEN}Starting Coolify...${NC}"
    systemctl start coolify.service
    ;;
  stop)
    echo -e "${YELLOW}Stopping Coolify...${NC}"
    systemctl stop coolify.service
    ;;
  restart)
    echo -e "${YELLOW}Restarting Coolify...${NC}"
    systemctl restart coolify.service
    ;;
  status)
    echo -e "${GREEN}Coolify Status:${NC}"
    systemctl status coolify.service
    ;;
  logs)
    echo -e "${GREEN}Coolify Logs:${NC}"
    docker logs coolify
    ;;
  update)
    echo -e "${YELLOW}Updating Coolify...${NC}"
    cd /opt/coolify
    docker-compose pull
    docker-compose down
    docker-compose up -d
    ;;
  *)
    echo -e "Usage: $0 {start|stop|restart|status|logs|update}"
    exit 1
    ;;
esac
EOF

chmod +x "$COOLIFY_DIR/manage-coolify.sh"

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}Coolify installation completed!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "\n${YELLOW}Installation Details:${NC}"
echo -e "  - Installation Directory: ${GREEN}$COOLIFY_DIR${NC}"
echo -e "  - Web Interface: ${GREEN}http://your-server-ip:8000${NC}"
echo -e "  - Management Script: ${GREEN}$COOLIFY_DIR/manage-coolify.sh${NC}"
echo -e "\n${YELLOW}Management Commands:${NC}"
echo -e "  - Start: ${GREEN}systemctl start coolify.service${NC}"
echo -e "  - Stop: ${GREEN}systemctl stop coolify.service${NC}"
echo -e "  - Check Status: ${GREEN}systemctl status coolify.service${NC}"
echo -e "  - View Logs: ${GREEN}docker logs coolify${NC}"
echo -e "  - Quick management: ${GREEN}$COOLIFY_DIR/manage-coolify.sh {start|stop|restart|status|logs|update}${NC}"
echo -e "\n${YELLOW}Note:${NC} You may need to configure your firewall to allow access to port 8000"
