#!/bin/bash
set -euo pipefail

# ============================================================================
# Logging Setup
# ============================================================================

LOG_FILE="/var/log/harbor-jenkins-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log_timestamp() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_info() {
  log_timestamp "INFO: $*"
}

log_success() {
  log_timestamp "SUCCESS: $*"
}

log_error() {
  log_timestamp "ERROR: $*"
}

log_separator() {
  log_timestamp "========================================"
}

log_separator
log_info "Starting Jenkins + Harbor installation"
log_info "Log file: $LOG_FILE"
log_separator

handle_error() {
  log_error "Error occurred at line $1"
  exit 1
}

trap 'handle_error $LINENO' ERR

# ============================================================================
# Harbor Configuration
# ============================================================================

PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)

HARBOR_HOSTNAME="${harbor_hostname}"

# fallback to public ip if hostname not provided
if [ -z "$HARBOR_HOSTNAME" ]; then
  HARBOR_HOSTNAME=$PUBLIC_IP
fi

HARBOR_PASSWORD="${harbor_admin_password}"
HARBOR_EMAIL="${harbor_admin_email}"
HARBOR_HTTPS_PORT="${harbor_https_port}"
HARBOR_HTTP_PORT="${harbor_http_port}"

HARBOR_SSL_COUNTRY="${harbor_ssl_cert_country}"
HARBOR_SSL_STATE="${harbor_ssl_cert_state}"
HARBOR_SSL_CITY="${harbor_ssl_cert_city}"
HARBOR_SSL_ORG="${harbor_ssl_cert_organization}"

log_info "Configuration:"
log_info "  Public IP: $PUBLIC_IP"
log_info "  Harbor Hostname: $HARBOR_HOSTNAME"

# ============================================================================
# System Update
# ============================================================================

log_info "Updating apt packages..."
apt update -y

log_info "Installing required packages..."
apt install -y \
  docker.io \
  docker-compose \
  curl \
  wget \
  unzip \
  openssl \
  ca-certificates \
  gnupg \
  lsb-release

log_success "Packages installed"

# ============================================================================
# Docker Setup
# ============================================================================

log_info "Starting Docker..."

systemctl enable docker
systemctl start docker

log_success "Docker started"

# add ubuntu user to docker group
usermod -aG docker ubuntu || true

# ============================================================================
# Jenkins Setup
# ============================================================================

log_separator
log_info "Starting Jenkins container..."

docker rm -f jenkins >/dev/null 2>&1 || true

docker run -d \
  --name jenkins \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -u root \
  jenkins/jenkins:lts

log_success "Jenkins container started"

# wait jenkins
log_info "Waiting for Jenkins startup..."
sleep 120

# install docker cli inside jenkins container
log_info "Installing Docker CLI inside Jenkins..."

docker exec jenkins bash -c "
apt-get update &&
apt-get install -y docker.io
" || true

# test docker access
if docker exec jenkins docker ps >/dev/null 2>&1; then
  log_success "Docker accessible from Jenkins"
else
  log_info "Docker access verification skipped"
fi

# ============================================================================
# SSL Certificates
# ============================================================================

log_separator
log_info "Generating SSL certificates..."

mkdir -p /data/cert

cd /data/cert

openssl genrsa -out ca.key 4096

openssl req -x509 -new -nodes -sha512 -days 3650 \
  -subj "/C=$HARBOR_SSL_COUNTRY/ST=$HARBOR_SSL_STATE/L=$HARBOR_SSL_CITY/O=$HARBOR_SSL_ORG/CN=$HARBOR_HOSTNAME" \
  -key ca.key \
  -out ca.crt

openssl genrsa -out $HARBOR_HOSTNAME.key 4096

openssl req -sha512 -new \
  -subj "/C=$HARBOR_SSL_COUNTRY/ST=$HARBOR_SSL_STATE/L=$HARBOR_SSL_CITY/O=$HARBOR_SSL_ORG/CN=$HARBOR_HOSTNAME" \
  -key $HARBOR_HOSTNAME.key \
  -out $HARBOR_HOSTNAME.csr

