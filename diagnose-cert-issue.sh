#!/bin/bash

# diagnose-cert-issue.sh - Diagnose the certificate loading issue

echo "Diagnosing Certificate Loading Issue"
echo "==================================="

# Check if P12 files exist
echo ""
echo "1. Checking for P12 files:"
if [ -d "apple_credentials/certificates" ]; then
    echo "   Directory exists: apple_credentials/certificates"
    echo "   Contents:"
    ls -la apple_credentials/certificates/*.p12 2>/dev/null || echo "   No .p12 files found"
else
    echo "   Directory not found: apple_credentials/certificates"
fi

# Check current certificates in keychain
echo ""
echo "2. Current certificates in keychain:"
security find-identity -v -p codesigning | grep "Developer ID" || echo "   No Developer ID certificates found"

# Test the certificate functions
echo ""
echo "3. Testing certificate functions:"
source scripts/common-certificate-setup.sh

# Test find_local_certificates
echo ""
echo "4. Testing find_local_certificates function:"
certs=$(find_local_certificates)
if [ -n "$certs" ]; then
    echo "   Found certificates:"
    echo "$certs" | while read -r cert; do
        echo "   - $cert"
    done
else
    echo "   No certificates found"
fi

# Test setup_certificates
echo ""
echo "5. Testing setup_certificates:"
setup_certificates "false"
echo "   Return code: $?"
echo "   CERT_LOADED: $CERT_LOADED"
echo "   CERT_SUMMARY: $CERT_SUMMARY"

echo ""
echo "Diagnosis complete!"
