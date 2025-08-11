output "lb_security_group_id" {
  description = "ID of the load balancer security group"
  value       = aws_security_group.lb_sg.id
}

output "controller_security_group_id" {
  description = "ID of the controller security group"
  value       = aws_security_group.controller_sg.id
}

output "worker_security_group_id" {
  description = "ID of the worker security group"
  value       = aws_security_group.worker_sg.id
}