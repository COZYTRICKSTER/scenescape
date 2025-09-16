#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation  
# SPDX-License-Identifier: Apache-2.0

# Script to generate secrets and certificates for SceneScape deployment

set -e

SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secrets"
CERTS_DIR="${SECRETS_DIR}/certs"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_info "Generating secrets in: ${SECRETS_DIR}"

# Create certificates directory
mkdir -p "${CERTS_DIR}"

# Generate passwords and tokens
echo_info "Generating authentication secrets..."
openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}|;:,.<>?/~' | head -c 24 > "${SECRETS_DIR}/django"
openssl rand -base64 32 > "${SECRETS_DIR}/browser.auth"
openssl rand -base64 32 > "${SECRETS_DIR}/calibration.auth"
openssl rand -base64 32 > "${SECRETS_DIR}/controller.auth"

# Generate self-signed certificates for development
echo_info "Generating self-signed certificates..."

# Root CA
openssl genrsa -out "${CERTS_DIR}/scenescape-ca.key" 4096
openssl req -new -x509 -days 365 -key "${CERTS_DIR}/scenescape-ca.key" \
    -out "${CERTS_DIR}/scenescape-ca.pem" \
    -subj "/C=US/ST=State/L=City/O=SceneScape/OU=Development/CN=SceneScape-CA"

# Web server certificate
openssl genrsa -out "${CERTS_DIR}/scenescape-web.key" 2048
openssl req -new -key "${CERTS_DIR}/scenescape-web.key" \
    -out "${CERTS_DIR}/scenescape-web.csr" \
    -subj "/C=US/ST=State/L=City/O=SceneScape/OU=Development/CN=web.scenescape.intel.com"
openssl x509 -req -days 365 -in "${CERTS_DIR}/scenescape-web.csr" \
    -CA "${CERTS_DIR}/scenescape-ca.pem" -CAkey "${CERTS_DIR}/scenescape-ca.key" -CAcreateserial \
    -out "${CERTS_DIR}/scenescape-web.crt"

# VDMS client certificate
openssl genrsa -out "${CERTS_DIR}/scenescape-vdms-c.key" 2048
openssl req -new -key "${CERTS_DIR}/scenescape-vdms-c.key" \
    -out "${CERTS_DIR}/scenescape-vdms-c.csr" \
    -subj "/C=US/ST=State/L=City/O=SceneScape/OU=Development/CN=vdms-client"
openssl x509 -req -days 365 -in "${CERTS_DIR}/scenescape-vdms-c.csr" \
    -CA "${CERTS_DIR}/scenescape-ca.pem" -CAkey "${CERTS_DIR}/scenescape-ca.key" -CAcreateserial \
    -out "${CERTS_DIR}/scenescape-vdms-c.crt"

# VDMS server certificate  
openssl genrsa -out "${CERTS_DIR}/scenescape-vdms-s.key" 2048
openssl req -new -key "${CERTS_DIR}/scenescape-vdms-s.key" \
    -out "${CERTS_DIR}/scenescape-vdms-s.csr" \
    -subj "/C=US/ST=State/L=City/O=SceneScape/OU=Development/CN=vdms.scenescape.intel.com"
openssl x509 -req -days 365 -in "${CERTS_DIR}/scenescape-vdms-s.csr" \
    -CA "${CERTS_DIR}/scenescape-ca.pem" -CAkey "${CERTS_DIR}/scenescape-ca.key" -CAcreateserial \
    -out "${CERTS_DIR}/scenescape-vdms-s.crt"

# Clean up CSR files
rm -f "${CERTS_DIR}"/*.csr

# Set appropriate permissions
chmod 600 "${CERTS_DIR}"/*.key
chmod 644 "${CERTS_DIR}"/*.pem "${CERTS_DIR}"/*.crt
chmod 600 "${SECRETS_DIR}/django" "${SECRETS_DIR}"/*.auth

echo_info "Secrets generated successfully!"
echo_info "Root CA certificate: ${CERTS_DIR}/scenescape-ca.pem"
echo_info "Secrets directory: ${SECRETS_DIR}"

# Display generated credentials
echo ""
echo "Generated credentials:"
echo "SUPASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}|;:,.<>?/~' | head -c 24)"
echo "DBROOT=$(openssl rand -base64 32)"
