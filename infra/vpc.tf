
# VPC Configuration
resource "aws_vpc" "game_server_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.game_server_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ca-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "game-server-public"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.game_server_vpc.id
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.game_server_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "game-server-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# Combined Security Group
resource "aws_security_group" "game_server_sg" {
  name        = "satiserver-ports-sg"
  description = "Security group for all game server ports"
  vpc_id      = aws_vpc.game_server_vpc.id
}

# Game Port Rules
resource "aws_security_group_rule" "game_port" {
  type              = "ingress"
  from_port         = 7777
  to_port           = 7777
  protocol          = "udp"
  cidr_blocks       = var.players_ips
  description       = "Game port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "game_port_tcp" {
  type              = "ingress"
  from_port         = 7777
  to_port           = 7777
  protocol          = "tcp"
  cidr_blocks       = var.players_ips
  description       = "Game port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "beacon_port" {
  type              = "ingress"
  from_port         = 15000
  to_port           = 15000
  protocol          = "udp"
  cidr_blocks       = var.players_ips
  description       = "Beacon port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "beacon_port_tcp" {
  type              = "ingress"
  from_port         = 15000
  to_port           = 15000
  protocol          = "tcp"
  cidr_blocks       = var.players_ips
  description       = "Beacon port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "query_port" {
  type              = "ingress"
  from_port         = 15077
  to_port           = 15077
  protocol          = "udp"
  cidr_blocks       = var.players_ips
  description       = "Query port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "query_port_tcp" {
  type              = "ingress"
  from_port         = 15077
  to_port           = 15077
  protocol          = "tcp"
  cidr_blocks       = var.players_ips
  description       = "Query port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "admin_port" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.players_ips
  description       = "admin port access"
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.game_server_sg.id
}

resource "aws_security_group_rule" "ec2_instance_connect" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["35.183.92.176/29"]
  description       = "EC2 Instance Connect service access"
  security_group_id = aws_security_group.game_server_sg.id
}
