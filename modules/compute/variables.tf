variable "instance_count" {
  description = "Number of instances to create"
  type        = number
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "AWS key pair name"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "name_prefix" {
  description = "Prefix for instance names"
  type        = string
}

variable "user_data" {
  description = "User data script"
  type        = string
  default     = ""
}

variable "target_group_arn" {
  description = "Target group ARN for load balancer"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}