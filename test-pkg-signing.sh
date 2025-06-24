#!/bin/bash
set -euo pipefail

# test-pkg-signing.sh - Test the PKG signing functionality

echo "🧪 Testing PKG signing functionality..."

# Test 1: Check if the sign-pkg.sh script exists and is executable
echo ""
echo "Test 1: Checking sign-pkg.sh script..."
if [ -f ".github/scripts/sign-pkg.sh" ]; then
    echo "✅ sign-pkg.sh exists"
    if [ -x ".github/scripts/sign-pkg.sh" ]; then
        echo "✅ sign-pkg.sh is executable"
    else
        echo "❌ sign-pkg.sh is not executable"
        exit 1
    fi
else
    echo "❌ sign-pkg.sh not found"
    exit 1
fi

# Test 2: Check configuration file
echo ""
echo "Test 2: Checking configuration file..."
CONFIG_FILE="apple_credentials/config/app_config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Configuration file exists: $CONFIG_FILE"
    
    # Test reading configuration values
    if python3 -c "import json; config = json.load(open('$CONFIG_FILE')); print('p12_path:', config['apple_developer']['p12_path']); print('p12_password:', '***' if config['apple_developer']['p12_password'] else 'MISSING')" 2>/dev/null; then
        echo "✅ Configuration file is valid JSON and contains required fields"
    else
        echo "❌ Configuration file is invalid or missing required fields"
        exit 1
    fi
else
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Test 3: Check installer certificate
echo ""
echo "Test 3: Checking installer certificate..."
P12_PATH=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['apple_developer']['p12_path'])" 2>/dev/null || echo "")
if [ -n "$P12_PATH" ]; then
    INSTALLER_CERT_PATH="${P12_PATH}/installer_cert.p12"
    if [ -f "$INSTALLER_CERT_PATH" ]; then
        echo "✅ Installer certificate exists: $INSTALLER_CERT_PATH"
        
        # Check certificate file size
        CERT_SIZE=$(stat -f%z "$INSTALLER_CERT_PATH" 2>/dev/null || echo "0")
        if [ "$CERT_SIZE" -gt 0 ]; then
            echo "✅ Installer certificate file is not empty (${CERT_SIZE} bytes)"
        else
            echo "❌ Installer certificate file is empty"
            exit 1
        fi
    else
        echo "❌ Installer certificate not found: $INSTALLER_CERT_PATH"
        exit 1
    fi
else
    echo "❌ Could not read p12_path from configuration"
    exit 1
fi

# Test 4: Check required tools
echo ""
echo "Test 4: Checking required tools..."
REQUIRED_TOOLS=("security" "pkgbuild" "productsign" "xcrun" "python3")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool is available"
    else
        echo "❌ $tool is not available"
        exit 1
    fi
done

# Test 5: Test script help functionality
echo ""
echo "Test 5: Testing script help functionality..."
if .github/scripts/sign-pkg.sh --help >/dev/null 2>&1; then
    echo "✅ Script help works correctly"
else
    echo "❌ Script help failed"
    exit 1
fi

# Test 6: Test script with missing PKG (should fail gracefully)
echo ""
echo "Test 6: Testing script with missing PKG..."
if .github/scripts/sign-pkg.sh --pkg "nonexistent.pkg" 2>/dev/null; then
    echo "❌ Script should have failed with missing PKG"
    exit 1
else
    echo "✅ Script correctly handles missing PKG file"
fi

echo ""
echo "🎉 All tests passed! PKG signing functionality is ready."
echo ""
echo "📋 Summary:"
echo "  ✅ sign-pkg.sh script is available and executable"
echo "  ✅ Configuration file is valid and contains required fields"
echo "  ✅ Installer certificate exists and is not empty"
echo "  ✅ All required tools are available"
echo "  ✅ Script help functionality works"
echo "  ✅ Script handles errors gracefully"
echo ""
echo "🚀 Ready to test with actual PKG files!"
echo ""
echo "💡 To test with a real PKG file:"
echo "   1. Build a client or server: ./build-client-local.sh --version 1.0.0-test"
echo "   2. The PKG will be automatically signed and notarized during the build process"
echo "   3. Check the build logs for signing and notarization status"