output "vpc_id" {
  value = aws_vpc.my_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.my_subnets[*].id
}

output "security_group_id" {
  value = aws_security_group.ecs_sg.id
}

output "app_url" {
  value = aws_ecs_service.my_service.endpoint
}