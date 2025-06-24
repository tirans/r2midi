#!/bin/bash

# test-certificate-fix.sh - Test the certificate setup and build flow

set -euo pipefail

echo "Testing Certificate Setup Fix"
echo "============================"

# Source the common certificate setup
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/scripts/common-certificate-setup.sh"

# Test certificate setup
echo ""
echo "Test 1: Certificate Setup (no skip)"
if setup_certificates "false"; then
    echo "Certificate setup succeeded (returned 0)"
else
    echo "Certificate setup failed (returned non-zero) - this is expected if no certs available"
fi

get_certificate_summary

# Test that we can continue even without certificates
echo ""
echo "Test 2: Continuing without certificates"
echo "CERT_LOADED: $CERT_LOADED"
echo "CERT_SUMMARY: $CERT_SUMMARY"

if [ "$CERT_LOADED" = "false" ]; then
    echo "No certificates loaded - would create unsigned build"
else
    echo "Certificates loaded - would create signed build"
fi

echo ""
echo "Test complete!"
