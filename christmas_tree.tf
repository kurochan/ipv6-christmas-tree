resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = local.project_name
  }
}

output "ipv6_vpc_block" {
  value = aws_vpc.main.ipv6_cidr_block
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "${aws_vpc.main.region}a"

  cidr_block      = "10.0.0.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0) # 56 + 8 = 64

  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = {
    Name = "${local.project_name}-a"
  }
}

output "ipv6_subnet_block" {
  value = aws_subnet.main.ipv6_cidr_block
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.project_name
  }
}

resource "aws_default_route_table" "route" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = local.project_name
  }
}

resource "aws_security_group" "ec2" {
  name   = "${local.project_name}-ec2"
  vpc_id = aws_vpc.main.id

  # ICMP Echo Request
  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMPv6 Echo Request
  ingress {
    from_port        = 128
    to_port          = 0
    protocol         = "icmpv6"
    ipv6_cidr_blocks = ["::/0"]
  }

  # IPv6 UDP
  ingress {
    from_port        = 33000
    to_port          = 35000
    protocol         = "udp"
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.project_name}-ec2"
  }
}

resource "aws_iam_role" "ec2" {
  name = "${local.project_name}-ec2"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "${local.project_name}-ec2"
  }
}

resource "aws_iam_role_policy" "ec2_s3" {
  role   = aws_iam_role.ec2.id
  name   = "policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "policy0",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "${aws_s3_bucket.script.arn}/*"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "ec2_ssm" {
  name       = "${local.project_name}-ec2-ssm"
  roles      = [aws_iam_role.ec2.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.project_name}-ec2"
  role = aws_iam_role.ec2.name
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_network_interface" "ec2" {
  subnet_id       = aws_subnet.main.id
  security_groups = [aws_security_group.ec2.id]
  ipv6_prefixes   = [cidrsubnet(aws_subnet.main.ipv6_cidr_block, 16, 202)] # 64 + 16 = 80

  tags = {
    Name = "${local.project_name}-eni"
  }
}

output "ipv6_ec2_prefix" {
  value = tolist(aws_network_interface.ec2.ipv6_prefixes)[0]
}

output "ipv6_ec2" {
  value = cidrhost(tolist(aws_network_interface.ec2.ipv6_prefixes)[0], 0)
}

resource "aws_instance" "ec2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  primary_network_interface {
    network_interface_id = aws_network_interface.ec2.id
  }

  iam_instance_profile = aws_iam_instance_profile.ec2.id

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    ipv6_prefix = cidrhost(tolist(aws_network_interface.ec2.ipv6_prefixes)[0], 0),
    s3_bucket   = aws_s3_bucket.script.bucket
  })

  tags = {
    Name = "${local.project_name}-01"
  }

  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}

resource "random_string" "script_suffix" {
  length  = 16
  special = false
  upper   = false
}

resource "aws_s3_bucket" "script" {
  bucket = "${local.project_name}-script-${random_string.script_suffix.id}"
}

output "script_bucket_name" {
  value = aws_s3_bucket.script.bucket
}

resource "aws_s3_bucket_public_access_block" "script" {
  bucket = aws_s3_bucket.script.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  script_content = templatefile("${path.module}/multihop.sh.tftpl", {
    ipv6_prefix = cidrhost(tolist(aws_network_interface.ec2.ipv6_prefixes)[0], 0),
  })
}

resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.script.bucket
  key    = "multihop.sh"

  content = local.script_content
  etag    = md5(local.script_content)
}
