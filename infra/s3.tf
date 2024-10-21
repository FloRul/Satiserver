resource "aws_s3_bucket" "server_backup" {
  bucket = var.backup_bucket
}

resource "aws_s3_bucket_ownership_controls" "server_backup" {
  bucket = aws_s3_bucket.server_backup.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

