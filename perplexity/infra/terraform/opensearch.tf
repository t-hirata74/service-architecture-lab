################################
# OpenSearch (ADR 0002 本番想定)
# ローカル: MySQL FULLTEXT (ngram) + numpy in-memory cosine の hybrid retrieval.
# 本番想定: OpenSearch に切り替え BM25 + knn_vector を 1 query で実行する.
# Phase 5 では設計図として AWS リソースのみ確保. ai-worker は OPENSEARCH_ENDPOINT を
# 受け取れるが、ローカルでは未使用 (numpy 経路) のまま.
################################

resource "aws_opensearch_domain" "main" {
  domain_name    = "perplexity"
  engine_version = "OpenSearch_2.13"

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    zone_awareness_enabled   = true
    dedicated_master_enabled = false

    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  vpc_options {
    subnet_ids         = aws_subnet.private_data[*].id
    security_group_ids = [aws_security_group.opensearch.id]
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 50
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true

    master_user_options {
      master_user_name     = "perplexity_admin"
      master_user_password = aws_secretsmanager_secret_version.opensearch_master_password.secret_string
    }
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  tags = { Name = "perplexity-opensearch" }
}
