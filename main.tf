terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "eu-north-1"
}

#
# Primary bucket (your existing)
# 
resource "aws_s3_bucket" "existing_bucket" {
  bucket = "devsecops-demo-bucket-7810e7b1" # you can use your buckets which you created in the last project 

  tags = {
    Name = "devsecops-demo"
    Env  = "demo"
  }
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.existing_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.existing_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.existing_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


# KMS for default encryption

resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7

  # Fix: enable key rotation
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.existing_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
    }
  }
}


# Enforce TLS-only

resource "aws_s3_bucket_policy" "https_only" {
  bucket = aws_s3_bucket.existing_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          "${aws_s3_bucket.existing_bucket.arn}",
          "${aws_s3_bucket.existing_bucket.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}


# Access logging (separate log bucket)

# NOTE:
#  Server Access Logging requires ACLs on the *target* bucket.)
# Keep ACLs disabled (BucketOwnerEnforced) on your main bucket,)
#   but allow ACLs on the log bucket with the canned ACL below :)

resource "aws_s3_bucket" "log_bucket" {
  bucket = "devsecops-demo-bucket-7810e7b1-logs"

  tags = {
    Name = "devsecops-demo-logs"
    Env  = "demo"
  }
}

# Allow ACLs on the log bucket (don't use BucketOwnerEnforced here)
resource "aws_s3_bucket_ownership_controls" "log_bucket_ownership" {
  bucket = aws_s3_bucket.log_bucket.id
  rule {
    # This setting keeps you as owner but still permits ACLs,)
    # which S3's log delivery requires:)
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "log_bucket_block" {
  bucket = aws_s3_bucket.log_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "log_bucket_versioning" {
  bucket = aws_s3_bucket.log_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE for the log bucket – use SSE-S3 to avoid extra KMS policy work
resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_sse" {
  bucket = aws_s3_bucket.log_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Critical: grant S3 Log Delivery group rights on the *target* bucket ;)
# The canned ACL "log-delivery-write" gives WRITE and READ_ACP to the log-delivery group :)
resource "aws_s3_bucket_acl" "log_bucket_acl" {
  bucket = aws_s3_bucket.log_bucket.id
  acl    = "log-delivery-write"

  depends_on = [
    aws_s3_bucket_ownership_controls.log_bucket_ownership
  ]
}

# Turn on access logging on your primary bucket, pointing to the log bucket :) ;)
resource "aws_s3_bucket_logging" "main_logging" {
  bucket        = aws_s3_bucket.existing_bucket.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "s3-access-logs/"
}
