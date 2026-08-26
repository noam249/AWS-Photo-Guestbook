# AWS Multi-AZ Photo Guestbook

Highly available web application demonstrating a classic three-tier architecture on AWS, fully provisioned with Terraform. The project showcases automated scaling, cross-AZ redundancy, secure cloud networking, and infrastructure managed entirely as code — no manual console clicks.

This is a rebuild of an earlier, manually-provisioned version of the same architecture. Everything below was recreated from scratch in Terraform, with a few deliberate improvements along the way (see *Design Decisions* below).

## Architecture

The infrastructure is designed for Fault Tolerance and High Availability (HA), spanning two Availability Zones in the `eu-west-1` region.

**Traffic flow:** Internet → Internet Gateway → Application Load Balancer (public subnets) → Auto Scaling Group targets (private subnets) → RDS / S3.

## Technical Stack

- **Compute:** Amazon EC2 (`t3.micro`) managed by an Auto Scaling Group (ASG), min 2 / max 4 instances
- **Load Balancing:** Application Load Balancer (ALB) distributing HTTP traffic across both AZs
- **Database:** Amazon RDS for PostgreSQL
- **Storage:** Amazon S3 for durable object storage, served through **CloudFront** with **Origin Access Control** — the bucket itself has no public access at all
- **Security:** IAM Roles scoped to least privilege, Security Group chaining, Private Subnet isolation, SSM Session Manager for shell access (no SSH keys exposed, no bastion host)
- **Infrastructure as Code:** 100% Terraform — VPC, networking, compute, database, and IAM are all defined in code and reproducible with `terraform apply` / `terraform destroy`
- **Containerization:** Flask application packaged as a multi-stage Docker image, run via a `user_data` bootstrap script on each ASG instance

## Infrastructure Details

### Networking (VPC Configuration)

| Resource | CIDR | Details |
|---|---|---|
| VPC | 10.0.0.0/16 | |
| Public Subnet A | 10.0.1.0/24 | NAT Gateway A · `eu-west-1a` |
| Public Subnet B | 10.0.2.0/24 | NAT Gateway B · `eu-west-1b` |
| Private Subnet A | 10.0.11.0/24 | EC2 (ASG) + RDS · `eu-west-1a` |
| Private Subnet B | 10.0.22.0/24 | EC2 (ASG) + RDS · `eu-west-1b` |

All subnet pairs, EIPs, NAT Gateways, and route tables are provisioned with `for_each` over a shared map, keyed by AZ (`a` / `b`) — not `count` — so that removing or modifying one AZ's resources doesn't force an unrelated recreation of the other.

### Security Groups

- **ALB-SG:** Allows inbound HTTP (80) from `0.0.0.0/0`
- **EC2-SG:** Allows inbound traffic on the app port (5000), restricted to `ALB-SG` as the source only
- **DB-SG:** Allows inbound PostgreSQL (5432), restricted to `EC2-SG` as the source only

### IAM

A single EC2 role (`ec2_to_s3`) with a trust policy scoped to `ec2.amazonaws.com`, and two things attached to it:
- An inline permissions policy granting `s3:ListBucket` on the bucket itself and `s3:PutObject` / `s3:GetObject` on objects within it — nothing broader
- The AWS-managed `AmazonSSMManagedInstanceCore` policy, enabling remote shell access via SSM Session Manager instead of SSH — instances in the private subnets have no public IP and no open port 22

## Proof of Concept: Multi-AZ Traffic Distribution

The application exposes the Availability Zone of the instance serving each request (read from the EC2 instance metadata service at boot, injected as an environment variable). Refreshing the page repeatedly shows the ALB alternating traffic between instances in `eu-west-1a` and `eu-west-1b`.

The load balancer's health check hits a dedicated `/health` endpoint that does **not** touch the database — it only confirms the process itself is alive and listening. This is intentional: coupling the health check to the database would mean a single RDS blip (failover, brief unavailability) could cause the ALB to mark every instance unhealthy at once, since they all depend on the same database.

<img width="1130" height="796" alt="guestbook-1a" src="https://github.com/user-attachments/assets/18497ff9-4dcb-4f95-a97b-fa68d41c8a84" />  <img width="1125" height="801" alt="guestbook-1b" src="https://github.com/user-attachments/assets/0ad68686-67bb-48c8-b9ad-249d5b3484f7" /> 




## Design Decisions Worth Noting

A few choices made along the way, and why:

- **`for_each` over `count`** for all AZ-paired resources (subnets, EIPs, NAT Gateways, route tables) — identity by key (`"a"` / `"b"`) rather than list index, so resources don't get recreated unnecessarily when the set changes.
- **Private S3 bucket + CloudFront with Origin Access Control**, instead of a public-read bucket policy. Only CloudFront can read from the bucket; the bucket itself blocks all public access.
- **SSM Session Manager instead of a bastion host.** No extra EC2 instance to maintain, no SSH keys to rotate, and no port 22 open anywhere in the VPC.
- **RDS provisioned single-AZ first, Multi-AZ as a later step** — Multi-AZ failover setup takes 10–20 minutes to create or tear down, which is a lot of friction while still debugging basic Terraform syntax. Validating the full pipeline on a cheaper, faster-to-iterate config first, then upgrading, saved a lot of wasted waiting time during development.
- **Health check leaves the database out on purposee** — see *Proof of Concept* above.
- **`terraform destroy` after every work session** — this stack costs real money if left running (2× NAT Gateway, RDS, ALB, 2× EC2), so the infrastructure is treated as fully ephemeral during development rather than left running between sessions.

## Notable Issues Hit During the Build

- **RDS `MasterUserPassword` rejected on `apply`** — RDS disallows `/`, `@`, `"`, and spaces in the password. The error only surfaces at `apply` time, not `plan` time.
- **IAM trust policy vs. permissions policy confusion** — early on, the S3 permissions JSON was mistakenly placed in `assume_role_policy` (which only defines *who* can assume the role) instead of a separate permissions policy (which defines *what* the role can do). Also hit a circular dependency trying to have the role and its policy reference each other.
- **`s3:ListBucket` vs. `s3:GetObject`/`s3:PutObject` require different ARN shapes** — the former acts on the bucket itself (`arn:aws:s3:::bucket-name`), the latter on objects inside it (`arn:aws:s3:::bucket-name/*`).
- **SSM connection failing on already-running instances** — the IAM policy attachment doesn't retroactively help an instance whose agent already failed to register at boot. Fixed by forcing the ASG to cycle the instance rather than waiting.

## Future Roadmap

- **CI/CD:** GitHub Actions pipeline — build and test the Docker image, push to a registry, then trigger `terraform apply` to roll out a new Launch Template version through the ASG
- **Orchestration:** Move the containerized app from EC2/ASG onto Kubernetes (starting locally with `kind`/`minikube`)
- **Remote state:** Migrate Terraform state to an S3 backend with DynamoDB locking
- **Modules:** Refactor the repeated per-AZ networking pattern (subnet + NAT + route table) into a reusable Terraform module
