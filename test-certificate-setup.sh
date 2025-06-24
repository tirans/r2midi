#!/bin/bash

# test-certificate-setup.sh - Test the common certificate setup functionality

set -euo pipefail

echo "🧪 Testing Common Certificate Setup"
echo "=================================="

# Source the common certificate setup
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/scripts/common-certificate-setup.sh"

# Test 1: Environment detection
echo ""
echo "Test 1: Environment Detection"
env_type=$(detect_environment)
echo "  • Environment: $env_type"

# Test 2: Certificate setup without signing
echo ""
echo "Test 2: Certificate Setup (skip signing)"
setup_certificates "true"
get_certificate_summary

# Test 3: Certificate setup with signing
echo ""
echo "Test 3: Certificate Setup (with signing)"
setup_certificates "false"
get_certificate_summary

# Test 4: List available certificates
echo ""
echo "Test 4: Available Certificates"
echo "  • Checking keychain for certificates..."
security find-identity -v -p codesigning | grep "Developer ID" || echo "  • No Developer ID certificates found"

# Test 5: Check for P12 files
echo ""
echo "Test 5: P12 Files"
if [ -d "apple_credentials/certificates" ]; then
    p12_count=$(find apple_credentials/certificates -name "*.p12" -type f 2>/dev/null | wc -l)
    echo "  • P12 files found: $p12_count"
    find apple_credentials/certificates -name "*.p12" -type f 2>/dev/null | while read -r p12; do
        echo "    - $(basename "$p12")"
    done
else
    echo "  • Directory apple_credentials/certificates not found"
fi

# Test 6: Build summary test
echo ""
echo "Test 6: Build Summary Examples"
print_build_summary "Test App" "success" "Additional build info here"
echo ""
print_build_summary "Failed App" "failed" "Build failed due to test"

# Cleanup
echo ""
echo "Test 7: Cleanup"
cleanup_certificates
echo "  • Cleanup completed"

echo ""
echo "✅ Certificate setup tests completed!"
