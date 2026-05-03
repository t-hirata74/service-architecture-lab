################################
# S3
# - corpus: コーパスのソーステキスト永続化 (Phase 2 の Source.body の本番想定の置き場).
#   Phase 2 はローカル seeds から MySQL に投入していたが、本番想定では S3 に raw を置き
#   バッチで chunk + embedding を再構築する想定 (ADR 0002 embedding_version 再計算).
################################

resource "aws_s3_bucket" "corpus" {
  bucket        = "perplexity-corpus-${random_id.suffix.hex}"
  force_destroy = false
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "corpus" {
  bucket                  = aws_s3_bucket.corpus.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "corpus" {
  bucket = aws_s3_bucket.corpus.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "corpus" {
  bucket = aws_s3_bucket.corpus.id

  versioning_configuration {
    status = "Enabled"
  }
}
