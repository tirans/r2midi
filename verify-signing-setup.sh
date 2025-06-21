#!/bin/bash
# verify-signing-setup.sh - Verify Apple Developer signing setup
set -euo pipefail

echo "🔍 Verifying Apple Developer Signing Setup..."

# Check if config file exists
if [ ! -f "apple_credentials/config/app_config.json" ]; then
    echo "❌ Apple credentials config file not found"
    echo "   Expected: apple_credentials/config/app_config.json"
    exit 1
fi

# Load credentials
TEAM_ID=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['team_id'])")
APPLE_ID=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['apple_id'])")

echo "📋 Configuration:"
echo "   Team ID: $TEAM_ID"
echo "   Apple ID: $APPLE_ID"

# Check entitlements
if [ -f "entitlements.plist" ]; then
    echo "✅ Entitlements file found"
else
    echo "❌ Entitlements file missing"
    exit 1
fi

# Check certificates
echo "🔐 Checking certificates..."

APP_FOUND=false
INSTALLER_FOUND=false

while IFS= read -r line; do
    if [[ $line == *"Developer ID Application"* && $line == *"$TEAM_ID"* ]]; then
        echo "✅ Application certificate: $line"
        APP_FOUND=true
    elif [[ $line == *"Developer ID Installer"* && $line == *"$TEAM_ID"* ]]; then
        echo "✅ Installer certificate: $line"
        INSTALLER_FOUND=true
    fi
done < <(security find-identity -v -p codesigning 2>/dev/null || echo "")

if [ "$APP_FOUND" = "false" ]; then
    echo "❌ Application signing certificate not found for team $TEAM_ID"
    exit 1
fi

if [ "$INSTALLER_FOUND" = "false" ]; then
    echo "❌ Installer signing certificate not found for team $TEAM_ID"
    exit 1
fi

# Check notarytool
if command -v xcrun >/dev/null && xcrun notarytool --help >/dev/null 2>&1; then
    echo "✅ notarytool available"
else
    echo "❌ notarytool not available"
    exit 1
fi

# Check stapler
if command -v xcrun >/dev/null && xcrun stapler --help >/dev/null 2>&1; then
    echo "✅ stapler available"
else
    echo "❌ stapler not available"
    exit 1
fi

echo ""
echo "🎉 Apple Developer signing setup verified!"
echo "Ready to build signed and notarized packages."
