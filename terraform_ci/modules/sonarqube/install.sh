#!/bin/bash
set -e

LOG=/var/log/sonar-install.log
exec > >(tee -a $LOG) 2>&1

echo "[INFO] Installing SonarQube..."

apt update -y
apt install -y docker.io curl

systemctl enable docker
systemctl start docker

docker rm -f sonarqube || true

docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  sonarqube:lts

echo "[SUCCESS] SonarQube installed"
echo "URL: http://$(curl -s ifconfig.me):9000"