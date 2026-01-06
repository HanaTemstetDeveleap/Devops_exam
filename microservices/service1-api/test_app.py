"""
Unit and Integration Tests for Service 1 - REST API
Tests token validation, payload validation, SQS integration
"""

import pytest
import json
import os
from unittest.mock import patch, MagicMock
from moto import mock_ssm, mock_sqs
import boto3

# Import Flask app
from app import app, validate_payload, validate_token, send_to_sqs, get_api_token


# Test Fixtures
@pytest.fixture
def client():
    """Flask test client"""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


@pytest.fixture
def valid_payload():
    """Valid request payload"""
    return {
        "data": {
            "email_subject": "Test Subject",
            "email_sender": "sender@example.com",
            "email_timestream": "2024-01-01T12:00:00Z",
            "email_content": "Test content"
        },
        "token": "test-secret-token-12345"
    }


# Unit Tests - Payload Validation
class TestPayloadValidation:
    """Test payload validation logic"""

    def test_valid_payload(self, valid_payload):
        """Test validation with valid payload"""
        is_valid, error = validate_payload(valid_payload)
        assert is_valid is True
        assert error is None

    def test_missing_data_field(self):
        """Test validation fails when 'data' field is missing"""
        payload = {"token": "test-token"}
        is_valid, error = validate_payload(payload)
        assert is_valid is False
        assert "Missing 'data' field" in error

    def test_missing_token_field(self):
        """Test validation fails when 'token' field is missing"""
        payload = {
            "data": {
                "email_subject": "Test",
                "email_sender": "test@example.com",
                "email_timestream": "2024-01-01T12:00:00Z",
                "email_content": "Test"
            }
        }
        is_valid, error = validate_payload(payload)
        assert is_valid is False
        assert "Missing 'token' field" in error

    def test_missing_email_subject(self, valid_payload):
        """Test validation fails when email_subject is missing"""
        del valid_payload['data']['email_subject']
        is_valid, error = validate_payload(valid_payload)
        assert is_valid is False
        assert "email_subject" in error

    def test_missing_multiple_fields(self, valid_payload):
        """Test validation fails when multiple required fields are missing"""
        del valid_payload['data']['email_subject']
        del valid_payload['data']['email_content']
        is_valid, error = validate_payload(valid_payload)
        assert is_valid is False
        assert "email_subject" in error
        assert "email_content" in error


# Unit Tests - Token Validation
class TestTokenValidation:
    """Test token validation against SSM"""

    @mock_ssm
    def test_valid_token(self):
        """Test validation succeeds with correct token"""
        # Setup mock SSM
        ssm = boto3.client('ssm', region_name='us-east-1')
        ssm.put_parameter(
            Name='/devops-exam/dev/api-token',
            Value='test-secret-token-12345',
            Type='SecureString'
        )

        # Clear cache
        import app as app_module
        app_module.api_token_cache = None

        # Test validation
        is_valid, error = validate_token('test-secret-token-12345')
        assert is_valid is True
        assert error is None

    @mock_ssm
    def test_invalid_token(self):
        """Test validation fails with incorrect token"""
        # Setup mock SSM
        ssm = boto3.client('ssm', region_name='us-east-1')
        ssm.put_parameter(
            Name='/devops-exam/dev/api-token',
            Value='correct-token',
            Type='SecureString'
        )

        # Clear cache
        import app as app_module
        app_module.api_token_cache = None

        # Test validation
        is_valid, error = validate_token('wrong-token')
        assert is_valid is False
        assert "Invalid token" in error

    @mock_ssm
    def test_token_caching(self):
        """Test that token is cached after first retrieval"""
        # Setup mock SSM
        ssm = boto3.client('ssm', region_name='us-east-1')
        ssm.put_parameter(
            Name='/devops-exam/dev/api-token',
            Value='cached-token',
            Type='SecureString'
        )

        # Clear cache
        import app as app_module
        app_module.api_token_cache = None

        # First call - should retrieve from SSM
        token1 = get_api_token()
        assert token1 == 'cached-token'

        # Second call - should use cache
        token2 = get_api_token()
        assert token2 == 'cached-token'
        assert app_module.api_token_cache == 'cached-token'


# Unit Tests - SQS Integration
class TestSQSIntegration:
    """Test SQS message sending"""

    @mock_sqs
    def test_send_to_sqs_success(self):
        """Test successful message send to SQS"""
        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']

        # Set environment variable
        os.environ['SQS_QUEUE_URL'] = queue_url

        # Test data
        test_data = {
            "email_subject": "Test",
            "email_sender": "test@example.com",
            "email_timestream": "2024-01-01T12:00:00Z",
            "email_content": "Test content"
        }

        # Send message
        success, message_id = send_to_sqs(test_data)
        assert success is True
        assert message_id is not None

        # Verify message in queue
        messages = sqs.receive_message(QueueUrl=queue_url)
        assert 'Messages' in messages
        assert len(messages['Messages']) == 1

        body = json.loads(messages['Messages'][0]['Body'])
        assert body == test_data


# Integration Tests - API Endpoints
class TestAPIEndpoints:
    """Test Flask API endpoints"""

    def test_health_check(self, client):
        """Test health check endpoint"""
        response = client.get('/health')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'healthy'

    def test_message_endpoint_missing_content_type(self, client):
        """Test endpoint rejects non-JSON requests"""
        response = client.post('/api/message', data='not json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'Content-Type must be application/json' in data['error']

    @mock_ssm
    @mock_sqs
    def test_message_endpoint_success(self, client, valid_payload):
        """Test successful message processing"""
        # Setup mock SSM
        ssm = boto3.client('ssm', region_name='us-east-1')
        ssm.put_parameter(
            Name='/devops-exam/dev/api-token',
            Value='test-secret-token-12345',
            Type='SecureString'
        )

        # Setup mock SQS
        sqs = boto3.client('sqs', region_name='us-east-1')
        queue = sqs.create_queue(QueueName='test-queue')
        queue_url = queue['QueueUrl']
        os.environ['SQS_QUEUE_URL'] = queue_url

        # Clear cache
        import app as app_module
        app_module.api_token_cache = None

        # Send request
        response = client.post(
            '/api/message',
            data=json.dumps(valid_payload),
            content_type='application/json'
        )

        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'success'
        assert 'message_id' in data

    @mock_ssm
    def test_message_endpoint_invalid_token(self, client, valid_payload):
        """Test endpoint rejects invalid token"""
        # Setup mock SSM with different token
        ssm = boto3.client('ssm', region_name='us-east-1')
        ssm.put_parameter(
            Name='/devops-exam/dev/api-token',
            Value='correct-token',
            Type='SecureString'
        )

        # Clear cache
        import app as app_module
        app_module.api_token_cache = None

        # Send request with wrong token
        valid_payload['token'] = 'wrong-token'
        response = client.post(
            '/api/message',
            data=json.dumps(valid_payload),
            content_type='application/json'
        )

        assert response.status_code == 401
        data = json.loads(response.data)
        assert 'Invalid token' in data['error']

    def test_message_endpoint_missing_field(self, client, valid_payload):
        """Test endpoint rejects payload with missing fields"""
        # Remove required field
        del valid_payload['data']['email_subject']

        response = client.post(
            '/api/message',
            data=json.dumps(valid_payload),
            content_type='application/json'
        )

        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'email_subject' in data['error']

    def test_message_endpoint_empty_payload(self, client):
        """Test endpoint rejects empty payload"""
        response = client.post(
            '/api/message',
            data=json.dumps({}),
            content_type='application/json'
        )

        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'Missing' in data['error']


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
