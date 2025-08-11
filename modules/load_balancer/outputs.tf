output "lb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.k8s_api_lb.arn
}

output "lb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.k8s_api_lb.dns_name
}

output "lb_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.k8s_api_lb.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.k8s_api_tg.arn
}