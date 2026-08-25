#!/bin/bash
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl start docker
systemctl enable docker
docker pull ne2409/photo-guestbook

AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)


docker run -d -p 5000:5000 --name guestbook-app --restart always \
  -e S3_BUCKET="${s3_bucket}" \
  -e DB_HOST="${db_host}" \
  -e DB_NAME="${db_name}" \
  -e DB_USER="${db_user}" \
  -e AWS_REGION="${region}" \
  -e DB_PASSWORD="${db_password}" \
  -e AZ="$AZ" \
  -e CLOUDFRONT_DOMAIN="${cloudfront_domain}" \
  ne2409/photo-guestbook

