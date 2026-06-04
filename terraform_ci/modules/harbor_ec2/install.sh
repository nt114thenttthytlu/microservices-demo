#!/bin/bash
set -e

LOG=/var/log/harbor-install.log
exec > >(tee -a "$LOG") 2>&1

echo "[INFO] Installing Harbor..."

# Harbor admin password (default: ChangeMe123!)

HARBOR_PASSWORD=${HARBOR_PASSWORD:-ChangeMe123!}

# Domain or public ip

DOMAIN=${DOMAIN:-$(curl -s ifconfig.me)}

apt update -y
apt install -y docker.io docker-compose curl wget

systemctl enable docker
systemctl start docker

cd /opt

if [ ! -f harbor-online-installer-v2.8.2.tgz ]; then
wget https://github.com/goharbor/harbor/releases/download/v2.8.2/harbor-online-installer-v2.8.2.tgz
fi

tar xzvf harbor-online-installer-v2.8.2.tgz

cd harbor

cp harbor.yml.tmpl harbor.yml

# Configure hostname

sed -i "s/^hostname:.*/hostname: ${DOMAIN}/" harbor.yml

# Configure Harbor admin password

sed -i "s/^harbor_admin_password:.*/harbor_admin_password: ${HARBOR_PASSWORD}/" harbor.yml

# Disable HTTPS section

sed -i '/^https:/,/^  private_key:/s/^/#/' harbor.yml

# Ensure HTTP enabled

sed -i 's/^#http:/http:/' harbor.yml
sed -i 's/^#  port: 80/  port: 80/' harbor.yml

./install.sh

echo ""
echo "[SUCCESS] Harbor installed"
echo "URL: http://${DOMAIN}"
echo "Username: admin"
echo "Password: ${HARBOR_PASSWORD}"
