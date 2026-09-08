# ==== VPC ==== #
resource "aws_vpc" "photoguestbook_vpc" {
  cidr_block = var.vpc_cidr
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

resource "aws_eip" "eip_ngw" {
  for_each = aws_subnet.public_subnet
  domain   = "vpc"
}

resource "aws_nat_gateway" "ngw" {
  for_each      = aws_subnet.public_subnet
  subnet_id     = each.value.id
  allocation_id = aws_eip.eip_ngw[each.key].id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "nat_gateway-${each.key}"
  }
}

resource "aws_subnet" "public_subnet" {
  for_each          = var.public_subnet
  vpc_id            = aws_vpc.photoguestbook_vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
  tags = {
    Name = "photoguestbook-public-subnet-${each.key}"
  }
}

resource "aws_subnet" "private_subnet" {
  for_each          = var.private_subnet
  vpc_id            = aws_vpc.photoguestbook_vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
  tags = {
    Name = "photoguestbook-private-subnet-${each.key}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.photoguestbook_vpc.id
  tags = {
    Name = "photoguestbook-public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  for_each = aws_subnet.private_subnet
  vpc_id   = aws_vpc.photoguestbook_vpc.id
  tags = {
    Name = "photoguestbook-private-rt-${each.key}"
  }
}

resource "aws_route" "r_public" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route" "r_private" {
  for_each               = aws_nat_gateway.ngw
  route_table_id         = aws_route_table.private_rt[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = each.value.id
}

resource "aws_route_table_association" "rta-public" {
  for_each       = aws_subnet.public_subnet
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "rta-private" {
  for_each       = aws_subnet.private_subnet
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt[each.key].id
}

# ==== security ==== #
## temp rule, need to add the following rules:
# interner -> ALB, ALB->EC2
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP from everywhere to ALB"
  vpc_id      = aws_vpc.photoguestbook_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow HTTP from ALB to EC2"
  vpc_id      = aws_vpc.photoguestbook_vpc.id
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow access from EC2 to DB"
  vpc_id      = aws_vpc.photoguestbook_vpc.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.ec2_to_s3.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ==== RDS ==== #
resource "aws_db_subnet_group" "guestbook_db_subnets" {
  name       = "guestbook-db-subnets"
  subnet_ids = [for subnet in aws_subnet.private_subnet : subnet.id]

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "guestbook_db" {
  allocated_storage      = 10
  db_name                = var.db_name
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  username               = var.db_user
  password               = var.db_password
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.guestbook_db_subnets.name
}

# ==== S3 ==== #
resource "aws_s3_bucket" "image_storage" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_policy" "cloudfront_oac_policy" {
  bucket = aws_s3_bucket.image_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.image_storage.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "guestbook-oac"
  description                       = "OAC for Guestbook Photos"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = true

  origin {
    domain_name              = aws_s3_bucket.image_storage.bucket_regional_domain_name
    origin_id                = "S3-GuestbookPhotos"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-GuestbookPhotos"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
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

resource "aws_launch_template" "guestbook_lt" {
  name          = "guestbook_template"
  instance_type = "t3.micro"
  image_id      = data.aws_ami.ubuntu.id
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = aws_key_pair.ssh_key.key_name
  user_data = base64encode(templatefile("userdata.sh", {
    s3_bucket         = var.bucket_name
    db_host           = aws_db_instance.guestbook_db.address
    db_name           = var.db_name
    db_user           = var.db_user
    db_password       = var.db_password
    region            = var.region
    cloudfront_domain = aws_cloudfront_distribution.cdn.domain_name
  }))
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

# ==== ALB === #

resource "aws_lb" "alb" {
  name               = "photoguestbook-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]
}

resource "aws_lb_target_group" "alb_tg" {
  name     = "guestbook-forward-http-traffic"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.photoguestbook_vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }

  health_check {
    healthy_threshold = 2
    interval          = 30
    path              = "/health"
    port              = 5000
    protocol          = "HTTP"
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

# ==== ASG ==== #

resource "aws_autoscaling_group" "asg" {
  name                      = "guestbook-asg"
  max_size                  = 4
  min_size                  = 2
  desired_capacity          = 2
  vpc_zone_identifier       = [for subnet in aws_subnet.private_subnet : subnet.id]
  target_group_arns         = [aws_lb_target_group.alb_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  launch_template {
    id      = aws_launch_template.guestbook_lt.id
    version = "$Latest"
  }
}


# === OUTPUT === #

output "alb_dns_name" {
  description = "URL to access the Guestbook application"
  value       = aws_lb.alb.dns_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint for manual DB access"
  value       = aws_db_instance.guestbook_db.address
}

output "bucket_name" {
  description = "S3 bucket name for image storage"
  value       = aws_s3_bucket.image_storage.id
}