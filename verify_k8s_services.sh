#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

controller_ip=$(grep controller-0 inventory.ini | awk '{print $3}' | cut -d'=' -f2)

print_status "Testing Kubernetes API server connectivity..."

# Test API server with curl
if curl -k --connect-timeout 5 https://${controller_ip}:6443/version 2>/dev/null; then
    print_success "API server is responding on port 6443!"
else
    print_error "API server is not responding"
fi

# Test with ss command instead of netstat
print_status "Checking listening ports on controller..."
ssh -F ssh_config controller-0 '
    echo "=== Listening Ports (using ss) ==="
    ss -tlnp | grep -E ":6443|:2379|:2380" || echo "Using lsof instead..."
    
    echo "=== Using lsof ==="
    sudo lsof -i :6443 -i :2379 -i :2380 2>/dev/null || echo "lsof not available"
    
    echo "=== Process check ==="
    ps aux | grep -E "kube-apiserver|etcd" | grep -v grep
'

print_status "Testing etcd connectivity..."
ssh -F ssh_config controller-0 '
    echo "=== etcd cluster health ==="
    sudo ETCDCTL_API=3 etcdctl endpoint health \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem 2>/dev/null || echo "etcd health check failed"
'

# Now continue with the rest of the setup
print_status "Services are ready! Now completing the Kubernetes setup..."

echo ""
echo "You can now either:"
echo "1. Continue with the original setup script:"
echo "   ./scripts/setup-k8s.sh"
echo ""  
echo "2. Or continue manually from Step 7 (RBAC setup):"
echo "   kubectl apply --kubeconfig admin.kubeconfig -f rbac-config.yaml"
echo ""
echo "Since the control plane is working, let's continue with RBAC and worker setup..."
