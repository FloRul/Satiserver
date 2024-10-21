
# EC2 Instance
resource "aws_instance" "game_server" {
  ami       = "ami-049332278e728bdb7" # Ubuntu 22.04 LTS in ca-central-1
  subnet_id = aws_subnet.public.id

  instance_type = "m5a.large"

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
  }

  vpc_security_group_ids = [aws_security_group.game_server_sg.id]

  tags = {
    Name = "game-server"
  }

  user_data            = templatefile("${path.module}/scripts/install.sh", { S3_SAVE_BUCKET = aws_s3_bucket.server_backup.bucket })
  iam_instance_profile = aws_iam_instance_profile.game_server.name
}

resource "aws_ec2_instance_state" "game_server_state" {
  instance_id = aws_instance.game_server.id
  state       = "stopped" # stopped, running
}

# Elastic IP
resource "aws_eip" "game_server" {
  instance = aws_instance.game_server.id
}

resource "aws_iam_role" "game_server" {
  name = "game-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access"
  role = aws_iam_role.game_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.server_backup.arn}",
          "${aws_s3_bucket.server_backup.arn}/*"
        ]
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "game_server" {
  name = "game-server-profile"
  role = aws_iam_role.game_server.name
}
