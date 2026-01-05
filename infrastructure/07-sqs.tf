# =============================================================================
# SQS Queue for passing messages between microservices
# =============================================================================

resource "aws_sqs_queue" "messages" {
  name                       = "${var.project_name}-messages-queue"
  visibility_timeout_seconds = 30  # Time message is invisible after being received
  message_retention_seconds  = 345600 # Keep messages for 4 days (max for free tier)
  max_message_size          = 262144 # 256 KB - maximum allowed
  delay_seconds             = 0    # No delay in message delivery
  receive_wait_time_seconds = 20   # Long polling - reduces costs and empty responses

  tags = {
    Name        = "${var.project_name}-messages-queue"
    Description = "Queue for messages from service1 to service2"
  }
}

# Dead Letter Queue - stores messages that failed processing
resource "aws_sqs_queue" "messages_dlq" {
  name                       = "${var.project_name}-messages-dlq"
  message_retention_seconds  = 1209600 # Keep failed messages for 14 days

  tags = {
    Name        = "${var.project_name}-messages-dlq"
    Description = "Dead letter queue for failed messages"
  }
}

# Redrive policy - send failed messages to DLQ after 3 attempts
resource "aws_sqs_queue_redrive_policy" "messages" {
  queue_url = aws_sqs_queue.messages.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.messages_dlq.arn
    maxReceiveCount     = 3 # Retry 3 times before moving to DLQ
  })
}
