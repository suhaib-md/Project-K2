#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_status "Fixing certificate distribution and restarting services..."

# Check if certificates exist locally
if [ ! -d "certs" ] || [ ! -f "certs/ca.pem" ]; then
    print_error "Certificates not found locally. Need to regenerate them."
    
    # Create certificates directory and regenerate
    mkdir -p certs
    cd certs
    
    print_status "Regenerating certificates..."
    
    # Generate CA certificate
    cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

    cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF

    # Generate CA
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
    
    # Get controller IP for API server certificate
    CONTROLLER_IP=$(grep "controller-0" ../inventory.ini | awk '{print $3}' | cut -d'=' -f2)
    
    # Generate API server certificate
    cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=10.32.0.1,${CONTROLLER_IP},127.0.0.1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local \
      -profile=kubernetes \
      kubernetes-csr.json | cfssljson -bare kubernetes

    # Generate service account certificate
    cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      service-account-csr.json | cfssljson -bare service-account
    
    cd ..
    print_success "Certificates regenerated"
fi

# Distribute certificates to controller
print_status "Distributing certificates to controller..."

controller_host=$(grep "controller-0" inventory.ini | awk '{print $2}' | cut -d'=' -f2)

print_status "Copying certificates to controller: $controller_host"

# Copy certificates
scp -F ssh_config -o ConnectTimeout=30 "certs/ca.pem" ubuntu@$controller_host:/tmp/
scp -F ssh_config -o ConnectTimeout=30 "certs/ca-key.pem" ubuntu@$controller_host:/tmp/
scp -F ssh_config -o ConnectTimeout=30 "certs/kubernetes-key.pem" ubuntu@$controller_host:/tmp/
scp -F ssh_config -o ConnectTimeout=30 "certs/kubernetes.pem" ubuntu@$controller_host:/tmp/
scp -F ssh_config -o ConnectTimeout=30 "certs/service-account-key.pem" ubuntu@$controller_host:/tmp/
scp -F ssh_config -o ConnectTimeout=30 "certs/service-account.pem" ubuntu@$controller_host:/tmp/

# Generate and copy encryption config
if [ ! -f "encryption-config.yaml" ]; then
    ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
    cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
fi

scp -F ssh_config -o ConnectTimeout=30 "encryption-config.yaml" ubuntu@$controller_host:/tmp/

print_success "Certificates distributed successfully"

# Move certificates to proper locations and restart services
print_status "Moving certificates and restarting services on controller..."

ssh -F ssh_config ubuntu@$controller_host '
    # Stop services first
    sudo systemctl stop kube-apiserver kube-controller-manager kube-scheduler etcd 2>/dev/null || true
    
    # Create directories
    sudo mkdir -p /etc/etcd /var/lib/etcd /var/lib/kubernetes
    
    # Move etcd certificates
    sudo mv /tmp/ca.pem /tmp/kubernetes-key.pem /tmp/kubernetes.pem /etc/etcd/
    sudo chown etcd:etcd /etc/etcd/* 2>/dev/null || true
    
    # Copy certificates for kubernetes
    sudo cp /etc/etcd/ca.pem /etc/etcd/kubernetes-key.pem /etc/etcd/kubernetes.pem /var/lib/kubernetes/
    sudo mv /tmp/ca-key.pem /tmp/service-account-key.pem /tmp/service-account.pem /var/lib/kubernetes/
    sudo mv /tmp/encryption-config.yaml /var/lib/kubernetes/
    
    # Start etcd first
    sudo systemctl start etcd
    sleep 10
    
    # Start kubernetes services
    sudo systemctl start kube-apiserver
    sleep 10
    sudo systemctl start kube-controller-manager
    sudo systemctl start kube-scheduler
    
    # Check status
    echo "=== Service Status ==="
    sudo systemctl is-active etcd
    sudo systemctl is-active kube-apiserver  
    sudo systemctl is-active kube-controller-manager
    sudo systemctl is-active kube-scheduler
    
    echo "=== Listening Ports ==="
    netstat -tlnp | grep -E ":6443|:2379|:2380"
'

print_success "Services restarted"

# Test API server connectivity
print_status "Testing API server connectivity..."
sleep 20

controller_ip=$(grep "controller-0" inventory.ini | awk '{print $3}' | cut -d'=' -f2)

if curl -k https://${controller_ip}:6443/version 2>/dev/null; then
    print_success "API server is responding!"
else
    print_error "API server is still not responding. Checking logs..."
    ssh -F ssh_config ubuntu@$controller_host 'sudo journalctl -u kube-apiserver --since "2 minutes ago" --no-pager'
fi

print_status "Certificate distribution and service restart completed"
