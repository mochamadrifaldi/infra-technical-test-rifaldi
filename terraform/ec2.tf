resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size            = var.root_volume_size
    delete_on_termination  = true
    encrypted               = true
  }

  # The HealthCheckPath value is deliberately documented here so that
  # a Target Group configuration (if an ALB is added later) always
  # matches a path that actually exists in the app. See the RCA
  # section (Part 4) in README.md for why this matters.
  tags = {
    Name              = "${var.project_name}-app"
    Environment       = var.environment
    HealthCheckPath   = "/api/health"
  }
}
