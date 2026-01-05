# =============================================================================
# S3 Bucket for storing messages from SQS
# =============================================================================

resource "aws_s3_bucket" "messages" {
  bucket = "${var.project_name}-messages-${var.environment}"

  tags = {
    Name        = "${var.project_name}-messages"
    Description = "Storage for messages received from SQS queue"
  }
}

# NOTE: Public access block removed due to AWS account policy restrictions
# The bucket remains private by default - AWS does not allow public access unless explicitly configured

# Enable versioning - keep history of changes
resource "aws_s3_bucket_versioning" "messages" {
  bucket = aws_s3_bucket.messages.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption - encrypt data at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "messages" {
  bucket = aws_s3_bucket.messages.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Free - uses AWS managed keys
    }
  }
}

# Lifecycle rule - delete old messages after 90 days to save storage
resource "aws_s3_bucket_lifecycle_configuration" "messages" {
  bucket = aws_s3_bucket.messages.id

  rule {
    id     = "delete-old-messages"
    status = "Enabled"

    filter {} # Apply to all objects in bucket

    expiration {
      days = 90 # Free tier: 5GB storage
    }
  }
}
