# ==== VPC ==== #
resource "aws_vpc" "photoguestbook_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "photoguestbook-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.photoguestbook_vpc.id
  tags = {
    Name = "photoguestbook-igw"
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.photoguestbook_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "photoguestbook-public-subnet-a"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.photoguestbook_vpc.id
  tags = {
    Name = "photoguestbook-public-rt"
  }
}

resource "aws_route" "r" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "rta-public" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

# ==== security ==== #
## temp rule, need to add the following rules:
# interner -> ALB, ALB->EC2
resource "aws_security_group" "http_ssh_sg" {
  name        = "allow _http_allow_my_ssh"
  description = "Allow HTTP from everywhere and SSH from my IP only."
  vpc_id      = aws_vpc.photoguestbook_vpc.id
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==== S3 ==== #
resource "aws_s3_bucket" "image_storage" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket                  = aws_s3_bucket.image_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==== IAM ==== #

resource "aws_iam_role" "ec2_to_s3" {
  name = "ec2_to_s3"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

}

resource "aws_iam_role_policy" "allow_s3_access" {
  name = "allow_s3_access"
  role = aws_iam_role.ec2_to_s3.name
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "Statement1",
          "Effect" : "Allow",
          "Action" : [
            "s3:ListBucket"
          ],
          "Resource" : "arn:aws:s3:::${var.bucket_name}"
        },
        {
          "Sid" : "Statement2",
          "Effect" : "Allow",
          "Action" : [
            "s3:PutObject",
            "s3:GetObject"
          ],
          "Resource" : "arn:aws:s3:::${var.bucket_name}/*"
        }
      ]
    }
  )
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_to_s3.name
}

# === EC2 === #

resource "aws_instance" "server" {
  instance_type               = "t3.micro"
  ami                         = data.aws_ami.ubuntu.id
  subnet_id                   = aws_subnet.public_subnet_a.id
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.http_ssh_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh_key.key_name
  tags = {
    Name = "guestbook-server"
  }
}

data "aws_ami" "ubuntu" {
  region      = var.region
  owners      = ["099720109477"] # Canonical
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "guestbook-key"
  public_key = file(var.ssh_key_file)
}
