# variables.tf
variable "aws_region" {
  description = "aws region to deploy resources"
  default     = "eu-west-2"
}

variable "subnet_cidr_blocks" {
  type    = list(string)
  default = ["10.0.1.0/28", "10.0.2.0/28"]
}

variable "availability_zone" {
  description = "aws AZ to deploy resources"
  default     = "eu-west-2a"
}

variable "app_name" {
  description = "name of the node.js application."
  default     = "nodejs-app"
}
