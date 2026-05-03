################################
# S3: 画像保管 (本番想定の置き場所)
# 本リポでは Post.image_url を URL 文字列で持つだけだが、本番では
# pre-signed URL で直接 S3 に PUT させる経路を想定する。
################################

resource "aws_s3_bucket" "images" {
  bucket = "instagram-architecture-lab-images-${var.environment}"
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
