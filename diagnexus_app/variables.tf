variable "region" {
  default = "us-east-1"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name"
}

variable "db_username" {
  type        = string
  description = "RDS username"
}

variable "db_password" {
  type        = string
  description = "RDS password"
  sensitive   = true
}
