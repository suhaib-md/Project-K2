# Kubernetes The Hard Way - Complete Terraform Automation

This is a complete automation of Kelsey Hightower's "Kubernetes The Hard Way" using Terraform on AWS, designed to run from WSL2 Debian.

## 🐛 Troubleshooting

### Common Issues and Solutions

#### 1. Terraform Apply Fails
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check for resource limits
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A

# Re-run with detailed logging
TF_LOG=DEBUG terraform apply
```

#### 2. SSH Connection Issues
```bash
# Wait longer for instances to initialize
sleep 120

# Check security groups allow SSH (port 22)
aws ec2 describe-security-groups --group-ids <sg-id>

# Verify SSH key permissions
chmod 600 k8s-key.pem
```

#### 3. API Server Not Responding
```bash
# Check etcd status on controllers
ssh -F ssh_config controller-0 'sudo systemctl status etcd'

# Check API server logs
ssh -F ssh_config controller-0 'sudo journalctl -u kube-apiserver -f'

# Verify load balancer health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

#### 4. Nodes Not Joining Cluster
```bash
# Check kubelet logs on workers
ssh -F ssh_config worker-0 'sudo journalctl -u kubelet -f'

# Verify certificates
ssh -F ssh_config worker-0 'sudo openssl x509 -in /var/lib/kubelet/worker-0.pem -text -noout'

# Check network connectivity
ssh -F ssh_config worker-0 'curl -k https://<controller-ip>:6443/version'
```

#### 5. Pod Network Issues
```bash
# Check Weave Net pods
kubectl get pods -n kube-system | grep weave

# Check Weave Net logs
kubectl logs -n kube-system daemonset/weave-net

# Restart Weave Net if needed
kubectl delete pods -n kube-system -l name=weave-net
```

### Log Locations

**On Controllers:**
- etcd: `sudo journalctl -u etcd`
- API server: `sudo journalctl -u kube-apiserver`
- Controller manager: `sudo journalctl -u kube-controller-manager`
- Scheduler: `sudo journalctl -u kube-scheduler`

**On Workers:**
- containerd: `sudo journalctl -u containerd`
- kubelet: `sudo journalctl -u kubelet`
- kube-proxy: `sudo journalctl -u kube-proxy`

## 🔧 Customization

### Change Instance Types
Edit `terraform.tfvars`:
```hcl
controller_instance_type = "t3.medium"  # For better performance
worker_instance_type     = "t3.medium"
```

### Change Region
Edit `terraform.tfvars`:
```hcl
aws_region = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

### Scale Workers
Edit the worker count in `main.tf`:
```hcl
module "workers" {
  instance_count = 5  # Change from 3 to 5
  # ... rest of configuration
}
```

## 📊 Monitoring and Observability

### Built-in Monitoring
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage  
kubectl top pods --all-namespaces

# Cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Manual Health Checks
```bash
# etcd cluster health
ssh -F ssh_config controller-0 'sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem endpoint health --cluster'

# API server health
curl -k https://$(terraform output -raw load_balancer_dns):6443/healthz

# Worker node readiness
kubectl describe nodes
```

## 🔐 Security Considerations

### For Learning Environment
- ✅ All certificates properly generated and distributed
- ✅ RBAC enabled with proper permissions
- ✅ Network policies supported (via CNI)
- ⚠️ Nodes have public IPs (acceptable for learning)
- ⚠️ SSH access from anywhere (acceptable for learning)

### For Production
Consider these improvements:
- Use private subnets for nodes
- Implement bastion host for SSH access
- Enable VPC Flow Logs
- Use AWS IAM roles for service accounts
- Implement network policies
- Enable audit logging
- Use AWS KMS for etcd encryption
- Implement backup strategies

## 💰 Cost Optimization

### During Learning
```bash
# Stop instances when not in use
aws ec2 stop-instances --instance-ids $(terraform output -json | jq -r '.controller_instances.value[].instance_id, .worker_instances.value[].instance_id')

