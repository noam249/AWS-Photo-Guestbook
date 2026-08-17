# AWS Photo Guestbook

A highly available three-tier web application demonstrating AWS best practices for fault tolerance and high availability.

## Architecture

- **Frontend**: Flask web application running on EC2 instances in an Auto Scaling Group
- **Load Balancing**: Application Load Balancer distributing traffic across two Availability Zones
- **Database**: Amazon RDS PostgreSQL with Multi-AZ deployment for redundancy
- **Storage**: Amazon S3 for durable photo storage
- **Region**: eu-west-1 with cross-AZ redundancy

## Features

- Upload photos with accompanying messages
- View all guestbook entries in a responsive grid
- Photos stored durably in S3
- Metadata and S3 references stored in RDS

## Environment Variables Required

- `S3_BUCKET`: Name of the S3 bucket for photo storage
- `AWS_REGION`: AWS region (default: eu-west-1)
- `DB_HOST`: RDS database endpoint
- `DB_NAME`: Database name (default: guestbook)
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password
- `SECRET_KEY`: Flask secret key for sessions

## Local Development

```bash
pip install -r requirements.txt
export S3_BUCKET=your-bucket
export DB_HOST=localhost
export DB_USER=postgres
export DB_PASSWORD=yourpassword
python app.py
```
