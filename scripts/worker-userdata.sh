#!/bin/bash

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y wget curl socat conntrack ipset

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable IP forwarding and bridge networking
cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

modprobe br_netfilter
sysctl --system

# Create directories
mkdir -p /etc/kubernetes/config
mkdir -p /var/lib/kubelet/
mkdir -p /var/lib/kube-proxy/
mkdir -p /var/lib/kubernetes/
mkdir -p /var/run/kubernetes/
mkdir -p /etc/systemd/system/
mkdir -p /etc/cni/net.d/
mkdir -p /opt/cni/bin/

# Create user for kubernetes services
useradd -r -d /var/lib/kubernetes -s /bin/false kubernetes || true

# Set hostname based on instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Set hostname
hostnamectl set-hostname worker-${INSTANCE_ID: -1}

# Update /etc/hosts
echo "$PRIVATE_IP worker-${INSTANCE_ID: -1}" >> /etc/hosts

# Create setup completion marker
touch /tmp/cloud-init-complete

# Log completion
echo "$(date): Worker node initialization completed" >> /var/log/k8s-init.log