output "instances" {
  description = "EC2 instance details"
  value       = aws_instance.instances
}

output "instance_ids" {
  description = "List of instance IDs"
  value       = aws_instance.instances[*].id
}

output "public_ips" {
  description = "List of public IP addresses"
  value       = aws_instance.instances[*].public_ip
}

output "private_ips" {
  description = "List of private IP addresses"
  value       = aws_instance.instances[*].private_ip
}