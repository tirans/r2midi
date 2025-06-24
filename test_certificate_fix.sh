#!/bin/bash

# Test script to verify the certificate selection fix

# Source the modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/.github/scripts/modules"

source "$MODULES_DIR/logging-utils.sh"
source "$MODULES_DIR/certificate-manager.sh"

echo "Testing certificate selection fix..."
echo "=================================="

# Test 1: Check that select_signing_identity only returns the certificate name
echo ""
echo "Test 1: Testing select_signing_identity output"
echo "----------------------------------------------"

# Capture the output
identity_output=$(select_signing_identity "Developer ID Application" "79449BGAM5" 2>/dev/null)

echo "Raw output from select_signing_identity:"
echo "'$identity_output'"
echo ""

# Check if output contains only the certificate name (no log messages)
if [[ "$identity_output" == *"ℹ️"* ]] || [[ "$identity_output" == *"✅"* ]]; then
    echo "❌ FAIL: Output contains log messages"
    echo "This indicates the fix didn't work properly"
else
    echo "✅ PASS: Output contains only certificate name"
    echo "Certificate: $identity_output"
fi

echo ""
echo "Test 2: Testing with stderr visible"
echo "-----------------------------------"

# Test with stderr visible to see log messages
echo "Running select_signing_identity with stderr visible:"
identity_output2=$(select_signing_identity "Developer ID Application" "79449BGAM5")
echo "Certificate returned: '$identity_output2'"

echo ""
echo "Test completed!"