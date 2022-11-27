
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}
provider "aws" {
  region = "us-west-2"
}
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = {
    Name = "main"
  }
}
# Public subnets
resource "aws_subnet" "publicsubnet1" {
  depends_on = [
    aws_vpc.main
  ]

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.0.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet1"
  }
}

resource "aws_subnet" "publicsubnet2" {
  depends_on = [
    aws_vpc.main
  ]

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet2"
  }
}
# App Server Private subnets
resource "aws_subnet" "wpsubnet1" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1
  ]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "WP Subnet 1"
  }
}

resource "aws_subnet" "wpsubnet2" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet2
  ]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "WP Subnet 2"
  }
}

# DB Private subnets
resource "aws_subnet" "dbsubnet1" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.wpsubnet1
  ]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "DB Subnet 1"
  }
}

resource "aws_subnet" "dbsubnet2" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.wpsubnet2
  ]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.5.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "DB Subnet 2"
  }
}

# IG for Public Subnets
resource "aws_internet_gateway" "Internet_Gateway" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2
  ]

  vpc_id = aws_vpc.main.id
  tags = {
    Name = "IG-Public-Subnets"
  }
}

# Creating an Route Table for the public subnet!
resource "aws_route_table" "Public-Subnet-RT" {
  depends_on = [
    aws_vpc.main,
    aws_internet_gateway.Internet_Gateway
  ]

  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Internet_Gateway.id
  }

  tags = {
    Name = "Route Table IGW"
  }
}

# Creating a resource for the Route Table Association!
resource "aws_route_table_association" "RT-IG-Association1" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2,
    aws_route_table.Public-Subnet-RT
  ]

  subnet_id      = aws_subnet.publicsubnet1.id
  route_table_id = aws_route_table.Public-Subnet-RT.id
}

resource "aws_route_table_association" "RT-IG-Association2" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2,
    aws_route_table.Public-Subnet-RT
  ]

  subnet_id      = aws_subnet.publicsubnet2.id
  route_table_id = aws_route_table.Public-Subnet-RT.id
}

