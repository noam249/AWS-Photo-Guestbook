variable "my_ip" {
  description = "Personal IP for SSH access"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet" {
  type = map(any)
  default = {
    a = {
      cidr_block        = "10.0.1.0/24",
      availability_zone = "eu-west-1a"
    },
    b = {
      cidr_block        = "10.0.2.0/24",
      availability_zone = "eu-west-1b"
    }
  }
}

variable "private_subnet" {
  type = map(any)
  default = {
    a = {
      cidr_block        = "10.0.11.0/24",
      availability_zone = "eu-west-1a"
    },
    b = {
      cidr_block        = "10.0.22.0/24",
      availability_zone = "eu-west-1b"
    }
  }
}


variable "bucket_name" {
  description = "S3 bucket name for image storage"
  type        = string
}

variable "db_name" {
  description = "RDS DB name"
  type        = string
  default     = "guestbook"
}

variable "db_user" {
  type    = string
  default = "guestbook_admin"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "ssh_key_file" {
  type = string
}