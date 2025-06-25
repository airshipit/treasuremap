#!/usr/bin/env python3
# filepath: generate_security_keys.py

import os
import secrets
import argparse
from cryptography.fernet import Fernet

# Set up argument parsing
parser = argparse.ArgumentParser(description='Generate security keys for Airflow')
parser.add_argument('--layer', type=str, choices=['type', 'site'], 
                    default='type', help='Layer for layeringDefinition (type or site)')
parser.add_argument('--output-dir', type=str, dest='output_dir', 
                    default='.', help='Output directory for generated files')

args = parser.parse_args()

# Get arguments
layer = args.layer
OUTPUT_DIR = args.output_dir

# Create output directory if it doesn't exist
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Generate JWT secret
jwt_secret = secrets.token_hex(32)  # 32 bytes (64 hex chars) for JWT

# Generate Fernet key
fernet_key = Fernet.generate_key().decode()

# Template for the YAML files
yaml_template = """---
schema: deckhand/Passphrase/v1
metadata:
  schema: metadata/Document/v1
  name: {name}
  layeringDefinition:
    abstract: false
    layer: {layer}
  storagePolicy: cleartext
data: {data}
...
"""

# Create the JWT secret file
with open(os.path.join(OUTPUT_DIR, "ucp_airflow_api_auth_jwt_secret.yaml"), "w") as f:
    f.write(yaml_template.format(
        name="ucp_airflow_api_auth_jwt_secret",
        layer=layer,
        data=jwt_secret
    ))

# Create the Fernet key file
with open(os.path.join(OUTPUT_DIR, "ucp_airflow_core_fernet_key.yaml"), "w") as f:
    f.write(yaml_template.format(
        name="ucp_airflow_core_fernet_key",
        layer=layer,
        data=fernet_key
    ))

print(f"Files generated successfully in {OUTPUT_DIR}:")
print(f"- ucp_airflow_api_auth_jwt_secret.yaml (JWT key)")
print(f"- ucp_airflow_core_fernet_key.yaml (Fernet key)")
print(f"Layer: {layer}")
