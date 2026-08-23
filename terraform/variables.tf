variable "my_ip" {
  description = "Personal IP for SSH access"
  type        = string
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