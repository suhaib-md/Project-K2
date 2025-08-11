output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = module.load_balancer.lb_dns_name
}

output "controller_instances" {
  description = "Controller instance details"
  value = {
    for i, instance in module.controllers.instances : 
    instance.tags.Name => {
      instance_id = instance.id
      public_ip   = instance.public_ip
      private_ip  = instance.private_ip
    }
  }
}

output "worker_instances" {
  description = "Worker instance details"
  value = {
    for i, instance in module.workers.instances : 
    instance.tags.Name => {
      instance_id = instance.id
      public_ip   = instance.public_ip
      private_ip  = instance.private_ip
    }
  }
}

output "ssh_command" {
  description = "SSH command template"
  value       = "ssh -F ssh_config -i k8s-key.pem ubuntu@<instance-ip>"
}

output "kubeconfig_setup" {
  description = "Commands to set up kubeconfig on your local machine"
  value = <<-EOT
    # After terraform apply completes, run:
    export KUBERNETES_PUBLIC_ADDRESS=${module.load_balancer.lb_dns_name}
    
    # The setup script will generate admin.kubeconfig
    # Copy it to your kubectl config:
    mkdir -p ~/.kube
    cp admin.kubeconfig ~/.kube/config
    
    # Test the connection:
    kubectl get nodes
  EOT
}