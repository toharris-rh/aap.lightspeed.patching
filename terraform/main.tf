# ---------------------------------------------------------------------------
# Networking — VPC, public subnet, IGW, route table, security group.
# ---------------------------------------------------------------------------

resource "aws_vpc" "demo" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "lsp-vpc-${local.name_suffix}" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "lsp-public-${local.name_suffix}" })
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = merge(local.common_tags, { Name = "lsp-igw-${local.name_suffix}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = merge(local.common_tags, { Name = "lsp-rt-${local.name_suffix}" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "demo" {
  name_prefix = "lsp-sg-"
  # ASCII only — AWS rejects non-ASCII in a security group GroupDescription.
  description = "Lightspeed Patching demo - SSH, HTTP/S, ICMP, Cockpit"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_source_cidrs
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_source_cidrs
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_source_cidrs
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = var.allowed_source_cidrs
  }

  ingress {
    description = "Cockpit"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_source_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "lsp-sg-${local.name_suffix}" })
}

# ---------------------------------------------------------------------------
# SSH key pair — injected from LINUX_SSH_PUBLIC_KEY env var.
# ---------------------------------------------------------------------------

resource "aws_key_pair" "demo" {
  key_name   = "lsp-key-${local.name_suffix}"
  public_key = var.linux_ssh_public_key

  tags = merge(local.common_tags, { Name = "lsp-key-${local.name_suffix}" })
}

# ---------------------------------------------------------------------------
# RHEL 9 EC2 instance.
# ---------------------------------------------------------------------------

resource "aws_instance" "rhel" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = local.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.demo.id]
  key_name               = aws_key_pair.demo.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name     = local.vm_name
    OS       = "rhel9"
    Hostname = local.vm_name
  })
}
