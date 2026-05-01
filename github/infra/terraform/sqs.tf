################################
# SQS
# - 通知配信ワーカーへの非同期キュー (本実装は未対応、将来用)
# - DLQ で失敗を分離し、運用観点で再処理しやすくする
################################

resource "aws_sqs_queue" "notifications_dlq" {
  name                       = "github-transcode-dlq"
  message_retention_seconds  = 1209600 # 14 日
  visibility_timeout_seconds = 60
}

resource "aws_sqs_queue" "notifications" {
  name                       = "github-transcode"
  message_retention_seconds  = 345600 # 4 日
  visibility_timeout_seconds = 60
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 5
  })
}
