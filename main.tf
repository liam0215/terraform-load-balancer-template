provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

resource "aws_vpc" "test-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "prod_test"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.test-vpc.id

  tags = {
    Name = "terraform-example-internet-gateway"
  }
}

resource "aws_subnet" "main" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.test-vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "public-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

resource "aws_route" "route" {
  route_table_id         = aws_vpc.test-vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gateway.id
}

resource "aws_security_group" "default" {
  name        = "test_security_group"
  description = "Test security group"
  vpc_id      = aws_vpc.test-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  # Allow outbound internet access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "test-security-group"
  }
}

resource "aws_security_group" "elb" {
  name        = "elb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = aws_vpc.test-vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elb-security-group"
  }
}

resource "aws_elb" "elb" {
  name            = "terraform-elb"
  security_groups = ["${aws_security_group.elb.id}"]
  subnets         = [for subnet in aws_subnet.main : subnet.id]

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = var.certificate_arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = []
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "terraform-elb"
  }
}

resource "aws_route53_record" "terraform" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "terraform.${var.route53_hosted_zone_name}"
  type    = "A"
  alias {
    name                   = aws_elb.elb.dns_name
    zone_id                = aws_elb.elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_network_interface" "test_network_interface" {
  count           = length(data.aws_availability_zones.available.names)
  subnet_id       = aws_subnet.main[count.index].id
  private_ips     = ["${substr(aws_subnet.main[count.index].cidr_block, 0, 6)}.50"]
  security_groups = ["${aws_security_group.default.id}"]

  tags = {
    Name = "kabcash_test_network_interface"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "terraform_deployer"
  public_key = file(var.public_key_path)
}

resource "aws_instance" "web_server_instance" {
  count             = length(data.aws_availability_zones.available.names)
  ami               = "ami-09e67e426f25ce0d7"
  instance_type     = "t2.micro"
  availability_zone = aws_subnet.main[count.index].availability_zone
  key_name          = aws_key_pair.deployer.id

  network_interface {
    network_interface_id = aws_network_interface.test_network_interface[count.index].id
    device_index         = 0
  }

  tags = {
    Name = "test_instance"
  }
}
