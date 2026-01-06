"""
End-to-End Integration Test
Tests the complete message flow using REAL AWS services

IMPORTANT: This test uses real AWS resources and incurs costs!
Run manually before major releases, not in CI.

Prerequisites:
1. AWS infrastructure must be deployed (terraform apply)
2. Both ECS services must be running
3. AWS credentials must be configured
4. Environment variables must be set

Usage:
    export ALB_DNS="your-alb-dns.us-east-1.elb.amazonaws.com"
    export API_TOKEN="your-api-token-from-ssm"
    export S3_BUCKET_NAME="your-bucket-name"

    pytest e2e_test.py -v -s
"""

import pytest
import boto3
import requests
import json
import time
import os
from datetime import datetime


# Test configuration from environment
ALB_DNS = os.getenv('ALB_DNS')
API_TOKEN = os.getenv('API_TOKEN')
S3_BUCKET_NAME = os.getenv('S3_BUCKET_NAME')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')


@pytest.fixture(scope="module")
def aws_clients():
    """Initialize real AWS clients"""
    return {
        's3': boto3.client('s3', region_name=AWS_REGION),
        'sqs': boto3.client('sqs', region_name=AWS_REGION),
        'ssm': boto3.client('ssm', region_name=AWS_REGION)
    }


@pytest.fixture(scope="module")
def verify_prerequisites():
    """Verify all prerequisites are met"""
    missing = []

    if not ALB_DNS:
        missing.append("ALB_DNS")
    if not API_TOKEN:
        missing.append("API_TOKEN")
    if not S3_BUCKET_NAME:
        missing.append("S3_BUCKET_NAME")

    if missing:
        pytest.skip(f"Missing required environment variables: {', '.join(missing)}")

    yield

    # Cleanup happens here after all tests


def test_e2e_message_flow(aws_clients, verify_prerequisites):
    """
    Complete end-to-end test:
    1. Send message via Service 1 API (through ALB)
    2. Verify message reaches SQS
    3. Wait for Service 2 to process
    4. Verify message appears in S3
    5. Cleanup test data
    """
    s3 = aws_clients['s3']

    # Unique test data
    test_timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    test_subject = f"E2E Test {test_timestamp}"

    # 1. Prepare test payload
    payload = {
        "data": {
            "email_subject": test_subject,
            "email_sender": "e2e-test@example.com",
            "email_timestream": datetime.utcnow().isoformat() + "Z",
            "email_content": "This is an end-to-end test message"
        },
        "token": API_TOKEN
    }

    print(f"\n[1/5] Sending message to Service 1 API...")
    print(f"      URL: http://{ALB_DNS}/api/message")

    # 2. Send message via Service 1 API
    try:
        response = requests.post(
            f"http://{ALB_DNS}/api/message",
            json=payload,
            timeout=10
        )
        print(f"      Response status: {response.status_code}")

        assert response.status_code == 200, f"API returned {response.status_code}: {response.text}"

        response_data = response.json()
        assert response_data['status'] == 'success'
        message_id = response_data['message_id']
        print(f"      Message ID: {message_id}")

    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}\nMake sure ALB DNS is correct and services are running")

    print(f"\n[2/5] Message sent successfully to SQS")

    # 3. Wait for Service 2 to process the message
    print(f"\n[3/5] Waiting for Service 2 to process message...")
    print(f"      (Service 2 polls every 10 seconds)")

    max_wait_time = 60  # Wait up to 60 seconds
    check_interval = 5
    elapsed = 0
    file_found = False
    s3_key = None

    while elapsed < max_wait_time and not file_found:
        time.sleep(check_interval)
        elapsed += check_interval
        print(f"      Waiting... ({elapsed}s / {max_wait_time}s)")

        # 4. Check if file appeared in S3
        now = datetime.utcnow()
        prefix = f"messages/{now.year}/{now.month:02d}/{now.day:02d}/"

        try:
            response = s3.list_objects_v2(
                Bucket=S3_BUCKET_NAME,
                Prefix=prefix
            )

            if 'Contents' in response:
                # Look for our specific message
                for obj in response['Contents']:
                    # Fetch the file content to verify it's our message
                    file_obj = s3.get_object(Bucket=S3_BUCKET_NAME, Key=obj['Key'])
                    file_content = json.loads(file_obj['Body'].read())

                    if file_content.get('email_subject') == test_subject:
                        file_found = True
                        s3_key = obj['Key']
                        print(f"\n[4/5] Message found in S3!")
                        print(f"      S3 Key: {s3_key}")
                        print(f"      Processing time: ~{elapsed} seconds")
                        break

        except Exception as e:
            print(f"      Error checking S3: {e}")

    if not file_found:
        pytest.fail(f"Message not found in S3 after {max_wait_time} seconds. Check Service 2 logs.")

    # 5. Verify S3 file content
    print(f"\n[5/5] Verifying S3 file content...")

    try:
        file_obj = s3.get_object(Bucket=S3_BUCKET_NAME, Key=s3_key)
        stored_data = json.loads(file_obj['Body'].read())

        assert stored_data['email_subject'] == test_subject
        assert stored_data['email_sender'] == "e2e-test@example.com"
        assert stored_data['email_content'] == "This is an end-to-end test message"

        print(f"      Content verified successfully!")

    except Exception as e:
        pytest.fail(f"Failed to verify S3 content: {e}")

    # 6. Cleanup - Delete test file from S3
    print(f"\n[Cleanup] Deleting test file from S3...")
    try:
        s3.delete_object(Bucket=S3_BUCKET_NAME, Key=s3_key)
        print(f"         Test file deleted: {s3_key}")
    except Exception as e:
        print(f"         Warning: Failed to delete test file: {e}")

    print(f"\n{'='*60}")
    print(f"E2E TEST PASSED")
    print(f"{'='*60}")
    print(f"Message traveled successfully:")
    print(f"  API (Service 1) → SQS → Service 2 → S3")
    print(f"Total processing time: ~{elapsed} seconds")
    print(f"{'='*60}\n")


def test_health_check(verify_prerequisites):
    """Test that the API health endpoint is accessible"""
    print(f"\n[Health Check] Testing API availability...")

    try:
        response = requests.get(
            f"http://{ALB_DNS}/health",
            timeout=5
        )
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'healthy'
        print(f"               API is healthy!")

    except requests.exceptions.RequestException as e:
        pytest.fail(f"Health check failed: {e}")


def test_invalid_token(verify_prerequisites):
    """Test that invalid tokens are rejected"""
    print(f"\n[Security Test] Testing invalid token rejection...")

    payload = {
        "data": {
            "email_subject": "Test",
            "email_sender": "test@example.com",
            "email_timestream": datetime.utcnow().isoformat() + "Z",
            "email_content": "Test"
        },
        "token": "invalid-token-12345"
    }

    try:
        response = requests.post(
            f"http://{ALB_DNS}/api/message",
            json=payload,
            timeout=10
        )
        assert response.status_code == 401
        print(f"                Invalid token correctly rejected!")

    except requests.exceptions.RequestException as e:
        pytest.fail(f"Security test failed: {e}")


if __name__ == '__main__':
    print("\n" + "="*60)
    print("End-to-End Integration Test Suite")
    print("="*60)
    print("\nThis test uses REAL AWS resources!")
    print("\nRequired environment variables:")
    print("  - ALB_DNS")
    print("  - API_TOKEN")
    print("  - S3_BUCKET_NAME")
    print("  - AWS_REGION (optional, defaults to us-east-1)")
    print("\nRun with: pytest e2e_test.py -v -s")
    print("="*60 + "\n")

    pytest.main([__file__, '-v', '-s'])
