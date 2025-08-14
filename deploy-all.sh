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
    echo -e "${BLUE}$1${NC}"
}

# Banner
echo -e "${GREEN}"
cat << 'EOF'
╦╔═╗╦ ╦╔╗ ╔═╗╦═╗╔╗╔╔═╗╔╦╗╔═╗╔═╗  ╔╦╗╦ ╦╔═╗  ╦ ╦╔═╗╦═╗╔╦╗  ╦ ╦╔═╗╦ ╦
╠╩╗ ║ ║╠╩╗║╣ ╠╦╝║║║║╣  ║ ║╣ ╚═╗   ║ ╠═╣║╣   ╠═╣╠═╣╠╦╝ ║║  ║║║╠═╣╚╦╝
╩ ╩ ╚═╝╚═╝╚═╝╩╚═╝╚╝╚═╝ ╩ ╚═╝╚═╝   ╩ ╩ ╩╚═╝  ╩ ╩╩ ╩╩╚══╩╝  ╚╩╝╩ ╩ ╩ 
Automated Terraform Deployment
EOF
echo -e "${NC}"

# Check prerequisites
print_header "=== Checking Prerequisites ==="

# Check if we're in WSL
if ! grep -q microsoft /proc/version; then
    print_error "This script is designed to run in WSL (Windows Subsystem for Linux)"
    exit 1
fi

# Check required tools
MISSING_TOOLS=""

if ! command -v terraform &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS terraform"
fi

if ! command -v aws &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS aws-cli"
fi

if ! command -v kubectl &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS kubectl"
fi

if ! command -v cfssl &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS cfssl"
fi

if [ -n "$MISSING_TOOLS" ]; then
    print_error "Missing required tools:$MISSING_TOOLS"
    print_status "Please run setup-wsl-jumpbox.sh first to install all prerequisites"
    exit 1
fi

# Check AWS credentials
print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured!"
    print_status "Please run: aws configure"
    exit 1
fi

print_success "All prerequisites satisfied!"

# Validate Terraform files
print_header "=== Validating Terraform Configuration ==="

if [ ! -f "main.tf" ]; then
    print_error "main.tf not found in current directory"
    print_status "Please ensure all Terraform files are in the current directory"
    exit 1
fi

print_status "Initializing Terraform..."
terraform init

print_status "Validating Terraform configuration..."
terraform validate

print_status "Planning deployment..."
terraform plan -out=tfplan

print_success "Terraform validation completed!"

# Confirm deployment
print_header "=== Deployment Confirmation ==="
echo -e "${YELLOW}"
echo "This will create the following AWS resources:"
echo "  - 1 VPC with public/private subnets"
echo "  - 1 Controller nodes (t3.small)"
echo "  - 2 Worker nodes (t3.small)" 
echo "  - 1 Network Load Balancer"
echo "  - Security groups and networking"
echo "  - SSH key pair"
echo ""
echo "Estimated monthly cost: ~\$50-80 USD"
echo "Remember to destroy resources when done learning!"
echo -e "${NC}"

read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_status "Deployment cancelled"
    exit 0
fi

# Deploy infrastructure
print_header "=== Deploying Infrastructure ==="
print_status "Starting Terraform apply..."
terraform apply tfplan

print_success "Infrastructure deployment completed!"

# Wait for instances to be fully ready
print_status "Waiting for instances to be fully initialized..."
sleep 90

# Test SSH connectivity
print_header "=== Testing Connectivity ==="
print_status "Testing SSH connectivity to all nodes..."

# Test controller connectivity
for i in {0..2}; do
    if ssh -F ssh_config -o ConnectTimeout=10 controller-$i 'echo "Controller-$i is reachable"' &> /dev/null; then
        print_success "Controller-$i is reachable"
    else
        print_error "Controller-$i is not reachable"
    fi
done

# Test worker connectivity
for i in {0..2}; do
    if ssh -F ssh_config -o ConnectTimeout=10 worker-$i 'echo "Worker-$i is reachable"' &> /dev/null; then
        print_success "Worker-$i is reachable"
    else
        print_error "Worker-$i is not reachable"
    fi
done

# Final verification
print_header "=== Final Verification ==="
print_status "Checking cluster status..."

# Wait a bit more for all services to be ready
sleep 60

# Test kubectl connectivity
if kubectl --kubeconfig=admin.kubeconfig get nodes &> /dev/null; then
    print_success "Kubernetes API is accessible!"
    
    echo -e "${GREEN}"
    echo "=== Cluster Information ==="
    kubectl --kubeconfig=admin.kubeconfig get nodes -o wide
    echo ""
    kubectl --kubeconfig=admin.kubeconfig get pods --all-namespaces
    echo -e "${NC}"
else
    print_error "Kubernetes API is not yet accessible. This might be normal - the cluster may still be initializing."
    print_status "You can check the setup progress by running:"
    echo "  ./helper-scripts/check-cluster.sh"
fi

# Display final information
print_header "=== Deployment Summary ==="
echo -e "${GREEN}"
echo "=============================================="
echo "  Kubernetes The Hard Way Deployment Complete!"
echo "=============================================="
echo -e "${NC}"

echo "Kubernetes API Endpoint: $(terraform output -raw kubernetes_api_endpoint)"
echo "Admin Kubeconfig: admin.kubeconfig"
echo "SSH Config: ssh_config"
echo "Private Key: k8s-key.pem"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Set up kubectl locally:"
echo "   export KUBECONFIG=\$PWD/admin.kubeconfig"
echo "   # Or copy to default location:"
echo "   cp admin.kubeconfig ~/.kube/config"
echo ""
echo "2. Test your cluster:"
echo "   kubectl get nodes"
echo "   kubectl get pods --all-namespaces"
echo ""
echo "3. Deploy a test application:"
echo "   kubectl create deployment nginx --image=nginx"
echo "   kubectl expose deployment nginx --port=80 --type=NodePort"
echo ""
echo "4. SSH to nodes:"
echo "   ssh -F ssh_config controller-0"
echo "   ssh -F ssh_config worker-0"
echo ""

echo -e "${YELLOW}Helper Scripts:${NC}"
echo "- ./helper-scripts/check-cluster.sh - Check cluster status"
echo "- ./helper-scripts/restart-services.sh - Restart all services"
echo "- ./helper-scripts/cleanup.sh - Destroy all resources"
echo ""

echo -e "${RED}Important:${NC}"
echo "- Don't forget to run 'terraform destroy' when you're done"
echo "- Keep your k8s-key.pem file secure"
echo "- All nodes are publicly accessible (for learning only)"
echo ""

print_success "Deployment completed successfully!"

# Source bashrc to load aliases
source ~/.bashrc 2>/dev/null || true

echo -e "${GREEN}Happy learning with Kubernetes The Hard Way!${NC}"
