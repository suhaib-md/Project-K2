#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Kubernetes The Hard Way Setup...${NC}"

# Set variables
KUBERNETES_VERSION="v1.28.3"
ETCD_VERSION="v3.5.10"
CNI_VERSION=v1.1.0
CONTAINERD_VERSION=1.7.3
CRICTL_VERSION=v1.28.0
KUBELET_VERSION=v1.28.3

KUBERNETES_PUBLIC_ADDRESS="${LB_DNS}"

# Function to print status
print_status() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Wait for instances to be ready
print_status "Waiting for instances to be ready..."
sleep 60

# Function to run command on all controllers
run_on_controllers() {
    local cmd="$1"
    while IFS= read -r line; do
        if [[ $line =~ ^controller- ]]; then
            host=$(echo $line | cut -d' ' -f1)  # Changed to extract name (e.g., controller-0)
            print_status "Running on controller: $host"
            ssh -F ssh_config -o ConnectTimeout=30 -o StrictHostKeyChecking=no $host "$cmd" || {
                print_error "Failed to execute on $host"
                return 1
            }
        fi
    done < inventory.ini
}

# Function to run command on all workers
run_on_workers() {
    local cmd="$1"
    while IFS= read -r line; do
        if [[ $line =~ ^worker- ]]; then
            host=$(echo $line | cut -d' ' -f1)  # Changed to extract name (e.g., worker-0)
            print_status "Running on worker: $host"
            ssh -F ssh_config -o ConnectTimeout=30 -o StrictHostKeyChecking=no $host "$cmd" || {
                print_error "Failed to execute on $host"
                return 1
            }
        fi
    done < inventory.ini
}

# Create certificates directory
mkdir -p certs
cd certs

print_status "Step 1: Generating certificates and keys..."

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

# Install cfssl if not exists
if ! command -v cfssl &> /dev/null; then
    print_status "Installing cfssl..."
    curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64
    curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64
    chmod +x cfssl cfssljson
    sudo mv cfssl cfssljson /usr/local/bin/
fi

# Generate CA
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# Generate admin client certificate
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
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
  admin-csr.json | cfssljson -bare admin

