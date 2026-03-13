#!/usr/bin/env python3
import json
import time
import base64
import hashlib
import hmac
import requests

# Read the JWT secret
with open('/data/blockchain/storage/base/jwt.hex', 'r') as f:
    secret = f.read().strip()

# Create a simple JWT token manually
header = {"alg": "HS256", "typ": "JWT"}
payload = {"iat": int(time.time())}

# Encode header and payload
header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")

# Create signature
message = f"{header_b64}.{payload_b64}"
signature = hmac.new(bytes.fromhex(secret), message.encode(), hashlib.sha256).digest()
signature_b64 = base64.urlsafe_b64encode(signature).decode().rstrip("=")

# Combine to create JWT
token = f"{header_b64}.{payload_b64}.{signature_b64}"

# Make a request to the authenticated RPC
headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {token}"
}

data = {
    "jsonrpc": "2.0",
    "method": "engine_exchangeCapabilities",
    "params": [["prague", "cancun", "shanghai"]],
    "id": 1
}

try:
    response = requests.post("http://127.0.0.1:8562", json=data, headers=headers)
    print(f"Status Code: {response.status_code}")
    print(f"Response Text: {response.text}")
    if response.status_code == 200:
        print(f"Response JSON: {json.dumps(response.json(), indent=2)}")
except Exception as e:
    print(f"Error: {e}")