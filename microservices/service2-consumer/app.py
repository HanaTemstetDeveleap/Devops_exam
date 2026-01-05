"""
Microservice 2 - SQS Consumer
Polls SQS queue, retrieves messages, and uploads them to S3
"""

import os
import json
import time
import boto3
from datetime import datetime
from botocore.exceptions import ClientError

# AWS clients
sqs_client = boto3.client('sqs', region_name=os.getenv('AWS_REGION', 'us-east-1'))
s3_client = boto3.client('s3', region_name=os.getenv('AWS_REGION', 'us-east-1'))

# Configuration from environment variables
SQS_QUEUE_URL = os.getenv('SQS_QUEUE_URL')
S3_BUCKET_NAME = os.getenv('S3_BUCKET_NAME')
POLL_INTERVAL = int(os.getenv('POLL_INTERVAL', '10'))  # Seconds between polls
MAX_MESSAGES = int(os.getenv('MAX_MESSAGES', '10'))  # Max messages per poll


def upload_to_s3(message_data, message_id):
    """
    Upload message to S3 bucket
    File naming: messages/YYYY/MM/DD/<message_id>.json
    """
    try:
        # Create hierarchical path based on current date
        now = datetime.utcnow()
        s3_key = f"messages/{now.year}/{now.month:02d}/{now.day:02d}/{message_id}.json"

        # Upload to S3
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(message_data, indent=2),
            ContentType='application/json'
        )

        print(f"✓ Uploaded message {message_id} to s3://{S3_BUCKET_NAME}/{s3_key}")
        return True

    except ClientError as e:
        print(f"✗ Failed to upload message {message_id} to S3: {e}")
        return False


def process_message(message):
    """
    Process a single SQS message
    Returns: True if successful, False otherwise
    """
    try:
        # Extract message details
        receipt_handle = message['ReceiptHandle']
        message_id = message['MessageId']
        body = message['Body']

        # Parse message body (should be JSON from service1)
        try:
            message_data = json.loads(body)
        except json.JSONDecodeError as e:
            print(f"✗ Invalid JSON in message {message_id}: {e}")
            return False

        # Upload to S3
        if not upload_to_s3(message_data, message_id):
            return False

        # Delete message from queue after successful processing
        sqs_client.delete_message(
            QueueUrl=SQS_QUEUE_URL,
            ReceiptHandle=receipt_handle
        )

        print(f"✓ Deleted message {message_id} from queue")
        return True

    except Exception as e:
        print(f"✗ Error processing message: {e}")
        return False


def poll_sqs():
    """
    Poll SQS queue for messages using long polling
    """
    try:
        # Receive messages from SQS (long polling)
        response = sqs_client.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=MAX_MESSAGES,
            WaitTimeSeconds=20,  # Long polling - wait up to 20 seconds
            MessageAttributeNames=['All']
        )

        messages = response.get('Messages', [])

        if not messages:
            print("○ No messages in queue")
            return 0

        print(f"● Received {len(messages)} message(s) from queue")

        # Process each message
        successful = 0
        for message in messages:
            if process_message(message):
                successful += 1

        print(f"✓ Successfully processed {successful}/{len(messages)} messages")
        return successful

    except ClientError as e:
        print(f"✗ Error polling SQS: {e}")
        return 0


def main():
    """Main loop - continuously poll SQS queue"""
    print("=" * 60)
    print("Microservice 2 - SQS Consumer")
    print("=" * 60)
    print(f"SQS Queue: {SQS_QUEUE_URL}")
    print(f"S3 Bucket: {S3_BUCKET_NAME}")
    print(f"Poll Interval: {POLL_INTERVAL} seconds")
    print("=" * 60)

    # Validate required environment variables
    if not SQS_QUEUE_URL:
        raise ValueError("SQS_QUEUE_URL environment variable is required")
    if not S3_BUCKET_NAME:
        raise ValueError("S3_BUCKET_NAME environment variable is required")

    # Main polling loop
    print("\n🚀 Starting message consumer...\n")

    while True:
        try:
            poll_sqs()
            time.sleep(POLL_INTERVAL)

        except KeyboardInterrupt:
            print("\n\n⏹ Shutting down gracefully...")
            break

        except Exception as e:
            print(f"✗ Unexpected error: {e}")
            time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
