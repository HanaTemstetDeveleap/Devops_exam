"""
Microservice 1 - REST API
Receives HTTP requests, validates token and payload, sends to SQS
"""

import os
import json
import boto3
from flask import Flask, request, jsonify
from botocore.exceptions import ClientError

# Initialize Flask app
app = Flask(__name__)

# AWS clients
ssm_client = boto3.client('ssm', region_name=os.getenv('AWS_REGION', 'us-east-1'))
sqs_client = boto3.client('sqs', region_name=os.getenv('AWS_REGION', 'us-east-1'))

# Configuration from environment variables
SSM_PARAMETER_NAME = os.getenv('SSM_PARAMETER_NAME', '/devops-exam/dev/api-token')
SQS_QUEUE_URL = os.getenv('SQS_QUEUE_URL')

# Cache for API token (avoid calling SSM on every request)
api_token_cache = None


def get_api_token():
    """Retrieve API token from SSM Parameter Store"""
    global api_token_cache

    if api_token_cache:
        return api_token_cache

    try:
        response = ssm_client.get_parameter(
            Name=SSM_PARAMETER_NAME,
            WithDecryption=True
        )
        api_token_cache = response['Parameter']['Value']
        return api_token_cache
    except ClientError as e:
        app.logger.error(f"Failed to retrieve token from SSM: {e}")
        raise


def validate_payload(payload):
    """
    Validate request payload structure
    Returns: (is_valid, error_message)
    """
    # Check if 'data' field exists
    if 'data' not in payload:
        return False, "Missing 'data' field"

    # Check if 'token' field exists
    if 'token' not in payload:
        return False, "Missing 'token' field"

    data = payload['data']

    # Validate all 4 required fields in data
    required_fields = ['email_subject', 'email_sender', 'email_timestream', 'email_content']
    missing_fields = [field for field in required_fields if field not in data]

    if missing_fields:
        return False, f"Missing required fields in data: {', '.join(missing_fields)}"

    return True, None


def validate_token(provided_token):
    """
    Validate provided token against SSM stored token
    Returns: (is_valid, error_message)
    """
    try:
        expected_token = get_api_token()

        if provided_token == expected_token:
            return True, None
        else:
            return False, "Invalid ???token"
    except Exception as e:
        app.logger.error(f"Token validation error: {e}")
        return False, "Token validation failed"


def send_to_sqs(data):
    """Send validated data to SQS queue"""
    try:
        response = sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(data)
        )
        return True, response['MessageId']
    except ClientError as e:
        app.logger.error(f"Failed to send message to SQS: {e}")
        return False, str(e)


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200


@app.route('/api/message', methods=['POST'])
def process_message():
    """
    Main endpoint - receives message, validates, and sends to SQS

    Expected payload:
    {
        "data": {
            "email_subject": "...",
            "email_sender": "...",
            "email_timestream": "...",
            "email_content": "..."
        },
        "token": "..."
    }
    """
    # Get JSON payload
    if not request.is_json:
        return jsonify({"error": "Content-Type must be application/json"}), 400

    payload = request.get_json()

    # Validate payload structure
    is_valid, error_msg = validate_payload(payload)
    if not is_valid:
        return jsonify({"error": error_msg}), 400

    # Validate token
    is_valid, error_msg = validate_token(payload['token'])
    if not is_valid:
        return jsonify({"error": error_msg}), 401

    # Send data to SQS
    success, result = send_to_sqs(payload['data'])
    if not success:
        return jsonify({"error": f"Failed to send message: {result}"}), 500

    return jsonify({
        "status": "success",
        "message": "Message sent to queue",
        "message_id": result
    }), 200


if __name__ == '__main__':
    # Validate required environment variables
    if not SQS_QUEUE_URL:
        raise ValueError("SQS_QUEUE_URL environment variable is required")

    # Run Flask app
    app.run(host='0.0.0.0', port=8080, debug=False)