# Creating security group for Bastion Host/Jump Box
resource "aws_security_group" "BH-SG" {

  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2
  ]

  description = "Bastion RDP Security Group"
  name        = "bastion-host-sg"
  vpc_id      = aws_vpc.main.id

  # Created an inbound rule for Bastion Host SSH
  ingress {
    description = "RDP from my house only"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["65.43.36.169/32"]
  }

  egress {
    description = "output from Bastion Host"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Creating security group for ALB
resource "aws_security_group" "ALB-SG" {

  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2
  ]

  description = "WP ALB SG"
  name        = "alb-sg"
  vpc_id      = aws_vpc.main.id

  # Created an inbound rule for ALB
  ingress {
    description = "Allow Users to reach ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow Users to reach ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    description = "output from Bastion Host"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Creating security group for WP Servers
resource "aws_security_group" "WPServerSG" {

  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2,
    aws_security_group.BH-SG,
    aws_security_group.ALB-SG
  ]

  description = "To allow app servers to communicate and be accessed from bastion"
  name        = "wpserver-sg"
  vpc_id      = aws_vpc.main.id

  # Created an inbound rule for WP Servers
  ingress {
    description = "PostGres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.1.4.0/24"]
  }
  ingress {
    description = "PostGres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.1.5.0/24"]
  }
  ingress {
    description     = "Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.BH-SG.id}"]
  }
  ingress {
    description = "WordPress Ports"
    from_port   = 110
    to_port     = 110
    protocol    = "tcp"
    self        = true
  }
  ingress {
    description = "WordPress Ports"
    from_port   = 143
    to_port     = 143
    protocol    = "tcp"
    self        = "true"
  }
  ingress {
    description = "WordPress Ports"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self        = "true"
  }
  ingress {
    description = "WordPress Ports"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = "true"
  }
  ingress {
    description     = "Allow ALB Inbound"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ALB-SG.id}"]
  }
  ingress {
    description     = "WordPress Ports"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ALB-SG.id}"]
  }


  egress {
    description = "output from WPServers"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Created an inbound rule for Postgres
#resource "aws_db_security_group" "PostgresSG" {
# depends_on = [
#  aws_vpc.main,
# aws_subnet.publicsubnet1,
#aws_subnet.publicsubnet2,
#aws_security_group.BH-SG,
#aws_security_group.WPServerSG

# ]

# description = "To allow app servers to communicate and be accessed from bastion"
# name        = "PostgresSG"


# ingress {
#  cidr = "10.1.0.0/24"
# }
#}

#Creating the ALB
resource "aws_alb" "alb" {
  name            = "WPServersALB"
  security_groups = ["${aws_security_group.ALB-SG.id}"]
  subnets         = ["${aws_subnet.wpsubnet1.id}", "${aws_subnet.wpsubnet2.id}"]
}

#Creating EC2 Instances
resource "aws_instance" "bastion" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2,
    aws_route_table.Public-Subnet-RT
  ]
  ami                         = "ami-0c12b5d624d73f1c0"
  instance_type               = "t3a.medium"
  subnet_id                   = aws_subnet.publicsubnet1.id
  associate_public_ip_address = "true"
  security_groups             = ["${aws_security_group.BH-SG.id}"]
  user_data                   = file("windowsconfig.txt")
  root_block_device {
    volume_size = 50
  }
  tags = {
    Name = "bastion1"
  }
}
resource "aws_instance" "WPServer1" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2,
    aws_route_table.Public-Subnet-RT
  ]
  ami             = "ami-0b6ce9bcd0a2f720d"
  instance_type   = "t3a.medium"
  subnet_id       = aws_subnet.wpsubnet1.id
  security_groups = ["${aws_security_group.WPServerSG.id}"]
  user_data       = file("rhconfig1.txt")
  key_name        = "rhkey-key"
  root_block_device {
    volume_size = 20
  }
  tags = {
    Name = "WPServer1"
  }
}
resource "aws_instance" "WPServer2" {
  depends_on = [
    aws_vpc.main,
    aws_subnet.publicsubnet1,
    aws_subnet.publicsubnet2,
    aws_route_table.Public-Subnet-RT
  ]
  ami             = "ami-0b6ce9bcd0a2f720d"
  instance_type   = "t3a.medium"
  subnet_id       = aws_subnet.wpsubnet2.id
  security_groups = ["${aws_security_group.WPServerSG.id}"]
  user_data       = file("rhconfig2.txt")
  key_name        = "rhkey-key"
  root_block_device {
    volume_size = 20
  }
  tags = {
    Name = "WPServer2"
  }
}
# Creating Key Pair
resource "aws_key_pair" "rhkey" {
  key_name   = "rhkey-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCNTI17ZdocpE/DCA2pDBYVxiQwgeku1tBH4silr56tQn2vuhQL1i5Gux4L7jUzJYzyw+Xw2Z0k11ly3ZWIrzVBKIcTEf9aJWlxvYd3nA0XP560Lm+oRCFeQN8+FqoGhv/Mw2UjEPmWH+s0VV8NAWRCNa5CAqMlxdBqvO5CQY6bn9I59S/7AzjM05x+pFAKV1jOuVEKBLDvKzhOMSiNIKiQqeoi2o20pKtBmMx9pEUscLQvP3Wunv/pSgCkJB/B5a6AMRs4VagdWbrjzBa7PkCIvjw1ZHUgEBMvxhgS5F11FdXPQtOvuqoOHb9KVU4/KHVP77B5mJb0vegDmWA+xDNmCKpq+7w9L3+gb3AxHiGVfs1SL43kPAMLNgqKOAAZ/3daJn3Q6Tb4sJ4r1ekrYEif8Bxq1635Ab1PjT4S7R5gWHYVflj4UCw1LcE8r0dLnzp7rB3npK2EyUgIJ9bCD8HsN14tV0KlV0BWl/uFPIj+z8vYEfZPVswY6WGIddMh3DEiSDTfL+NL55mjTw57MqXI2++osZkh7LHCu0XL0OGXTUYU79JGolMJDvUsRuPVTzvWL+5wypZFJgKco1omDECa/6N6qGmxnPI4G2B/IlGssf/SIjW5OdjmaUSuiKqKMEBywkvl7nUHipaV3HpBUkj4CZ42r+5WXDU2va/AZ3yDnw== edward.rule@hotmail.com"
}
# Create DB Subnet Group
resource "aws_db_subnet_group" "dbgroup" {
  name       = "dbgroup"
  subnet_ids = [aws_subnet.dbsubnet2.id, aws_subnet.dbsubnet1.id]
  tags = {
    Name = "dbgroup"
  }
}
# Create RDS
resource "aws_db_instance" "rds" {
  backup_retention_period = 7 # in days
  db_subnet_group_name    = aws_db_subnet_group.dbgroup.name
  engine                  = "postgres"
  engine_version          = "11"
  identifier              = "rds1"
  instance_class          = "db.t3.micro"
  multi_az                = false
  db_name                 = "rds2"
  password                = "12qwaszx34QWASZX"
  port                    = 5432
  allocated_storage       = 20
  publicly_accessible     = false
  storage_encrypted       = true # you should always do this
  storage_type            = "gp2"
  username                = "RDS1"
  # security_group_id       = ["${aws_db_security_group.PostGresSG.id}"]

}