# Generate worker certificates
while IFS= read -r line; do
    if [[ $line =~ ^worker- ]]; then
        worker_name=$(echo $line | cut -d' ' -f1)
        worker_ip=$(echo $line | cut -d' ' -f3 | cut -d'=' -f2)
        
        cat > ${worker_name}-csr.json <<EOF
{
  "CN": "system:node:${worker_name}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
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
          -hostname=${worker_name},${worker_ip} \
          -profile=kubernetes \
          ${worker_name}-csr.json | cfssljson -bare ${worker_name}
    fi
done < ../inventory.ini

# Generate kube-controller-manager certificate
cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-controller-manager",
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
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

# Generate kube-proxy certificate
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
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
  kube-proxy-csr.json | cfssljson -bare kube-proxy

# Generate kube-scheduler certificate
cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-scheduler",
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
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

# Generate API server certificate
KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local

# Get controller IPs
CONTROLLER_IPS=""
while IFS= read -r line; do
    if [[ $line =~ ^controller- ]]; then
        controller_ip=$(echo $line | cut -d' ' -f3 | cut -d'=' -f2)
        CONTROLLER_IPS="${CONTROLLER_IPS},${controller_ip}"
    fi
done < ../inventory.ini

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
  -hostname=10.32.0.1${CONTROLLER_IPS},${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,${KUBERNETES_HOSTNAMES} \
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

print_success "Certificates generated successfully!"

print_status "Step 2: Generating kubeconfig files..."

# Install kubectl if not exists
if ! command -v kubectl &> /dev/null; then
    print_status "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

mkdir -p kubeconfigs

# Generate worker kubeconfigs
while IFS= read -r line; do
    if [[ $line =~ ^worker- ]]; then
        worker_name=$(echo $line | cut -d' ' -f1)
        
        kubectl config set-cluster kubernetes-the-hard-way \
          --certificate-authority=certs/ca.pem \
          --embed-certs=true \
          --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
          --kubeconfig=kubeconfigs/${worker_name}.kubeconfig

        kubectl config set-credentials system:node:${worker_name} \
          --client-certificate=certs/${worker_name}.pem \
          --client-key=certs/${worker_name}-key.pem \
          --embed-certs=true \
          --kubeconfig=kubeconfigs/${worker_name}.kubeconfig

        kubectl config set-context default \
          --cluster=kubernetes-the-hard-way \
          --user=system:node:${worker_name} \
          --kubeconfig=kubeconfigs/${worker_name}.kubeconfig

        kubectl config use-context default --kubeconfig=kubeconfigs/${worker_name}.kubeconfig
    fi
done < inventory.ini

# Generate kube-proxy kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=certs/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=kubeconfigs/kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=certs/kube-proxy.pem \
  --client-key=certs/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kubeconfigs/kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=kubeconfigs/kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kubeconfigs/kube-proxy.kubeconfig

# Generate kube-controller-manager kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=certs/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kubeconfigs/kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=certs/kube-controller-manager.pem \
  --client-key=certs/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kubeconfigs/kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=kubeconfigs/kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=kubeconfigs/kube-controller-manager.kubeconfig

# Generate kube-scheduler kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=certs/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kubeconfigs/kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=certs/kube-scheduler.pem \
  --client-key=certs/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kubeconfigs/kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=kubeconfigs/kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kubeconfigs/kube-scheduler.kubeconfig

# Generate admin kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=certs/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kubeconfigs/admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=certs/admin.pem \
  --client-key=certs/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubeconfigs/admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=kubeconfigs/admin.kubeconfig

kubectl config use-context default --kubeconfig=kubeconfigs/admin.kubeconfig

print_success "Kubeconfig files generated successfully!"

print_status "Step 3: Generating data encryption config..."

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

print_success "Encryption config generated successfully!"

print_status "Step 4: Distributing certificates and configs to nodes..."

# First, create necessary directories on all nodes and setup etcd user
print_status "Setting up directories and users on controllers..."
run_on_controllers "
    sudo mkdir -p /var/lib/kubernetes/ /etc/etcd/ /var/lib/etcd/
    sudo groupadd -f etcd || true
    sudo useradd -c 'etcd user' -d /var/lib/etcd -s /bin/false -g etcd -r etcd 2>/dev/null || true
    sudo chown etcd:etcd /var/lib/etcd
    sudo chmod 755 /etc/etcd /var/lib/etcd
"

print_status "Setting up directories on workers..."
run_on_workers "sudo mkdir -p /var/lib/kubelet/ /var/lib/kube-proxy/ /var/lib/kubernetes/"

# Copy certificates to controllers
while IFS= read -r line; do
    if [[ $line =~ ^controller- ]]; then
        controller_host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
        
        print_status "Copying certificates to controller: $controller_host"
        
        # Copy to /tmp first
        scp -F ssh_config -o StrictHostKeyChecking=no certs/ca.pem ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/ca-key.pem ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/kubernetes-key.pem ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/kubernetes.pem ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/service-account-key.pem ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/service-account.pem ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no kubeconfigs/admin.kubeconfig ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no kubeconfigs/kube-controller-manager.kubeconfig ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no kubeconfigs/kube-scheduler.kubeconfig ubuntu@$controller_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no encryption-config.yaml ubuntu@$controller_host:/tmp/
        
        # FIXED: Copy certificates to proper locations with correct ownership
        ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$controller_host "
            # Copy for etcd (with etcd ownership) - ensure etcd user exists first
            if id etcd >/dev/null 2>&1; then
                sudo cp /tmp/ca.pem /tmp/kubernetes-key.pem /tmp/kubernetes.pem /etc/etcd/
                sudo chown etcd:etcd /etc/etcd/*.pem
                sudo chmod 600 /etc/etcd/*-key.pem
                echo 'Certificates copied to /etc/etcd/ with etcd ownership'
            else
                echo 'ERROR: etcd user not found!'
                exit 1
            fi
            
            # Copy for kubernetes API server (all required certificates)
            sudo cp /tmp/ca.pem /tmp/ca-key.pem /tmp/kubernetes.pem /tmp/kubernetes-key.pem /var/lib/kubernetes/
            sudo cp /tmp/service-account.pem /tmp/service-account-key.pem /var/lib/kubernetes/
            sudo cp /tmp/encryption-config.yaml /var/lib/kubernetes/
            sudo cp /tmp/admin.kubeconfig /tmp/kube-controller-manager.kubeconfig /tmp/kube-scheduler.kubeconfig /var/lib/kubernetes/
            
            # Set proper permissions
            sudo chown root:root /var/lib/kubernetes/*
            sudo chmod 600 /var/lib/kubernetes/*-key.pem
            sudo chmod 644 /var/lib/kubernetes/*.pem /var/lib/kubernetes/*.kubeconfig /var/lib/kubernetes/*.yaml
            
            echo 'Certificates copied to /var/lib/kubernetes/ with root ownership'
            echo 'Listing /etc/etcd contents:'
            ls -la /etc/etcd/
            echo 'Listing /var/lib/kubernetes contents:'
            ls -la /var/lib/kubernetes/
        "
    fi
done < inventory.ini

# Copy certificates to workers
while IFS= read -r line; do
    if [[ $line =~ ^worker- ]]; then
        worker_name=$(echo $line | cut -d' ' -f1)
        worker_host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
        
        print_status "Copying certificates to worker: $worker_host"
        scp -F ssh_config -o StrictHostKeyChecking=no certs/ca.pem ubuntu@$worker_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/${worker_name}-key.pem ubuntu@$worker_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no certs/${worker_name}.pem ubuntu@$worker_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no kubeconfigs/${worker_name}.kubeconfig ubuntu@$worker_host:/tmp/
        scp -F ssh_config -o StrictHostKeyChecking=no kubeconfigs/kube-proxy.kubeconfig ubuntu@$worker_host:/tmp/
        
        # Move certificates to proper locations on workers and set permissions
        ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$worker_host "
            # Move files to their final destinations
            sudo mv /tmp/ca.pem /var/lib/kubernetes/ca.pem
            sudo mv /tmp/${worker_name}-key.pem /var/lib/kubelet/${worker_name}-key.pem
            sudo mv /tmp/${worker_name}.pem /var/lib/kubelet/${worker_name}.pem
            sudo mv /tmp/${worker_name}.kubeconfig /var/lib/kubelet/kubeconfig
            sudo mv /tmp/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
            
            # Set ownership for the directories
            sudo chown -R root:root /var/lib/kubernetes/ /var/lib/kubelet/ /var/lib/kube-proxy/
            
            # Set specific file permissions
            sudo chmod 600 /var/lib/kubelet/${worker_name}-key.pem
            sudo chmod 644 /var/lib/kubelet/${worker_name}.pem
            sudo chmod 644 /var/lib/kubernetes/ca.pem
            sudo chmod 644 /var/lib/kubelet/kubeconfig
            sudo chmod 644 /var/lib/kube-proxy/kubeconfig
        "
    fi
done < inventory.ini

print_success "Certificates and configs distributed successfully!"

# Step 5: Setting up etcd cluster on controllers
print_status "Step 5: Setting up etcd cluster on controllers..."

# Wait longer after certificate copying to ensure instance stability
print_status "Waiting for controller instance to stabilize after certificate copying..."
sleep 60

# Pre-check SSH connectivity
run_on_controllers "
    echo 'Checking SSH responsiveness and system status...'
    uptime
    sudo systemctl status ssh --no-pager
    if ! sudo systemctl is-active --quiet ssh; then
        echo 'ERROR: SSH daemon is not active'
        exit 1
    fi
    echo 'SSH daemon is active'
" || {
    print_error "SSH pre-check failed on controller-0"
    exit 1
}

# Wait for Cloud-Init to complete on controllers
run_on_controllers "
    echo 'Waiting for Cloud-Init to complete...'
    for i in {1..30}; do
        if [ -f /tmp/cloud-init-complete ]; then
            echo 'Cloud-Init completed'
            break
        fi
        echo 'Waiting for Cloud-Init... (attempt $i/30)'
        sleep 10
    done
    if [ ! -f /tmp/cloud-init-complete ]; then
        echo 'ERROR: Cloud-Init did not complete in time'
        exit 1
    fi
    echo 'Checking system load...'
    uptime
    free -m
" || {
    print_error "Cloud-Init check failed on controller-0"
    exit 1
}

# Install and configure etcd with retries
run_on_controllers "
    set -e
    echo 'Installing etcd...'
    wget -q --show-progress --https-only --timestamping \
        \"https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz\"
    tar -xzf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
    sudo mv etcd-${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/
    rm -rf etcd-${ETCD_VERSION}-linux-amd64*
    
    echo 'Creating etcd systemd unit...'
    sudo mkdir -p /var/lib/etcd /etc/etcd
    sudo chown etcd:etcd /var/lib/etcd
    
    # Get private IP for etcd configuration
    TOKEN=\$(curl -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\")
    PRIVATE_IP=\$(curl -H \"X-aws-ec2-metadata-token: \$TOKEN\" -s http://169.254.169.254/latest/meta-data/local-ipv4)
    
    sudo tee /etc/systemd/system/etcd.service > /dev/null <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
User=etcd
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name \${HOSTNAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://\${PRIVATE_IP}:2380 \\
  --listen-peer-urls https://\${PRIVATE_IP}:2380 \\
  --listen-client-urls https://\${PRIVATE_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://\${PRIVATE_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster \${HOSTNAME}=https://\${PRIVATE_IP}:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd \\
  --wal-dir=/var/lib/etcd/wal \\
  --snapshot-count=10000 \\
  --heartbeat-interval=100 \\
  --election-timeout=1000 \\
  --max-snapshots=5 \\
  --max-wals=5 \\
  --cors=*
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    echo 'Starting etcd service...'
    sudo systemctl daemon-reload
    sudo systemctl enable etcd
    sudo systemctl start etcd
    sleep 5
    
    if ! sudo systemctl is-active --quiet etcd; then
        echo 'ERROR: etcd failed to start'
        sudo journalctl -u etcd --lines=20 --no-pager
        exit 1
    fi
    echo 'etcd is running successfully'
    
    echo 'Verifying etcd cluster health...'
    sudo -u etcd /usr/local/bin/etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem \
        member list
    sudo -u etcd /usr/local/bin/etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem \
        endpoint health
" || {
    print_error "Failed to set up etcd on controller-0 after retries"
    exit 1
}

print_status "Waiting for etcd cluster to stabilize..."
sleep 10

print_success "etcd cluster setup completed!"

print_status "Step 6: Setting up Kubernetes control plane..."

# Download Kubernetes binaries on controllers
run_on_controllers "
    sudo mkdir -p /etc/kubernetes/config
    wget -q --https-only --timestamping \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-apiserver \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-controller-manager \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-scheduler \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl
    
    chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
    sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
"

# Configure API server on each controller
while IFS= read -r line; do
    if [[ $line =~ ^controller- ]]; then
        controller_name=$(echo $line | cut -d' ' -f1)
        controller_host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
        controller_private_ip=$(echo $line | cut -d' ' -f3 | cut -d'=' -f2)
        
        # Get etcd servers list
        ETCD_SERVERS=""
        while IFS= read -r inner_line; do
            if [[ $inner_line =~ ^controller- ]]; then
                inner_private_ip=$(echo $inner_line | cut -d' ' -f3 | cut -d'=' -f2)
                ETCD_SERVERS="${ETCD_SERVERS}https://${inner_private_ip}:2379,"
            fi
        done < inventory.ini
        ETCD_SERVERS=${ETCD_SERVERS%,}
        
        print_status "Configuring API server on $controller_name"
        
        ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$controller_host "
            # Verify certificates exist before creating service
            echo 'Verifying certificates exist in /var/lib/kubernetes/:'
            ls -la /var/lib/kubernetes/
            
            # Check that all required certificates are present
            required_files=('ca.pem' 'ca-key.pem' 'kubernetes.pem' 'kubernetes-key.pem' 'service-account.pem' 'service-account-key.pem' 'encryption-config.yaml')
            for file in \"\${required_files[@]}\"; do
                if [ ! -f \"/var/lib/kubernetes/\$file\" ]; then
                    echo \"ERROR: Required file \$file not found in /var/lib/kubernetes/\"
                    exit 1
                fi
            done
            echo 'All required certificates and configs are present'
            
            sudo tee /etc/systemd/system/kube-apiserver.service > /dev/null <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\\\
  --advertise-address=${controller_private_ip} \\\\
  --allow-privileged=true \\\\
  --apiserver-count=1 \\\\
  --audit-log-maxage=30 \\\\
  --audit-log-maxbackup=3 \\\\
  --audit-log-maxsize=100 \\\\
  --audit-log-path=/var/log/audit.log \\\\
  --authorization-mode=Node,RBAC \\\\
  --bind-address=0.0.0.0 \\\\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\\\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\\\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\\\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\\\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\\\
  --etcd-servers=${ETCD_SERVERS} \\\\
  --event-ttl=1h \\\\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\\\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\\\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\\\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\\\
  --runtime-config='api/all=true' \\\\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\\\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\\\
  --service-account-issuer=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \\\\
  --service-cluster-ip-range=10.32.0.0/24 \\\\
  --service-node-port-range=30000-32767 \\\\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\\\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\\\
  --v=2
Restart=on-failure
RestartSec=5
TimeoutStartSec=0
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF

            # Configure kube-controller-manager
            sudo tee /etc/systemd/system/kube-controller-manager.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\\\
  --bind-address=0.0.0.0 \\\\
  --cluster-cidr=10.200.0.0/16 \\\\
  --cluster-name=kubernetes \\\\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\\\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\\\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\\\
  --leader-elect=true \\\\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\\\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\\\
  --service-cluster-ip-range=10.32.0.0/24 \\\\
  --use-service-account-credentials=true \\\\
  --v=2
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

            # Configure kube-scheduler
            sudo tee /etc/kubernetes/config/kube-scheduler.yaml > /dev/null <<EOF
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: \"/var/lib/kubernetes/kube-scheduler.kubeconfig\"
leaderElection:
  leaderElect: true
profiles:
- schedulerName: default-scheduler
EOF

            sudo tee /etc/systemd/system/kube-scheduler.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\\\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\\\
  --v=2
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

            # Start services one by one with proper error handling
            sudo systemctl daemon-reload
            
            # Enable services
            sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
            
            # Start API server first
            echo 'Starting kube-apiserver...'
            sudo systemctl start kube-apiserver
            sleep 15
            
            if ! sudo systemctl is-active --quiet kube-apiserver; then
                echo 'ERROR: kube-apiserver failed to start'
                sudo journalctl -u kube-apiserver --lines=20 --no-pager
                exit 1
            fi
            echo 'kube-apiserver started successfully'
            
            # Start controller manager
            echo 'Starting kube-controller-manager...'
            sudo systemctl start kube-controller-manager
            sleep 10
            
            if ! sudo systemctl is-active --quiet kube-controller-manager; then
                echo 'ERROR: kube-controller-manager failed to start'
                sudo journalctl -u kube-controller-manager --lines=20 --no-pager
                exit 1
            fi
            echo 'kube-controller-manager started successfully'
            
            # Start scheduler
            echo 'Starting kube-scheduler...'
            sudo systemctl start kube-scheduler
            sleep 5
            
            if ! sudo systemctl is-active --quiet kube-scheduler; then
                echo 'ERROR: kube-scheduler failed to start'
                sudo journalctl -u kube-scheduler --lines=20 --no-pager
                exit 1
            fi
            echo 'kube-scheduler started successfully'
            
            echo 'All Kubernetes control plane components started successfully'
        " || {
            print_error "Kubernetes control plane setup failed on $controller_name"
            exit 1
        }
    fi
done < inventory.ini

print_status "Waiting for API servers to be ready..."
sleep 60

# Verify API server accessibility before RBAC setup
first_controller_host=$(grep "^controller-0" inventory.ini | cut -d' ' -f2 | cut -d'=' -f2)

print_status "Verifying API server accessibility..."
for i in {1..30}; do
    if ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$first_controller_host "kubectl --kubeconfig /var/lib/kubernetes/admin.kubeconfig get componentstatuses 2>/dev/null"; then
        print_success "API server is accessible"
        break
    else
        print_status "Waiting for API server to become accessible... (attempt $i/30)"
        if [ $i -eq 30 ]; then
            print_error "API server failed to become accessible"
            # Show logs for debugging
            ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$first_controller_host "
                echo '=== API Server Status ==='
                sudo systemctl status kube-apiserver --no-pager -l
                echo '=== API Server Logs ==='
                sudo journalctl -u kube-apiserver --lines=30 --no-pager
                echo '=== etcd Status ==='
                sudo systemctl status etcd --no-pager -l
            "
            exit 1
        fi
        sleep 10
    fi
done

print_success "Kubernetes control plane setup completed!"

print_status "Step 7: Setting up RBAC for kubelet authorization..."

# Configure RBAC on first controller
ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$first_controller_host "
    kubectl apply --kubeconfig /var/lib/kubernetes/admin.kubeconfig -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: \"true\"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - \"\"
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - \"*\"
EOF

    kubectl apply --kubeconfig /var/lib/kubernetes/admin.kubeconfig -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: \"\"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
" || {
    print_error "RBAC configuration failed"
    exit 1
}

print_success "RBAC configuration completed!"

# Step 8: Setting up worker nodes
print_status "Step 8: Setting up worker nodes..."

# Install binaries on workers
run_on_workers "
    set -e
    echo 'Checking system resources...'
    df -h /
    free -m
    if [ \$(df --output=avail / | tail -n 1) -lt 100000 ]; then
        echo 'ERROR: Less than 100 MB free disk space on /'
        exit 1
    fi
    if [ \$(free -m | awk '/^Mem:/ {print \$4}') -lt 100 ]; then
        echo 'ERROR: Less than 100 MB free memory'
        exit 1
    fi

    echo 'Installing required packages...'
    sudo apt-get update
    sudo apt-get install -y socat conntrack ipset || {
        echo 'ERROR: Failed to install packages'
        exit 1
    }
    
    echo 'Installing CNI plugins...'
    for attempt in {1..3}; do
        wget -q --show-progress --https-only --timestamping \
            \"https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz\" || {
            echo \"CNI download attempt \$attempt/3 failed, retrying in 5 seconds...\"
            sleep 5
            if [ \$attempt -eq 3 ]; then
                echo 'ERROR: Failed to download CNI plugins after 3 attempts'
                exit 1
            fi
            continue
        }
        if [ ! -f cni-plugins-linux-amd64-${CNI_VERSION}.tgz ]; then
            echo 'ERROR: CNI tarball not found after download attempt \$attempt'
            exit 1
        fi
        break
    done
    if ! file cni-plugins-linux-amd64-${CNI_VERSION}.tgz | grep -q 'gzip compressed data'; then
        echo 'ERROR: Downloaded CNI tarball is invalid'
        exit 1
    fi
    sudo mkdir -p /opt/cni/bin
    sudo tar -xzf cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin/ || {
        echo 'ERROR: Failed to extract CNI plugins'
        exit 1
    }
    rm -f cni-plugins-linux-amd64-${CNI_VERSION}.tgz
    
    echo 'Installing containerd...'
    for attempt in {1..3}; do
        wget -q --show-progress --https-only --timestamping \
            \"https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz\" || {
            echo \"Containerd download attempt \$attempt/3 failed, retrying in 5 seconds...\"
            sleep 5
            if [ \$attempt -eq 3 ]; then
                echo 'ERROR: Failed to download containerd after 3 attempts'
                exit 1
            fi
            continue
        }
        if [ ! -f containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz ]; then
            echo 'ERROR: Containerd tarball not found after download attempt \$attempt'
            exit 1
        fi
        break
    done
    if ! file containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz | grep -q 'gzip compressed data'; then
        echo 'ERROR: Downloaded containerd tarball is invalid'
        exit 1
    fi
    sudo tar -xzf containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C /usr/local || {
        echo 'ERROR: Failed to extract containerd'
        exit 1
    }
    rm -f containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz
    
    echo 'Installing crictl...'
    for attempt in {1..3}; do
        wget -q --show-progress --https-only --timestamping \
            \"https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz\" || {
            echo \"crictl download attempt \$attempt/3 failed, retrying in 5 seconds...\"
            sleep 5
            if [ \$attempt -eq 3 ]; then
                echo 'ERROR: Failed to download crictl after 3 attempts'
                exit 1
            fi
            continue
        }
        if [ ! -f crictl-${CRICTL_VERSION}-linux-amd64.tar.gz ]; then
            echo 'ERROR: crictl tarball not found after download attempt \$attempt'
            exit 1
        fi
        break
    done
    if ! file crictl-${CRICTL_VERSION}-linux-amd64.tar.gz | grep -q 'gzip compressed data'; then
        echo 'ERROR: Downloaded crictl tarball is invalid'
        exit 1
    fi
    sudo tar -xzf crictl-${CRICTL_VERSION}-linux-amd64.tar.gz -C /usr/local/bin/ || {
        echo 'ERROR: Failed to extract crictl'
        exit 1
    }
    rm -f crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
    
    echo 'Installing kubelet...'
    for attempt in {1..3}; do
        wget -q --show-progress --https-only --timestamping \
            \"https://dl.k8s.io/release/${KUBELET_VERSION}/bin/linux/amd64/kubelet\" || {
            echo \"kubelet download attempt \$attempt/3 failed, retrying in 5 seconds...\"
            sleep 5
            if [ \$attempt -eq 3 ]; then
                echo 'ERROR: Failed to download kubelet after 3 attempts'
                exit 1
            fi
            continue
        }
        if [ ! -f kubelet ]; then
            echo 'ERROR: kubelet file not found after download attempt \$attempt'
            exit 1
        fi
        break
    done
    if ! file kubelet | grep -q 'ELF 64-bit LSB executable'; then
        echo 'ERROR: Downloaded kubelet binary is invalid'
        rm -f kubelet
        exit 1
    fi
    sudo mv kubelet /usr/local/bin/kubelet || {
        echo 'ERROR: Failed to move kubelet to /usr/local/bin/'
        rm -f kubelet
        exit 1
    }
    sudo chmod +x /usr/local/bin/kubelet
    echo 'Verifying kubelet installation...'
    if ! /usr/local/bin/kubelet --version; then
        echo 'ERROR: kubelet binary is not executable or invalid'
        exit 1
    fi
    
    echo 'Listing installed binaries...'
    ls -la /opt/cni/bin
    ls -la /usr/local/bin
" || {
    print_error "Failed to install binaries on workers"
    exit 1
}

# Configure kubelet and kube-proxy on each worker
while IFS= read -r line; do
    if [[ $line =~ ^worker- ]]; then
        worker_name=$(echo $line | cut -d' ' -f1)
        worker_host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
        worker_private_ip=$(echo $line | cut -d' ' -f3 | cut -d'=' -f2)
        pod_cidr=$(echo $line | grep -o 'pod_cidr=[^ ]*' | cut -d'=' -f2 || echo "10.200.${worker_name: -1}.0/24")
        
        print_status "Configuring kubelet on $worker_name ($worker_host)"

        # Debug: List available files in certs/ and kubeconfigs/
        echo "Available files in certs/:"
        ls -l certs/ || echo "certs/ directory not found"
        echo "Available files in kubeconfigs/:"
        ls -l kubeconfigs/ || echo "kubeconfigs/ directory not found"

        # Check for required files
        if [ ! -f "certs/${worker_name}.kubeconfig" ] && [ ! -f "kubeconfigs/${worker_name}.kubeconfig" ]; then
            echo "ERROR: Kubeconfig file for ${worker_name} not found in certs/ or kubeconfigs/"
            exit 1
        fi
        if [ ! -f "certs/kube-proxy.kubeconfig" ] && [ ! -f "kubeconfigs/kube-proxy.kubeconfig" ]; then
            echo "ERROR: kube-proxy kubeconfig file not found in certs/ or kubeconfigs/"
            exit 1
        fi
        if [ ! -f "certs/ca.pem" ]; then
            echo "ERROR: ca.pem not found in certs/"
            exit 1
        fi
        if [ ! -f "certs/${worker_name}.pem" ]; then
            echo "ERROR: ${worker_name}.pem not found in certs/"
            exit 1
        fi
        if [ ! -f "certs/${worker_name}-key.pem" ]; then
            echo "ERROR: ${worker_name}-key.pem not found in certs/"
            exit 1
        fi

        # Use kubeconfigs/ if certs/${worker_name}.kubeconfig doesn't exist
        kubelet_kubeconfig_path="certs/${worker_name}.kubeconfig"
        kube_proxy_kubeconfig_path="certs/kube-proxy.kubeconfig"
        if [ -f "kubeconfigs/${worker_name}.kubeconfig" ]; then
            kubelet_kubeconfig_path="kubeconfigs/${worker_name}.kubeconfig"
        fi
        if [ -f "kubeconfigs/kube-proxy.kubeconfig" ]; then
            kube_proxy_kubeconfig_path="kubeconfigs/kube-proxy.kubeconfig"
        fi

        # Base64-encode certificates and configs
        ca_pem=$(base64 -w 0 < certs/ca.pem)
        worker_pem=$(base64 -w 0 < certs/${worker_name}.pem)
        worker_key_pem=$(base64 -w 0 < certs/${worker_name}-key.pem)
        kubelet_kubeconfig=$(base64 -w 0 < "$kubelet_kubeconfig_path")
        kube_proxy_kubeconfig=$(base64 -w 0 < "$kube_proxy_kubeconfig_path")
        
        ssh -F ssh_config -o ConnectTimeout=60 -o StrictHostKeyChecking=no -v $worker_name "
            set -e
            # Create directories
            sudo mkdir -p /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /etc/cni/net.d /etc/systemd/system /etc/containerd

            # Get actual node name from hostname
            node_name=\$(hostname)
            echo \"Detected node name: \$node_name\"

            # Copy certificates and configs
            echo '$ca_pem' | base64 -d | sudo tee /var/lib/kubernetes/ca.pem > /dev/null
            echo '$worker_pem' | base64 -d | sudo tee /var/lib/kubelet/${worker_name}.pem > /dev/null
            echo '$worker_key_pem' | base64 -d | sudo tee /var/lib/kubelet/${worker_name}-key.pem > /dev/null
            echo '$kubelet_kubeconfig' | base64 -d | sudo tee /var/lib/kubelet/kubeconfig > /dev/null
            echo '$kube_proxy_kubeconfig' | base64 -d | sudo tee /var/lib/kube-proxy/kubeconfig > /dev/null

            # Fix kubeconfig node name to match actual hostname
            sudo sed -i \"s/system:node:${worker_name}/system:node:\$node_name/g\" /var/lib/kubelet/kubeconfig
            sudo sed -i \"s/system:node:worker-0/system:node:\$node_name/g\" /var/lib/kubelet/kubeconfig

            # Verify kubeconfig
            echo 'Verifying kubeconfig...'
            sudo grep \"user: system:node:\$node_name\" /var/lib/kubelet/kubeconfig || {
                echo 'ERROR: Failed to update kubeconfig node name'
                exit 1
            }

            # Verify certificates
            echo 'Verifying certificates in /var/lib/kubelet/ and /var/lib/kubernetes/:'
            ls -la /var/lib/kubelet/ /var/lib/kubernetes/
            
            # Create containerd config
            sudo tee /etc/containerd/config.toml > /dev/null <<EOF
[plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runc]
  [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF
            echo 'Verifying containerd config...'
            ls -l /etc/containerd/

            # Create containerd service
            sudo tee /etc/systemd/system/containerd.service > /dev/null <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-500
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
            echo 'Verifying containerd service file...'
            ls -l /etc/systemd/system/containerd.service

            # Create kubelet config
            sudo tee /var/lib/kubelet/kubelet-config.yaml > /dev/null <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: \"/var/lib/kubernetes/ca.pem\"
authorization:
  mode: Webhook
clusterDomain: \"cluster.local\"
clusterDNS:
  - \"10.32.0.10\"
podCIDR: \"${pod_cidr}\"
resolvConf: \"/run/systemd/resolve/resolv.conf\"
runtimeRequestTimeout: \"15m\"
tlsCertFile: \"/var/lib/kubelet/${worker_name}.pem\"
tlsPrivateKeyFile: \"/var/lib/kubelet/${worker_name}-key.pem\"
cgroupDriver: \"systemd\"
EOF

            # Create kubelet service
            sudo tee /etc/systemd/system/kubelet.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --register-node=true \\
  --node-ip=${worker_private_ip} \\
  --v=2
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

            # Configure kube-proxy
            sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml > /dev/null <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: \"/var/lib/kube-proxy/kubeconfig\"
mode: \"iptables\"
clusterCIDR: \"10.200.0.0/16\"
EOF

            # Create kube-proxy service
            sudo tee /etc/systemd/system/kube-proxy.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

            # Start services with error handling
            sudo systemctl daemon-reload
            sudo systemctl enable containerd kubelet kube-proxy
            
            echo 'Starting containerd...'
            sudo systemctl start containerd
            sleep 5
            
            if ! sudo systemctl is-active --quiet containerd; then
                echo 'ERROR: containerd failed to start'
                sudo journalctl -u containerd --lines=20 --no-pager
                exit 1
            fi
            echo 'containerd started successfully'
            
            echo 'Starting kubelet...'
            sudo systemctl restart kubelet
            sleep 10
            
            if ! sudo systemctl is-active --quiet kubelet; then
                echo 'ERROR: kubelet failed to start'
                sudo journalctl -u kubelet --lines=20 --no-pager
                exit 1
            fi
            echo 'kubelet started successfully'
            
            echo 'Starting kube-proxy...'
            sudo systemctl start kube-proxy
            sleep 5
            
            if ! sudo systemctl is-active --quiet kube-proxy; then
                echo 'ERROR: kube-proxy failed to start'
                sudo journalctl -u kube-proxy --lines=20 --no-pager
                exit 1
            fi
            echo 'kube-proxy started successfully'
            
            echo 'All worker components started successfully'
        " || {
            print_error "Worker setup failed on $worker_name"
            exit 1
        }
    fi
done < inventory.ini

# Apply RBAC for node registration
print_status "Applying RBAC for node registration..."
kubectl --kubeconfig=admin.kubeconfig apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:node
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["create", "get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["nodes/status"]
  verbs: ["update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:node
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:node
  apiGroup: rbac.authorization.k8s.io
EOF

print_success "Worker node setup completed!"

print_status "Step 9: Configuring kubectl for remote access..."

# Create admin kubeconfig for remote access
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=certs/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=certs/admin.pem \
  --client-key=certs/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context kubernetes-the-hard-way --kubeconfig=admin.kubeconfig

print_success "Admin kubeconfig created: admin.kubeconfig"

# Step 10: Installing Pod network (Weave Net)
print_status "Step 10: Installing Pod network (Weave Net)..."

# Ensure DNS resolution
run_on_controllers "
    set -e
    echo 'Fixing DNS resolution...'
    sudo bash -c 'echo \"nameserver 8.8.8.8\" > /etc/resolv.conf'
    if ! nslookup cloud.weave.works >/dev/null; then
        echo 'ERROR: DNS resolution for cloud.weave.works failed'
        exit 1
    fi
" || {
    print_error "Failed to configure DNS on controllers"
    exit 1
}

# Wait for nodes to be ready
print_status "Waiting for nodes to be ready..."
for attempt in {1..30}; do
    print_status "Waiting for nodes to register... (attempt $attempt/30)"
    nodes_ready=$(kubectl --kubeconfig=admin.kubeconfig get nodes -o jsonpath='{.items[?(@.status.conditions[-1].type=="Ready")].status.conditions[-1].status}' | grep -c True || true)
    if [ "$nodes_ready" -ge 2 ]; then
        print_status "All worker nodes are ready!"
        break
    fi
    if [ $attempt -eq 30 ]; then
        print_error "Worker nodes failed to register after 15 minutes"
        kubectl --kubeconfig=admin.kubeconfig get nodes -o wide
        for node in worker-0 worker-1; do
            ssh -F ssh_config -o ConnectTimeout=10 -o StrictHostKeyChecking=no $node "
                echo 'Checking kubelet status on $node...'
                sudo systemctl status kubelet --no-pager
                sudo journalctl -u kubelet --no-pager -n 50
                echo 'Checking API server connectivity...'
                curl -k https://${KUBERNETES_PUBLIC_ADDRESS}:6443 || echo 'Failed to connect to API server'
            "
        done
        exit 1
    fi
    sleep 30
done

# Install Weave Net
print_status "Installing Weave Net..."
kubectl --kubeconfig=admin.kubeconfig apply -f https://cloud.weave.works/k8s/net?k8s-version=v1.28.3 || {
    print_status "Trying alternative Weave installation..."
    kubectl --kubeconfig=admin.kubeconfig apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml || {
        print_error "Failed to install Weave network"
        exit 1
    }
}

# Wait for Weave Net pods to be ready
print_status "Waiting for pod network to be ready..."
for attempt in {1..10}; do
    pods_ready=$(kubectl --kubeconfig=admin.kubeconfig get pods -n kube-system -l name=weave-net -o jsonpath='{.items[?(@.status.phase=="Running")].status.phase}' | grep -c Running || true)
    if [ "$pods_ready" -ge 2 ]; then
        print_status "Weave Net pods are ready!"
        break
    fi
    if [ $attempt -eq 10 ]; then
        print_error "Weave Net pods failed to start after 5 minutes"
        kubectl --kubeconfig=admin.kubeconfig get pods -n kube-system -o wide
        kubectl --kubeconfig=admin.kubeconfig get events -n kube-system
        exit 1
    fi
    sleep 30
done

# Final verification
print_status "Final verification..."
print_status "Getting cluster nodes..."
kubectl --kubeconfig=admin.kubeconfig get nodes -o wide
print_status "Getting cluster pods..."
kubectl --kubeconfig=admin.kubeconfig get pods --all-namespaces -o wide
print_status "Getting cluster component status..."
kubectl --kubeconfig=admin.kubeconfig get componentstatuses

print_success "Kubernetes The Hard Way setup completed successfully!"
print_success "Use 'kubectl --kubeconfig=admin.kubeconfig' to interact with your cluster"
print_success "Or copy admin.kubeconfig to ~/.kube/config to use kubectl normally"
echo
echo "=============================================="
echo "  Kubernetes The Hard Way Setup Complete!"
echo "=============================================="
echo "Cluster endpoint: https://${KUBERNETES_PUBLIC_ADDRESS}:6443"
echo "Admin kubeconfig: admin.kubeconfig"
echo "SSH config: ssh_config"
echo "Private key: k8s-key.pem"
echo
echo "Quick test commands:"
echo "  kubectl --kubeconfig=admin.kubeconfig get nodes"
echo "  kubectl --kubeconfig=admin.kubeconfig get pods --all-namespaces"
echo "  kubectl --kubeconfig=admin.kubeconfig cluster-info"
echo
echo "To use kubectl without --kubeconfig flag:"
echo "  export KUBECONFIG=$PWD/admin.kubeconfig"
echo "  # OR"
echo "  cp admin.kubeconfig ~/.kube/config"
echo "=============================================="
echo -e "${NC}"