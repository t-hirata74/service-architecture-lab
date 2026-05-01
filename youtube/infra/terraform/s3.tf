################################
# S3
# - attachments: 添付ファイル (画像等) の永続化
# - exports: GDPR 等のデータエクスポート結果
# 両者ともプライベート、署名付き URL 経由でアクセス
################################

resource "aws_s3_bucket" "attachments" {
  bucket        = "youtube-videos-${random_id.suffix.hex}"
  force_destroy = false
}

resource "aws_s3_bucket" "exports" {
  bucket        = "youtube-thumbnails-${random_id.suffix.hex}"
  force_destroy = false
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "attachments" {
  bucket                  = aws_s3_bucket.attachments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id

  rule {
    id     = "expire-old-exports"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}
