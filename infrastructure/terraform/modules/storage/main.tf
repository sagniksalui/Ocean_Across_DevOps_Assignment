locals {
  portal_prefixes = toset(["companies", "bureaus", "employees"])
}

# A generated suffix avoids globally unique bucket-name collisions without
# embedding an AWS account ID or other deployment-specific identifier.
resource "aws_s3_bucket" "documents" {
  bucket_prefix = "${var.environment}-ocean-across-payroll-documents-"
  force_destroy = false

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-payroll-documents"
    Purpose = "PayrollDocumentsAndReports"
  })
}

# Bucket-owner-enforced ownership disables legacy ACL-based access paths.
resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public access is blocked independently of IAM and bucket policy statements.
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning provides recovery from accidental overwrite or deletion.
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Explicit SSE-S3 ensures every object is encrypted at rest without requiring a
# customer-managed KMS key for this assignment.
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Keep lifecycle behavior simple: expire only noncurrent versions and abandoned
# multipart uploads. Current payroll records are never expired automatically.
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "manage-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.documents]
}
