#!/bin/bash

# Quick fix script for certificate issues
set -e

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

print_status "Quick fix for certificate issues..."

# Get the controller IP from inventory
CONTROLLER_HOST=$(grep "^controller-0" inventory.ini | cut -d' ' -f2 | cut -d'=' -f2)

if [ -z "$CONTROLLER_HOST" ]; then
    print_error "Could not find controller-0 in inventory.ini"
    exit 1
fi

print_status "Found controller at: $CONTROLLER_HOST"

# Check what certificates exist locally
print_status "Checking local certificates..."
ls -la certs/

# Copy missing certificates to controller
print_status "Copying certificates to controller..."

# Copy all certificates to /tmp on controller
scp -F ssh_config -o StrictHostKeyChecking=no certs/ca.pem ubuntu@$CONTROLLER_HOST:/tmp/
scp -F ssh_config -o StrictHostKeyChecking=no certs/ca-key.pem ubuntu@$CONTROLLER_HOST:/tmp/
scp -F ssh_config -o StrictHostKeyChecking=no certs/kubernetes.pem ubuntu@$CONTROLLER_HOST:/tmp/
scp -F ssh_config -o StrictHostKeyChecking=no certs/kubernetes-key.pem ubuntu@$CONTROLLER_HOST:/tmp/
scp -F ssh_config -o StrictHostKeyChecking=no certs/service-account.pem ubuntu@$CONTROLLER_HOST:/tmp/
scp -F ssh_config -o StrictHostKeyChecking=no certs/service-account-key.pem ubuntu@$CONTROLLER_HOST:/tmp/

# Fix certificates on controller
ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$CONTROLLER_HOST "
    # Stop services first
    sudo systemctl stop kube-apiserver kube-controller-manager kube-scheduler
    
    # Copy certificates to proper locations
    sudo cp /tmp/ca.pem /tmp/ca-key.pem /tmp/kubernetes.pem /tmp/kubernetes-key.pem /var/lib/kubernetes/
    sudo cp /tmp/service-account.pem /tmp/service-account-key.pem /var/lib/kubernetes/
    
    # Also copy to etcd location (they are already there but just to be sure)
    sudo cp /tmp/ca.pem /tmp/kubernetes.pem /tmp/kubernetes-key.pem /etc/etcd/
    
    # Set proper permissions
    sudo chown root:root /var/lib/kubernetes/*
    sudo chmod 600 /var/lib/kubernetes/*-key.pem
    sudo chmod 644 /var/lib/kubernetes/*.pem
    
    # Fix etcd permissions
    sudo chown etcd:etcd /etc/etcd/*
    
    # Verify certificates are in place
    echo 'Certificates in /var/lib/kubernetes/:'
    ls -la /var/lib/kubernetes/
    
    echo 'Certificates in /etc/etcd/:'
    ls -la /etc/etcd/
    
    # Restart services
    sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
    
    # Wait and check status
    sleep 10
    sudo systemctl status kube-apiserver --no-pager --lines=5
"

print_status "Waiting for API server to be ready..."
sleep 30

# Test API server
print_status "Testing API server..."
for i in {1..10}; do
    if ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$CONTROLLER_HOST "kubectl --kubeconfig /var/lib/kubernetes/admin.kubeconfig get componentstatuses 2>/dev/null"; then
        print_success "API server is working!"
        break
    else
        print_status "Waiting for API server... (attempt $i/10)"
        if [ $i -eq 10 ]; then
            print_error "API server is still not responding"
            print_status "Checking logs..."
            ssh -F ssh_config -o StrictHostKeyChecking=no ubuntu@$CONTROLLER_HOST "sudo journalctl -u kube-apiserver --lines=20 --no-pager"
            exit 1
        fi
        sleep 10
    fi
done

print_success "Certificate fix completed successfully!"
print_status "You can now test your cluster with:"
echo "kubectl --kubeconfig=admin.kubeconfig get nodes"
