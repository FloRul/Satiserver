# Satisfactory Game Server on AWS with Terraform
Inspired from [this existing solution](https://github.com/feydan/satisfactory-server-aws).
This repository contains Terraform code for setting up a Satisfactory game server on AWS. The server is hosted on an EC2 instance with the necessary ports open for players to connect. It also includes a backup system for saving game progress to an S3 bucket and an (auto-shutdown)[] mechanism to stop the server after a period of inactivity.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed
- An AWS account with appropriate permissions
- Satisfactory game server files (obtained separately)

## Usage

1. Clone this repository:

```
git clone https://github.com/your-repo/satisfactory-server.git
cd satisfactory-server
```

2. Create a `terraform.tfvars` file and specify your variable values (e.g., `instance_type`, `instance_ami`, `players_ips`). Refer to `variables.tf` for the available variables.

3. Initialize Terraform:

```
terraform init
```

4. Review the execution plan:

```
terraform plan -var-file=terraform.tfvars
```

5. Apply the configuration:

```
terraform apply -var-file=terraform.tfvars
```

6. After the setup is complete, the public IP address of the server will be displayed in the output.

## Components

### EC2 Instance

The `aws_instance` resource defines the EC2 instance that will host the Satisfactory game server. It uses the specified AMI (Ubuntu 22.04 LTS in ca-central-1 by default), instance type, and security group. The instance user data script (`scripts/install.sh`) takes care of installing the necessary dependencies and setting up the game server.

### Security Group

The `aws_security_group` resource defines the security group rules for allowing incoming traffic on the required game ports (7777, 15000, 15077), as well as SSH access for administration purposes. The allowed IP addresses for incoming traffic are specified in the `players_ips` variable.

### S3 Bucket

The `aws_s3_bucket` resource creates an S3 bucket for storing game server backups. The bucket name is specified in the `backup_bucket` variable (default: `satiserver-backup`).

### Backup System

The user data script (`scripts/install.sh`) creates a backup script (`/home/steam/backup-saves.sh`) that runs every 5 minutes via a systemd timer. The script creates a tar archive of the server's save files and uploads it to the S3 bucket with a path based on the instance ID, timestamp, and the specified `backup_prefix`.

### Auto Shutdown

The user data script includes an auto-shutdown mechanism that shuts down the EC2 instance after a specified period of inactivity (default: 30 minutes). This is implemented using a shell script (`/home/ubuntu/auto-shutdown.sh`) and a systemd service (`auto-shutdown.service`).

The auto-shutdown script periodically checks for active connections on the game port (7777). If no connections are detected for the specified idle time (30 minutes by default), the script initiates a shutdown of the EC2 instance.

## Cleanup

To remove the resources created by Terraform, run:

```
terraform destroy -var-file=terraform.tfvars
```

Note that this will delete the EC2 instance, security group, and S3 bucket (including any backups stored in it).

## Disclaimers
This is a free and open source project and there are no guarantees that it will work or always continue working. If you use it, you are responsible for maintaining your setup and monitoring and paying for your AWS bill. It is a great project for learning a little AWS and Terraform.