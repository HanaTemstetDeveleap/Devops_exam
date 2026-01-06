"""
Unit and Integration Tests for Service 2 - SQS Consumer
Tests message processing, S3 upload, SQS polling
"""

import pytest
import json
import os
from datetime import datetime
from unittest.mock import patch, MagicMock
from moto import mock_aws
import boto3

# Import functions to test
from app import process_message, upload_to_s3, poll_sqs


# Test Fixtures
@pytest.fixture
def sample_message_data():
    """Sample message data from Service 1"""
    return {
        "email_subject": "Test Subject",
        "email_sender": "sender@example.com",
        "email_timestream": "2024-01-01T12:00:00Z",
        "email_content": "Test email content"
    }


@pytest.fixture
def sqs_message(sample_message_data):
    """Mock SQS message structure"""
    return {
        "MessageId": "test-message-id-12345",
        "ReceiptHandle": "test-receipt-handle",
        "Body": json.dumps(sample_message_data)
    }


# Unit Tests - S3 Upload
@mock_aws
class TestS3Upload:
    """Test S3 upload functionality"""

    def test_upload_to_s3_success(self, sample_message_data):
        """Test successful upload to S3"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Patch the app's s3_client
        with patch('app.s3_client', s3):
            with patch('app.S3_BUCKET_NAME', bucket_name):
                message_id = 'test-message-123'
                result = upload_to_s3(sample_message_data, message_id)
                assert result is True

                # Verify file in S3
                now = datetime.utcnow()
                expected_key = f"messages/{now.year}/{now.month:02d}/{now.day:02d}/{message_id}.json"

                obj = s3.get_object(Bucket=bucket_name, Key=expected_key)
                stored_data = json.loads(obj['Body'].read())
                assert stored_data == sample_message_data

    def test_upload_to_s3_invalid_bucket(self, sample_message_data):
        """Test upload fails with non-existent bucket"""
        # Setup mock S3 without creating bucket
        s3 = boto3.client('s3', region_name='us-east-1')

        # Patch the app's s3_client
        with patch('app.s3_client', s3):
            with patch('app.S3_BUCKET_NAME', 'non-existent-bucket'):
                message_id = 'test-message-123'
                result = upload_to_s3(sample_message_data, message_id)
                assert result is False

    def test_upload_creates_hierarchical_path(self, sample_message_data):
        """Test that upload creates correct date-based path"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Patch the app's s3_client
        with patch('app.s3_client', s3):
            with patch('app.S3_BUCKET_NAME', bucket_name):
                message_id = 'test-message-456'
                upload_to_s3(sample_message_data, message_id)

                # Verify hierarchical structure
                now = datetime.utcnow()
                expected_key = f"messages/{now.year}/{now.month:02d}/{now.day:02d}/{message_id}.json"

                # Check object exists
                try:
                    s3.head_object(Bucket=bucket_name, Key=expected_key)
                    assert True
                except:
                    assert False, f"Expected key {expected_key} not found"


# Unit Tests - Message Processing
@mock_aws
class TestMessageProcessing:
    """Test SQS message processing"""

    def test_process_message_success(self, sqs_message):
        """Test successful message processing"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Send message to queue to get proper receipt handle
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=sqs_message['Body']
        )

        # Receive message
        response = sqs.receive_message(QueueUrl=queue_url)
        message = response['Messages'][0]

        # Patch clients
        with patch('app.s3_client', s3):
            with patch('app.sqs_client', sqs):
                with patch('app.S3_BUCKET_NAME', bucket_name):
                    with patch('app.SQS_QUEUE_URL', queue_url):
                        result = process_message(message)
                        assert result is True

                        # Verify message was deleted from queue
                        response = sqs.receive_message(QueueUrl=queue_url)
                        assert 'Messages' not in response

    def test_process_message_invalid_json(self):
        """Test processing fails with invalid JSON"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Create message with invalid JSON
        invalid_message = {
            "MessageId": "test-123",
            "ReceiptHandle": "test-receipt",
            "Body": "not valid json"
        }

        # Patch clients
        with patch('app.s3_client', s3):
            with patch('app.sqs_client', sqs):
                with patch('app.S3_BUCKET_NAME', bucket_name):
                    with patch('app.SQS_QUEUE_URL', queue_url):
                        result = process_message(invalid_message)
                        assert result is False


# Integration Tests - SQS Polling
@mock_aws
class TestSQSPolling:
    """Test SQS polling functionality"""

    def test_poll_sqs_with_messages(self, sample_message_data):
        """Test polling when messages exist in queue"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Add messages to queue
        for i in range(3):
            sqs.send_message(
                QueueUrl=queue_url,
                MessageBody=json.dumps(sample_message_data)
            )

        # Patch clients
        with patch('app.s3_client', s3):
            with patch('app.sqs_client', sqs):
                with patch('app.S3_BUCKET_NAME', bucket_name):
                    with patch('app.SQS_QUEUE_URL', queue_url):
                        processed_count = poll_sqs()
                        assert processed_count == 3

                        # Verify all messages were processed and deleted
                        response = sqs.receive_message(QueueUrl=queue_url)
                        assert 'Messages' not in response

    def test_poll_sqs_empty_queue(self):
        """Test polling when queue is empty"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Patch clients
        with patch('app.s3_client', s3):
            with patch('app.sqs_client', sqs):
                with patch('app.S3_BUCKET_NAME', bucket_name):
                    with patch('app.SQS_QUEUE_URL', queue_url):
                        processed_count = poll_sqs()
                        assert processed_count == 0

    def test_poll_sqs_partial_success(self, sample_message_data):
        """Test polling with some messages failing"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Add valid message
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(sample_message_data)
        )

        # Add invalid message
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody="invalid json"
        )

        # Patch clients
        with patch('app.s3_client', s3):
            with patch('app.sqs_client', sqs):
                with patch('app.S3_BUCKET_NAME', bucket_name):
                    with patch('app.SQS_QUEUE_URL', queue_url):
                        processed_count = poll_sqs()
                        assert processed_count == 1  # Only one should succeed

    def test_poll_sqs_verifies_s3_upload(self, sample_message_data):
        """Test that polling correctly uploads to S3"""
        # Setup mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        bucket_name = 'test-bucket'
        s3.create_bucket(Bucket=bucket_name)

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Add message
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(sample_message_data)
        )

        # Patch clients
        with patch('app.s3_client', s3):
            with patch('app.sqs_client', sqs):
                with patch('app.S3_BUCKET_NAME', bucket_name):
                    with patch('app.SQS_QUEUE_URL', queue_url):
                        poll_sqs()

                        # Verify S3 contains the message
                        now = datetime.utcnow()
                        prefix = f"messages/{now.year}/{now.month:02d}/{now.day:02d}/"

                        response = s3.list_objects_v2(Bucket=bucket_name, Prefix=prefix)
                        assert 'Contents' in response
                        assert len(response['Contents']) == 1


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
