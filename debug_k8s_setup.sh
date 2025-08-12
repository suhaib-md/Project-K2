#!/bin/bash

# Debug script to check what's wrong with the API server
# Run this after the deployment fails

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Get first controller
first_controller_host=$(grep "^controller-0" inventory.ini | cut -d' ' -f2 | cut -d'=' -f2)

if [ -z "$first_controller_host" ]; then
    print_error "Could not find controller-0 in inventory.ini"
    exit 1
fi

print_header "Diagnosing API Server Issues on $first_controller_host"

echo "Controller host: $first_controller_host"

# Check if we can connect
print_status "Testing SSH connectivity..."
if ssh -F ssh_config -o ConnectTimeout=10 ubuntu@$first_controller_host 'echo "SSH connection successful"'; then
    print_success "SSH connection works"
else
    print_error "Cannot SSH to controller"
    exit 1
fi

# Check systemd services status
print_header "Checking Kubernetes Services Status"
ssh -F ssh_config ubuntu@$first_controller_host "
    echo '=== etcd service ==='
    sudo systemctl status etcd --no-pager -l
    echo
    
    echo '=== kube-apiserver service ==='
    sudo systemctl status kube-apiserver --no-pager -l
    echo
    
    echo '=== kube-controller-manager service ==='
    sudo systemctl status kube-controller-manager --no-pager -l
    echo
    
    echo '=== kube-scheduler service ==='
    sudo systemctl status kube-scheduler --no-pager -l
"

# Check logs
print_header "Checking Service Logs"
ssh -F ssh_config ubuntu@$first_controller_host "
    echo '=== etcd logs (last 20 lines) ==='
    sudo journalctl -u etcd --lines=20 --no-pager
    echo
    
    echo '=== kube-apiserver logs (last 30 lines) ==='
    sudo journalctl -u kube-apiserver --lines=30 --no-pager
    echo
    
    echo '=== kube-controller-manager logs (last 10 lines) ==='
    sudo journalctl -u kube-controller-manager --lines=10 --no-pager
    echo
    
    echo '=== kube-scheduler logs (last 10 lines) ==='
    sudo journalctl -u kube-scheduler --lines=10 --no-pager
"

# Check certificate files
print_header "Checking Certificate Files"
ssh -F ssh_config ubuntu@$first_controller_host "
    echo '=== Checking /var/lib/kubernetes/ certificates ==='
    ls -la /var/lib/kubernetes/
    echo
    
    echo '=== Checking /etc/etcd/ certificates ==='
    ls -la /etc/etcd/
    echo
    
    echo '=== Verifying certificate permissions ==='
    sudo find /var/lib/kubernetes/ -name '*.pem' -exec ls -la {} \;
"

# Check network connectivity
print_header "Checking Network Connectivity"
ssh -F ssh_config ubuntu@$first_controller_host "
    echo '=== Network interfaces ==='
    ip addr show
    echo
    
    echo '=== Listening ports ==='
    sudo netstat -tlnp | grep -E ':(6443|2379|2380|10250|10251|10252)'
    echo
    
    echo '=== Testing local API server connectivity ==='
    curl -k https://127.0.0.1:6443/healthz || echo 'API server not responding on localhost'
    echo
    
    echo '=== Testing etcd connectivity ==='
    sudo ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem endpoint health || echo 'etcd not healthy'
"

# Check configuration files
print_header "Checking Configuration Files"
ssh -F ssh_config ubuntu@$first_controller_host "
    echo '=== kube-apiserver systemd service file ==='
    cat /etc/systemd/system/kube-apiserver.service
    echo
    
    echo '=== Encryption config ==='
    cat /var/lib/kubernetes/encryption-config.yaml
    echo
    
    echo '=== Admin kubeconfig ==='
    cat /var/lib/kubernetes/admin.kubeconfig | grep server
"

print_header "Suggested Fixes"

echo -e "${YELLOW}Based on the logs above, here are common issues and fixes:${NC}"
echo
echo "1. If etcd is not running:"
echo "   ssh -F ssh_config ubuntu@$first_controller_host 'sudo systemctl restart etcd'"
echo
echo "2. If API server has certificate issues:"
echo "   ssh -F ssh_config ubuntu@$first_controller_host 'sudo systemctl restart kube-apiserver'"
echo
echo "3. If API server is not binding to the right interface:"
echo "   Check the --bind-address and --advertise-address in the service file"
echo
echo "4. If there are permission issues:"
echo "   ssh -F ssh_config ubuntu@$first_controller_host 'sudo chown -R root:root /var/lib/kubernetes/'"
echo
echo "5. To restart all services:"
echo "   ssh -F ssh_config ubuntu@$first_controller_host 'sudo systemctl restart etcd kube-apiserver kube-controller-manager kube-scheduler'"
echo
echo "6. To check API server accessibility manually:"
echo "   ssh -F ssh_config ubuntu@$first_controller_host 'kubectl --kubeconfig /var/lib/kubernetes/admin.kubeconfig get nodes'"

print_header "Quick Fix Script"
echo "Would you like me to try some automatic fixes? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    print_status "Attempting automatic fixes..."
    
    # Restart services in order
    ssh -F ssh_config ubuntu@$first_controller_host "
        # Stop all services
        sudo systemctl stop kube-scheduler kube-controller-manager kube-apiserver etcd
        
        # Fix permissions
        sudo chown -R root:root /var/lib/kubernetes/
        sudo chown -R etcd:etcd /etc/etcd/
        sudo chown -R etcd:etcd /var/lib/etcd/
        
        # Start services in order
        sudo systemctl start etcd
        sleep 10
        
        sudo systemctl start kube-apiserver
        sleep 15
        
        sudo systemctl start kube-controller-manager
        sleep 5
        
        sudo systemctl start kube-scheduler
        sleep 5
        
        # Check status
        sudo systemctl status etcd kube-apiserver kube-controller-manager kube-scheduler --no-pager
    "
    
    print_status "Waiting for services to stabilize..."
    sleep 30
    
    # Test API server
    print_status "Testing API server accessibility..."
    for i in {1..10}; do
        if ssh -F ssh_config ubuntu@$first_controller_host "kubectl --kubeconfig /var/lib/kubernetes/admin.kubeconfig get nodes 2>/dev/null"; then
            print_success "API server is now accessible!"
            break
        else
            print_status "Waiting for API server... (attempt $i/10)"
            sleep 10
        fi
    done
fi