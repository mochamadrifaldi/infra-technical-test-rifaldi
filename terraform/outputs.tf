output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of both public subnets"
  value       = aws_subnet.public[*].id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "security_group_id" {
  description = "ID of the web security group"
  value       = aws_security_group.web.id
}
