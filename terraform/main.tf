# ==== VPC ==== #
resource "aws_vpc" "photoguestbook_vpc" { 
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" { 
  vpc_id = aws_vpc.photoguestbook_vpc.id
}

resource "aws_subnet" "publuc_subnet_a" {
  vpc_id = aws_vpc.photoguestbook_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone  = "eu-west-1a"
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.photoguestbook_vpc.id
}

resource "aws_route" "r" {
  route_table_id = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "RTA-public" {
  subnet_id = aws_subnet.publuc_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

# ==== security ==== #
## temp rule, need to add the following rules:
# interner -> ALB, ALB->EC2
resource "aws_security_group" "http_ssh_sg" { 
  name        = "allow _http_allow_my_ssh"
  description = "Allow HTTP from everywhere and SSH from my IP only." 
  vpc_id =  aws_vpc.photoguestbook_vpc.id
  ingress {
    from_port = 5000
    to_port = 5000
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["5.29.23.21/32"]
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
  bucket = "noame-photoguestbook-project-randomname"
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = "noame-photoguestbook-project-randomname"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
