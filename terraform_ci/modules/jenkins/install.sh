#!/bin/bash
set -e

LOG=/var/log/jenkins-install.log
exec > >(tee -a $LOG) 2>&1

echo "[INFO] Installing Jenkins..."

apt update -y
apt install -y docker.io curl git

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu || true

# Jenkins container
docker rm -f jenkins || true

docker run -d \
  --name jenkins \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -u root \
  jenkins/jenkins:lts

echo "[SUCCESS] Jenkins installed"
echo "URL: http://$(curl -s ifconfig.me):8080"