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
CNI_VERSION="v1.3.0"
CONTAINERD_VERSION="1.7.8"
RUNC_VERSION="v1.1.9"

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
            host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
            print_status "Running on controller: $host"
            ssh -F ssh_config -o ConnectTimeout=30 -o StrictHostKeyChecking=no ubuntu@$host "$cmd" || {
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
            host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
            print_status "Running on worker: $host"
            ssh -F ssh_config -o ConnectTimeout=30 -o StrictHostKeyChecking=no ubuntu@$host "$cmd" || {
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

# First, create necessary directories on all nodes
run_on_controllers "sudo mkdir -p /var/lib/kubernetes/ /etc/etcd/"
run_on_workers "sudo mkdir -p /var/lib/kubelet/ /var/lib/kube-proxy/ /var/lib/kubernetes/"

# **FIXED: Copy certificates to both locations on controllers**
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
        
        # **FIXED: Copy certificates to BOTH /etc/etcd/ and /var/lib/kubernetes/**
        ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$controller_host "
            # Copy for etcd (with etcd ownership)
            sudo cp /tmp/ca.pem /tmp/kubernetes-key.pem /tmp/kubernetes.pem /etc/etcd/
            sudo chown etcd:etcd /etc/etcd/*
            
            # Copy for kubernetes API server (all required certificates)
            sudo cp /tmp/ca.pem /tmp/ca-key.pem /tmp/kubernetes.pem /tmp/kubernetes-key.pem /var/lib/kubernetes/
            sudo cp /tmp/service-account.pem /tmp/service-account-key.pem /var/lib/kubernetes/
            sudo cp /tmp/encryption-config.yaml /var/lib/kubernetes/
            sudo cp /tmp/admin.kubeconfig /tmp/kube-controller-manager.kubeconfig /tmp/kube-scheduler.kubeconfig /var/lib/kubernetes/
            
            # Set proper permissions
            sudo chown root:root /var/lib/kubernetes/*
            sudo chmod 600 /var/lib/kubernetes/*-key.pem
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
    fi
done < inventory.ini

print_success "Certificates and configs distributed successfully!"

print_status "Step 5: Setting up etcd cluster on controllers..."

# Download and install etcd on controllers
run_on_controllers "
    wget -q --https-only --timestamping https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz
    tar -xvf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
    sudo mv etcd-${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/
    sudo mkdir -p /etc/etcd /var/lib/etcd
    sudo groupadd -f etcd
    sudo useradd -c \"etcd user\" -d /var/lib/etcd -s /bin/false -g etcd -r etcd 2>/dev/null || true
    sudo chown etcd:etcd /var/lib/etcd
"

# Create etcd systemd service on each controller
while IFS= read -r line; do
    if [[ $line =~ ^controller- ]]; then
        controller_name=$(echo $line | cut -d' ' -f1)
        controller_host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
        controller_private_ip=$(echo $line | cut -d' ' -f3 | cut -d'=' -f2)
        
        # Get all controller IPs for cluster formation
        ETCD_CLUSTER=""
        while IFS= read -r inner_line; do
            if [[ $inner_line =~ ^controller- ]]; then
                inner_name=$(echo $inner_line | cut -d' ' -f1)
                inner_private_ip=$(echo $inner_line | cut -d' ' -f3 | cut -d'=' -f2)
                ETCD_CLUSTER="${ETCD_CLUSTER}${inner_name}=https://${inner_private_ip}:2380,"
            fi
        done < inventory.ini
        ETCD_CLUSTER=${ETCD_CLUSTER%,}
        
        print_status "Setting up etcd on $controller_name"
        
        ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$controller_host "
            sudo tee /etc/systemd/system/etcd.service > /dev/null <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
User=etcd
ExecStart=/usr/local/bin/etcd \\\\
  --name ${controller_name} \\\\
  --cert-file=/etc/etcd/kubernetes.pem \\\\
  --key-file=/etc/etcd/kubernetes-key.pem \\\\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\\\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\\\
  --trusted-ca-file=/etc/etcd/ca.pem \\\\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\\\
  --peer-client-cert-auth \\\\
  --client-cert-auth \\\\
  --initial-advertise-peer-urls https://${controller_private_ip}:2380 \\\\
  --listen-peer-urls https://${controller_private_ip}:2380 \\\\
  --listen-client-urls https://${controller_private_ip}:2379,https://127.0.0.1:2379 \\\\
  --advertise-client-urls https://${controller_private_ip}:2379 \\\\
  --initial-cluster-token etcd-cluster-0 \\\\
  --initial-cluster ${ETCD_CLUSTER} \\\\
  --initial-cluster-state new \\\\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
            sudo systemctl enable etcd
            sudo systemctl start etcd
        "
    fi
done < inventory.ini

print_status "Waiting for etcd cluster to be ready..."
sleep 30

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
            # **VERIFY CERTIFICATES EXIST**
            echo 'Verifying certificates exist:'
            ls -la /var/lib/kubernetes/
            
            sudo tee /etc/systemd/system/kube-apiserver.service > /dev/null <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

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

[Install]
WantedBy=multi-user.target
EOF

            # Configure kube-controller-manager
            sudo tee /etc/systemd/system/kube-controller-manager.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

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

[Install]
WantedBy=multi-user.target
EOF

            # Configure kube-scheduler
            sudo tee /etc/kubernetes/config/kube-scheduler.yaml > /dev/null <<EOF
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
profiles:
- schedulerName: default-scheduler
EOF

            sudo tee /etc/systemd/system/kube-scheduler.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\\\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\\\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

            # Start services
            sudo systemctl daemon-reload
            sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
            sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
            
            # Wait for API server to be ready before proceeding
            sleep 20
            
            # Verify API server is running
            for i in {1..30}; do
                if sudo systemctl is-active --quiet kube-apiserver; then
                    echo 'API server is running'
                    break
                fi
                echo 'Waiting for API server to start...'
                sleep 5
            done
        "
    fi
done < inventory.ini

print_status "Waiting for API servers to be ready..."
sleep 60

# Verify API server accessibility before RBAC setup
first_controller_host=$(grep "^controller-0" inventory.ini | cut -d' ' -f2 | cut -d'=' -f2)

print_status "Verifying API server accessibility..."
for i in {1..30}; do
    if ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$first_controller_host "kubectl --kubeconfig /var/lib/kubernetes/admin.kubeconfig get nodes 2>/dev/null"; then
        print_success "API server is accessible"
        break
    else
        print_status "Waiting for API server to become accessible... (attempt $i/30)"
        if [ $i -eq 30 ]; then
            print_error "API server failed to become accessible"
            # Show logs for debugging
            ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$first_controller_host "sudo journalctl -u kube-apiserver --lines=20 --no-pager"
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
"

print_success "RBAC configuration completed!"

print_status "Step 8: Setting up worker nodes..."

# Download and install worker binaries
run_on_workers "
    sudo apt-get update
    sudo apt-get -y install socat conntrack ipset
    
    sudo mkdir -p /etc/cni/net.d /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes
    
    wget -q --https-only --timestamping \\
      https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.28.0/crictl-v1.28.0-linux-amd64.tar.gz \\
      https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.amd64 \\
      https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz \\
      https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-proxy \\
      https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubelet
    
    # Install CNI plugins
    sudo tar -xvf cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin/
    
    # Install containerd
    sudo tar -xvf containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C /
    
    # Install runc
    sudo mv runc.amd64 runc
    chmod +x runc kubectl kube-proxy kubelet
    sudo mv runc /usr/local/bin/
    sudo mv kubectl kube-proxy kubelet /usr/local/bin/
    
    # Extract and install crictl
    tar -xvf crictl-v1.28.0-linux-amd64.tar.gz
    sudo mv crictl /usr/local/bin/
"

# Configure containerd on workers
run_on_workers "
    sudo mkdir -p /etc/containerd/
    
    sudo tee /etc/containerd/config.toml > /dev/null <<EOF
[plugins]
  [plugins.cri.containerd]
    snapshotter = \"overlayfs\"
    [plugins.cri.containerd.default_runtime]
      runtime_type = \"io.containerd.runc.v2\"
      runtime_engine = \"/usr/local/bin/runc\"
      runtime_root = \"\"
EOF

    sudo tee /etc/systemd/system/containerd.service > /dev/null <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
"

# Configure kubelet on each worker
while IFS= read -r line; do
    if [[ $line =~ ^worker- ]]; then
        worker_name=$(echo $line | cut -d' ' -f1)
        worker_host=$(echo $line | cut -d' ' -f2 | cut -d'=' -f2)
        worker_private_ip=$(echo $line | cut -d' ' -f3 | cut -d'=' -f2)
        pod_cidr=$(echo $line | grep -oP 'pod_cidr=\K[^[:space:]]+')
        
        print_status "Configuring kubelet on $worker_name"
        
        ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$worker_host "
            # Move certificates
            sudo mv /tmp/${worker_name}-key.pem /tmp/${worker_name}.pem /var/lib/kubelet/
            sudo mv /tmp/${worker_name}.kubeconfig /var/lib/kubelet/kubeconfig
            sudo mv /tmp/ca.pem /var/lib/kubernetes/
            
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
EOF

            # Create kubelet service
            sudo tee /etc/systemd/system/kubelet.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\\\
  --config=/var/lib/kubelet/kubelet-config.yaml \\\\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\\\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\\\
  --register-node=true \\\\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

            # Configure kube-proxy
            sudo mv /tmp/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
            
            sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml > /dev/null <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: \"/var/lib/kube-proxy/kubeconfig\"
mode: \"iptables\"
clusterCIDR: \"10.200.0.0/16\"
EOF

            sudo tee /etc/systemd/system/kube-proxy.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\\\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

            # Start services
            sudo systemctl daemon-reload
            sudo systemctl enable containerd kubelet kube-proxy
            sudo systemctl start containerd kubelet kube-proxy
        "
    fi
done < inventory.ini

print_status "Waiting for worker nodes to register..."
sleep 30

print_success "Worker nodes setup completed!"

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

print_status "Step 10: Installing Pod network (Weave Net)..."

# Install pod network
kubectl --kubeconfig=admin.kubeconfig apply -f "https://cloud.weave.works/k8s/net?k8s-version=\$(kubectl --kubeconfig=admin.kubeconfig version | base64 | tr -d '\n')&env.IPALLOC_RANGE=10.200.0.0/16"

print_status "Waiting for pod network to be ready..."
sleep 30

print_status "Final verification..."

# Test the cluster
kubectl --kubeconfig=admin.kubeconfig get nodes
kubectl --kubeconfig=admin.kubeconfig get pods --all-namespaces

print_success "Kubernetes The Hard Way setup completed successfully!"
print_success "Use 'kubectl --kubeconfig=admin.kubeconfig' to interact with your cluster"
print_success "Or copy admin.kubeconfig to ~/.kube/config to use kubectl normally"

echo -e "${GREEN}"
echo "=============================================="
echo "  Kubernetes The Hard Way Setup Complete!"
echo "=============================================="
echo "Cluster endpoint: https://${KUBERNETES_PUBLIC_ADDRESS}:6443"
echo "Admin kubeconfig: admin.kubeconfig"
echo "SSH config: ssh_config"
echo "Private key: k8s-key.pem"
echo "=============================================="
echo -e "${NC}"