# Start instances when needed
aws ec2 start-instances --instance-ids $(terraform output -json | jq -r '.controller_instances.value[].instance_id, .worker_instances.value[].instance_id')
```

### For Extended Learning
- Use Spot Instances (modify compute module)
- Use smaller instance types for workers
- Deploy in a single AZ to reduce data transfer costs

## 🎓 Learning Path

After successful deployment, try these exercises:

1. **Basic Operations**
   - Deploy various workload types
   - Create services and ingress
   - Work with ConfigMaps and Secrets

2. **Cluster Operations**
   - Add/remove worker nodes
   - Upgrade Kubernetes version
   - Backup and restore etcd

3. **Networking**
   - Implement NetworkPolicies
   - Set up Ingress controllers
   - Explore service mesh (Istio/Linkerd)

4. **Storage**
   - Deploy persistent workloads
   - Use AWS EBS CSI driver
   - Implement StatefulSets

5. **Monitoring**
   - Deploy Prometheus and Grafana
   - Set up logging with ELK stack
   - Implement alerting

## 🧹 Cleanup

### Quick Cleanup
```bash
# Destroy all resources
./helper-scripts/cleanup.sh
```

### Manual Cleanup
```bash
# Destroy Terraform resources
terraform destroy

# Clean up local files
rm -rf certs/ kubeconfigs/
rm -f *.pem *.kubeconfig ssh_config inventory.ini encryption-config.yaml
```

### Verify Cleanup
```bash
# Check for remaining resources
aws ec2 describe-instances --filters "Name=tag:Project,Values=kubernetes-the-hard-way"
aws elbv2 describe-load-balancers --names k8s-api-lb
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-the-hard-way-vpc"
```

## 🆘 Emergency Procedures

### Complete Reset
```bash
# 1. Destroy infrastructure
terraform destroy -auto-approve

# 2. Clean local state
rm -rf .terraform/ *.tfstate* *.tfplan
rm -rf certs/ kubeconfigs/ *.pem *.kubeconfig

# 3. Re-initialize
terraform init
```

### Partial Recovery
```bash
# Re-run just the Kubernetes setup
./scripts/setup-k8s.sh

# Or restart all services
./helper-scripts/restart-services.sh
```

## 📚 Additional Resources

- [Kubernetes The Hard Way Original](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## 🤝 Contributing

This project is for educational purposes. To improve it:

1. Fork the repository
2. Create feature branch
3. Test thoroughly
4. Submit pull request

## ⚖️ License

This project follows the same license as the original Kubernetes The Hard Way.

## ⚠️ Disclaimer

- This is for educational purposes only
- Not suitable for production workloads
- Always destroy resources after learning to avoid costs
- Review AWS billing regularly

---

**Happy Learning! 🎉**

Remember: The goal is to understand how Kubernetes works under the hood. Take time to explore each component and understand what's happening at each step.🚀 Quick Start (One Command Deployment)

```bash
# 1. Set up your environment
./setup-wsl-jumpbox.sh

# 2. Configure AWS
aws configure

# 3. Deploy everything
./deploy-all.sh
```

## 📋 Prerequisites

### WSL2 Setup
- Windows 10/11 with WSL2 enabled
- Debian or Ubuntu distribution installed
- At least 4GB RAM allocated to WSL

### AWS Requirements
- AWS account with programmatic access
- IAM user with permissions for:
  - EC2 (full access)
  - VPC (full access)
  - ELB (full access)
  - IAM (read access for instance profiles)

### Required Permissions Policy
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "elasticloadbalancing:*",
                "iam:PassRole",
                "iam:GetRole",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:CreateInstanceProfile",
                "iam:AddRoleToInstanceProfile"
            ],
            "Resource": "*"
        }
    ]
}
```

## 📁 Project Structure

After running the setup, your project will look like this:

