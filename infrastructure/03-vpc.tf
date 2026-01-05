# =============================================================================
# VPC - Virtual Private Cloud
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # Enable DNS hostnames for ECS
  enable_dns_support   = true # Enable DNS resolution

  tags = {
    Name        = "${var.project_name}-vpc"
    Description = "Private VPC for microservices"
  }
}

# =============================================================================
# Internet Gateway - For public subnets (ALB only)
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# =============================================================================
# Public Subnets - For ALB (Load Balancer needs to be public)
# =============================================================================

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # Public IPs for ALB

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  }
}

# =============================================================================
# Private Subnets - For ECS tasks (microservices run here)
# =============================================================================

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  }
}


# =============================================================================
# Route Tables
# =============================================================================

# Public route table - routes to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Private route table - uses VPC Endpoints for AWS services
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# VPC Endpoints - Private connection to AWS services (NO INTERNET!)
# =============================================================================

# S3 Gateway Endpoint - Free! No data transfer charges within same region
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name        = "${var.project_name}-s3-endpoint"
    Description = "Private connection to S3 - no internet required"
  }
}

# SQS Interface Endpoint - Private connection to SQS
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = aws_subnet.private[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project_name}-sqs-endpoint"
    Description = "Private connection to SQS - no internet required"
  }
}

# SSM Interface Endpoint - Private connection to SSM Parameter Store
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = aws_subnet.private[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project_name}-ssm-endpoint"
    Description = "Private connection to SSM - no internet required"
  }
}

# ECR API Endpoint - For pulling Docker images
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = aws_subnet.private[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.project_name}-ecr-api-endpoint"
  }
}

# ECR Docker Endpoint - For pulling Docker image layers
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = aws_subnet.private[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.project_name}-ecr-dkr-endpoint"
  }
}

# =============================================================================
# Security Groups
# =============================================================================

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg"
  }
}

# =============================================================================
# Application Load Balancer Security Group
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP from anywhere (public access)
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS from anywhere (for future SSL)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound to ECS tasks
  egress {
    description = "Allow outbound to ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Description = "Allows HTTP/HTTPS from internet"
  }
}

# =============================================================================
# ECS Service 1 Security Group (REST API)
# =============================================================================

resource "aws_security_group" "service1" {
  name        = "${var.project_name}-service1-sg"
  description = "Security group for Service 1 (REST API)"
  vpc_id      = aws_vpc.main.id

  # Allow traffic ONLY from ALB on port 8080
  ingress {
    description     = "Allow traffic from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound (for VPC endpoints)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-service1-sg"
    Description = "Allows traffic only from ALB"
  }
}

# =============================================================================
# ECS Service 2 Security Group (SQS Consumer)
# =============================================================================

resource "aws_security_group" "service2" {
  name        = "${var.project_name}-service2-sg"
  description = "Security group for Service 2 (SQS Consumer)"
  vpc_id      = aws_vpc.main.id

  # No ingress - service2 doesn't accept incoming connections
  # It only polls SQS and writes to S3

  # Allow all outbound (for VPC endpoints)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-service2-sg"
    Description = "No ingress - only outbound for SQS and S3"
  }
}
