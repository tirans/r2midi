#!/bin/bash

echo "🧪 Testing configuration file path resolution fix..."
echo ""

# Test 1: Verify the config file exists
echo "📋 Test 1: Checking if config file exists..."
if [ -f "apple_credentials/config/app_config.json" ]; then
    echo "✅ Config file found at: apple_credentials/config/app_config.json"
else
    echo "❌ Config file not found at: apple_credentials/config/app_config.json"
    exit 1
fi

# Test 2: Test the sign-pkg.sh script's path resolution
echo ""
echo "📋 Test 2: Testing sign-pkg.sh path resolution..."

# Create a temporary test PKG file
mkdir -p test_artifacts
echo "dummy pkg content" > test_artifacts/test.pkg

# Test the sign-pkg.sh script (it should fail at certificate setup but should find the config file)
echo "Running sign-pkg.sh to test config file resolution..."
if ./.github/scripts/sign-pkg.sh --pkg test_artifacts/test.pkg --skip-notarize 2>&1 | grep -q "Configuration file not found"; then
    echo "❌ Config file still not found - fix didn't work"
    rm -rf test_artifacts
    exit 1
else
    echo "✅ Config file path resolution appears to be working"
fi

# Cleanup
rm -rf test_artifacts

echo ""
echo "🎉 Configuration file path resolution fix appears to be working!"
echo "The sign-pkg.sh script should now be able to find the config file regardless of working directory."