```
~/kubernetes-the-hard-way/
├── main.tf                          # Root configuration
├── variables.tf                     # Variable definitions  
├── outputs.tf                       # Outputs
├── terraform.tfvars                 # Variable values
├── modules/
│   ├── networking/                  # VPC, subnets, routing
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/                    # Security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/                     # EC2 instances
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── load_balancer/               # Network Load Balancer
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── scripts/
│   ├── controller-userdata.sh       # Controller cloud-init
│   ├── worker-userdata.sh          # Worker cloud-init
│   └── setup-k8s.sh               # Main Kubernetes setup
├── templates/
│   ├── inventory.tpl               # Ansible-style inventory
│   └── ssh_config.tpl              # SSH configuration
├── helper-scripts/
│   ├── check-cluster.sh            # Cluster status
│   ├── restart-services.sh         # Restart services
│   └── cleanup.sh                  # Resource cleanup
├── setup-wsl-jumpbox.sh            # WSL environment setup
├── deploy-all.sh                   # Complete deployment
├── create-project-structure.sh     # Project structure setup
└── README.md                       # This file
```

## 🔧 Manual Step-by-Step Setup

### Step 1: Prepare WSL Environment

```bash
# Run the WSL setup script
chmod +x setup-wsl-jumpbox.sh
./setup-wsl-jumpbox.sh
```

This installs:
- Terraform
- AWS CLI v2
- kubectl
- cfssl/cfssljson
- Required dependencies

### Step 2: Configure AWS

```bash
aws configure
```

Enter your:
- AWS Access Key ID
- AWS Secret Access Key  
- Default region (e.g., `us-west-2`)
- Default output format (`json`)

### Step 3: Create Project Structure

```bash
# Create the directory structure
./create-project-structure.sh

# Navigate to project directory
cd ~/kubernetes-the-hard-way
```

### Step 4: Copy Terraform Files

Copy all the Terraform files provided into your project directory:

```bash
# Copy all .tf files to project root
# Copy module files to respective module directories
# Copy scripts to scripts/ directory
# Copy templates to templates/ directory
```

### Step 5: Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy (this will take 10-15 minutes)
terraform apply
```

## 🎯 What Gets Deployed

### Infrastructure
- **VPC**: 10.240.0.0/16 with public/private subnets
- **Load Balancer**: Network LB for Kubernetes API (port 6443)
- **Security Groups**: Properly configured for K8s communication
- **EC2 Instances**: 3 controllers + 3 workers (t3.small)

### Kubernetes Components
- **etcd**: 3-node cluster on controllers
- **API Server**: HA setup behind load balancer
- **Controller Manager**: Leader election enabled
- **Scheduler**: Leader election enabled
- **kubelet**: On all worker nodes
- **kube-proxy**: On all worker nodes
- **Weave Net**: Pod networking (10.200.0.0/16)

### Certificates Generated
- CA certificate and key
- API server certificate
- Controller manager certificate
- Scheduler certificate
- Admin certificate
- Worker node certificates
- Service account certificate

### Kubeconfig Files
- admin.kubeconfig (for cluster administration)
- Controller manager kubeconfig
- Scheduler kubeconfig
- Worker node kubeconfigs
- Kube-proxy kubeconfig

## 🔍 Post-Deployment Verification

### Check Infrastructure
```bash
# View Terraform outputs
terraform output

# Test SSH connectivity
ssh -F ssh_config controller-0 'hostname'
ssh -F ssh_config worker-0 'hostname'
```

### Check Kubernetes Cluster
```bash
# Set kubeconfig
export KUBECONFIG=$PWD/admin.kubeconfig

# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods --all-namespaces

# Check component status
kubectl get cs

# Check cluster info
kubectl cluster-info
```

### Test Pod Deployment
```bash
# Deploy test application
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# Check deployment
kubectl get deployments
kubectl get services
kubectl get pods
```

##