#!/bin/bash

# setup-apple-certificates.sh - Setup Apple Developer certificates from GitHub Secrets
# Usage: ./setup-apple-certificates.sh

set -euo pipefail

echo "🔐 Setting up certificates from GitHub Secrets..."
echo "🔧 Using native macOS security framework"

# Check required environment variables
required_vars=(
    "APPLE_DEVELOPER_ID_APPLICATION_CERT"
    "APPLE_DEVELOPER_ID_INSTALLER_CERT"
    "APPLE_CERT_PASSWORD"
    "APPLE_ID"
    "APPLE_ID_PASSWORD"
    "APPLE_TEAM_ID"
)

echo "🔍 Verifying required secrets..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "❌ $var secret not found or empty"
        exit 1
    else
        echo "✅ $var: Present"
    fi
done

echo "✅ All required GitHub secrets found"
echo "Apple ID: $APPLE_ID"
echo "Team ID: $APPLE_TEAM_ID"

# Create temporary keychain for code signing
TEMP_KEYCHAIN="r2midi-native-build-$(date +%s).keychain"
TEMP_KEYCHAIN_PASSWORD="temp_password_$(date +%s)_$(openssl rand -hex 8)"

echo ""
echo "🔐 Creating temporary keychain: $TEMP_KEYCHAIN"

# Clean up any existing keychain with same name
security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true

# Create and configure new keychain
security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"  # 6 hour timeout
security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"

# Add to keychain search list
security list-keychains -d user -s "$TEMP_KEYCHAIN" $(security list-keychains -d user | sed s/\"//g)

echo "🔐 Decoding and importing certificates from GitHub secrets..."

# Decode and import application certificate
echo "$APPLE_DEVELOPER_ID_APPLICATION_CERT" | base64 --decode > app_cert.p12
if [ ! -s app_cert.p12 ]; then
    echo "❌ Failed to decode application certificate"
    exit 1
fi
echo "✅ Application certificate decoded"

# Decode and import installer certificate
echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > installer_cert.p12
if [ ! -s installer_cert.p12 ]; then
    echo "❌ Failed to decode installer certificate"
    exit 1
fi
echo "✅ Installer certificate decoded"

# Import application certificate (for app signing)
echo "📜 Importing application certificate..."
security import app_cert.p12 \
    -k "$TEMP_KEYCHAIN" \
    -P "$APPLE_CERT_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/productbuild

if [ $? -ne 0 ]; then
    echo "❌ Failed to import application certificate"
    exit 1
fi
echo "✅ Application certificate imported"

# Import installer certificate (for PKG signing)
echo "📜 Importing installer certificate..."
security import installer_cert.p12 \
    -k "$TEMP_KEYCHAIN" \
    -P "$APPLE_CERT_PASSWORD" \
    -T /usr/bin/productsign \
    -T /usr/bin/productbuild

if [ $? -ne 0 ]; then
    echo "❌ Failed to import installer certificate"
    exit 1
fi
echo "✅ Installer certificate imported"

# Clean up certificate files
rm -f app_cert.p12 installer_cert.p12
echo "🗑️ Certificate files cleaned up"

# Set partition list to allow codesign access
echo "🔓 Setting keychain partition list..."
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$TEMP_KEYCHAIN_PASSWORD" \
    "$TEMP_KEYCHAIN"

echo "🔍 Finding signing identities..."

# Find application signing identity
APP_SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$TEMP_KEYCHAIN" | \
    grep "Developer ID Application" | head -1 | \
    sed 's/.*"\(.*\)".*/\1/')

# Find installer signing identity  
INSTALLER_SIGNING_IDENTITY=$(security find-identity -v "$TEMP_KEYCHAIN" | \
    grep "Developer ID Installer" | head -1 | \
    sed 's/.*"\(.*\)".*/\1/')

if [ -z "$APP_SIGNING_IDENTITY" ]; then
    echo "❌ No Developer ID Application certificate found"
    echo "Available identities:"
    security find-identity -v -p codesigning "$TEMP_KEYCHAIN"
    exit 1
fi

if [ -z "$INSTALLER_SIGNING_IDENTITY" ]; then
    echo "❌ No Developer ID Installer certificate found"
    echo "Available identities:"
    security find-identity -v "$TEMP_KEYCHAIN"
    exit 1
fi

echo "✅ Application signing identity: $APP_SIGNING_IDENTITY"
echo "✅ Installer signing identity: $INSTALLER_SIGNING_IDENTITY"

# Export for other steps
{
    echo "APP_SIGNING_IDENTITY=$APP_SIGNING_IDENTITY"
    echo "INSTALLER_SIGNING_IDENTITY=$INSTALLER_SIGNING_IDENTITY"
    echo "TEMP_KEYCHAIN=$TEMP_KEYCHAIN"
    echo "TEMP_KEYCHAIN_PASSWORD=$TEMP_KEYCHAIN_PASSWORD"
    echo "APPLE_ID=$APPLE_ID"
    echo "APPLE_ID_PASSWORD=$APPLE_ID_PASSWORD"
    echo "APPLE_TEAM_ID=$APPLE_TEAM_ID"
} >> "${GITHUB_ENV:-/dev/null}"

# Also export for current script context
export APP_SIGNING_IDENTITY INSTALLER_SIGNING_IDENTITY
export TEMP_KEYCHAIN TEMP_KEYCHAIN_PASSWORD

echo ""
echo "✅ Certificate setup completed successfully"
echo "🔐 Ready for code signing and packaging"
