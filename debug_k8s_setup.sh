#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_header "Debugging Kubernetes Setup Issues"

# Check if we have the required files
print_status "Checking local files..."
echo "Current directory: $(pwd)"
echo "Files in current directory:"
ls -la

echo ""
echo "Files in certs directory:"
ls -la certs/ 2>/dev/null || echo "No certs directory found"

echo ""
echo "Files in kubeconfigs directory:"
ls -la kubeconfigs/ 2>/dev/null || echo "No kubeconfigs directory found"

# Check SSH connectivity
print_status "Testing SSH connectivity to controller..."
if ssh -F ssh_config -o ConnectTimeout=10 controller-0 'echo "SSH test successful"' 2>/dev/null; then
    print_success "SSH connectivity to controller-0 is working"
else
    print_error "SSH connectivity to controller-0 failed"
    echo "Let's check the SSH config:"
    cat ssh_config 2>/dev/null || echo "No ssh_config file found"
    exit 1
fi

# Check what's on the controller
print_status "Checking controller state..."
ssh -F ssh_config controller-0 '
    echo "=== Controller filesystem ==="
    echo "Files in /tmp:"
    ls -la /tmp/
    echo ""
    echo "Files in /var/lib/kubernetes:"
    sudo ls -la /var/lib/kubernetes/ 2>/dev/null || echo "Directory does not exist"
    echo ""
    echo "Kubernetes processes:"
    ps aux | grep kube | grep -v grep || echo "No kubernetes processes found"
    echo ""
    echo "Systemd services status:"
    sudo systemctl status kube-apiserver --no-pager -l || echo "kube-apiserver not found"
    echo ""
    sudo systemctl status etcd --no-pager -l || echo "etcd not found"
    echo ""
    echo "Network connectivity:"
    netstat -tlnp | grep -E ":6443|:2379|:2380" || echo "No kubernetes ports listening"
    echo ""
    echo "Recent logs:"
    sudo journalctl -u kube-apiserver --since "5 minutes ago" --no-pager || echo "No apiserver logs"
'

print_header "Diagnosis Complete"
echo "Based on the output above, here are the likely issues and solutions:"
echo ""
echo "1. If certificates are missing from /tmp/ on the controller:"
echo "   - The certificate distribution step failed"
echo "   - Solution: Re-run certificate distribution manually"
echo ""
echo "2. If kube-apiserver is not running:"
echo "   - Check systemd logs for errors"
echo "   - Verify certificate paths in service files"
echo "   - Check if etcd is running and accessible"
echo ""
echo "3. If etcd is not running:"
echo "   - Check etcd systemd service status"
echo "   - Verify etcd configuration and certificates"
echo ""

print_status "To fix the issues, you can run the following commands:"
echo ""
echo "# 1. Clean up and restart"
echo "terraform destroy -auto-approve"
echo "terraform apply -auto-approve"
echo ""
echo "# 2. Or manually fix certificate distribution:"
echo "./fix_certificate_distribution.sh"
echo ""
echo "# 3. Or check logs in detail:"
echo "./check_detailed_logs.sh"
