terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
  default     = "buildkite-key"
}

variable "buildkite_agent_token" {
  description = "Buildkite agent token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_access_key" {
  description = "AWS access key"
  type        = string
  default     = ""
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
  sensitive   = true
  default     = ""
}

# Create VPC
resource "aws_vpc" "buildkite_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "buildkite-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "buildkite_igw" {
  vpc_id = aws_vpc.buildkite_vpc.id

  tags = {
    Name = "buildkite-igw"
  }
}

# Create public subnet
resource "aws_subnet" "buildkite_subnet" {
  vpc_id                  = aws_vpc.buildkite_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "buildkite-subnet"
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create key pair for SSH access
resource "aws_key_pair" "buildkite_key" {
  key_name   = "buildkite-key"
  public_key = tls_private_key.buildkite_key.public_key_openssh
}

# Generate private key
resource "tls_private_key" "buildkite_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key locally
resource "local_file" "private_key" {
  content  = tls_private_key.buildkite_key.private_key_pem
  filename = "buildkite-key.pem"
  file_permission = "0600"
}

# Create route table
resource "aws_route_table" "buildkite_rt" {
  vpc_id = aws_vpc.buildkite_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.buildkite_igw.id
  }

  tags = {
    Name = "buildkite-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "buildkite_rta" {
  subnet_id      = aws_subnet.buildkite_subnet.id
  route_table_id = aws_route_table.buildkite_rt.id
}

# Security group
resource "aws_security_group" "buildkite_sg" {
  name        = "buildkite-security-group"
  description = "Security group for Buildkite agent"
  vpc_id      = aws_vpc.buildkite_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "buildkite-sg"
  }
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script to install Buildkite agent and Docker
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    buildkite_agent_token = var.buildkite_agent_token
  }))
}

# EC2 instance
resource "aws_instance" "buildkite_agent" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.buildkite_key.key_name
  vpc_security_group_ids = [aws_security_group.buildkite_sg.id]
  subnet_id              = aws_subnet.buildkite_subnet.id
  user_data_base64       = local.user_data

  tags = {
    Name = "buildkite-agent"
  }
}

# Outputs
output "instance_public_ip" {
  description = "Public IP address of the Buildkite agent instance"
  value       = aws_instance.buildkite_agent.public_ip
}

output "instance_id" {
  description = "ID of the Buildkite agent instance"
  value       = aws_instance.buildkite_agent.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i buildkite-key.pem ubuntu@${aws_instance.buildkite_agent.public_ip}"
}