cat > v3.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage=serverAuth

subjectAltName=@alt_names

[alt_names]
DNS.1=$HARBOR_HOSTNAME
DNS.2=localhost
EOF

# if hostname is ip
if [[ "$HARBOR_HOSTNAME" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "IP.1=$HARBOR_HOSTNAME" >> v3.ext
fi

openssl x509 -req -sha512 -days 3650 \
  -extfile v3.ext \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -in $HARBOR_HOSTNAME.csr \
  -out $HARBOR_HOSTNAME.crt

openssl x509 -inform PEM \
  -in $HARBOR_HOSTNAME.crt \
  -out $HARBOR_HOSTNAME.cert

log_success "SSL certificates generated"

# ============================================================================
# Docker Certs
# ============================================================================

DOCKER_CERTS_DIR="/etc/docker/certs.d/$HARBOR_HOSTNAME:$HARBOR_HTTPS_PORT"

mkdir -p "$DOCKER_CERTS_DIR"

cp $HARBOR_HOSTNAME.cert "$DOCKER_CERTS_DIR/"
cp $HARBOR_HOSTNAME.key "$DOCKER_CERTS_DIR/"
cp ca.crt "$DOCKER_CERTS_DIR/"

cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker

log_success "Docker certs configured"

# ============================================================================
# Harbor Installation
# ============================================================================

log_separator
log_info "Installing Harbor..."

cd /opt

wget https://github.com/goharbor/harbor/releases/download/v2.8.2/harbor-online-installer-v2.8.2.tgz

tar xzvf harbor-online-installer-v2.8.2.tgz

cd harbor

cp harbor.yml.tmpl harbor.yml

# hostname
sed -i "s/^hostname: .*/hostname: $HARBOR_HOSTNAME/" harbor.yml

# password
sed -i "s/^harbor_admin_password: .*/harbor_admin_password: $HARBOR_PASSWORD/" harbor.yml

# email
sed -i "s/^email_server\.email_from: .*/email_server.email_from: $HARBOR_EMAIL/" harbor.yml

# https config
sed -i 's|port: 443|port: '"$HARBOR_HTTPS_PORT"'|' harbor.yml
sed -i 's|certificate: .*|certificate: /data/cert/'$HARBOR_HOSTNAME'.crt|' harbor.yml
sed -i 's|private_key: .*|private_key: /data/cert/'$HARBOR_HOSTNAME'.key|' harbor.yml

chmod +x install.sh

./install.sh --with-trivy

docker compose up -d

log_success "Harbor installed"

# ============================================================================
# Jenkins CA Certificates
# ============================================================================

log_info "Updating Jenkins CA certificates..."

docker cp /data/cert/ca.crt jenkins:/usr/local/share/ca-certificates/ca.crt || true

docker exec jenkins update-ca-certificates || true

docker restart jenkins || true

# ============================================================================
# Verify Harbor
# ============================================================================

log_separator
log_info "Verifying Harbor..."

sleep 30

if curl -k https://$HARBOR_HOSTNAME:$HARBOR_HTTPS_PORT/api/v2.0/health >/dev/null 2>&1; then
  log_success "Harbor is healthy"
else
  log_info "Harbor health check failed"
fi

# ============================================================================
# SonarQube
# ============================================================================

log_separator
log_info "Starting SonarQube..."

docker rm -f sonarqube >/dev/null 2>&1 || true

docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  sonarqube

log_success "SonarQube started"

# ============================================================================
# Final Output
# ============================================================================

log_separator
log_success "INSTALLATION COMPLETED"

echo ""
echo "========================================"
echo "Jenkins:"
echo "  http://$PUBLIC_IP:8080"
echo ""
echo "Harbor:"
echo "  https://$HARBOR_HOSTNAME:$HARBOR_HTTPS_PORT"
echo ""
echo "SonarQube:"
echo "  http://$PUBLIC_IP:9000"
echo ""
echo "Harbor Username:"
echo "  admin"
echo ""
echo "Harbor Password:"
echo "  $HARBOR_PASSWORD"
echo "========================================"
