#!/bin/bash
# setup-local-certificates.sh - Import Apple Developer certificates for local builds
set -euo pipefail

echo "🔐 Setting up local Apple Developer certificates..."

# Check if app_config.json exists
if [ ! -f "apple_credentials/config/app_config.json" ]; then
    echo "❌ apple_credentials/config/app_config.json not found"
    exit 1
fi

# Load configuration
TEAM_ID=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['team_id'])")
P12_PATH=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['p12_path'])")
P12_PASSWORD=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['p12_password'])")

echo "Team ID: $TEAM_ID"
echo "P12 Path: $P12_PATH"

# Check if certificate files exist
APP_CERT_PATH="${P12_PATH}/app_cert.p12"
INSTALLER_CERT_PATH="${P12_PATH}/installer_cert.p12"

if [ ! -f "$APP_CERT_PATH" ]; then
    echo "❌ Application certificate not found: $APP_CERT_PATH"
    exit 1
fi

if [ ! -f "$INSTALLER_CERT_PATH" ]; then
    echo "❌ Installer certificate not found: $INSTALLER_CERT_PATH"
    exit 1
fi

echo "✅ Certificate files found"

# Create a temporary keychain for local development
TEMP_KEYCHAIN="r2midi-local-$(date +%s).keychain"
TEMP_KEYCHAIN_PASSWORD="temp_password_$(date +%s)_$(openssl rand -hex 8)"

echo "🔐 Creating temporary keychain: $TEMP_KEYCHAIN"

# Clean up any existing keychain with same pattern
security list-keychains -d user | grep "r2midi-local" | sed 's/"//g' | xargs -I {} security delete-keychain {} 2>/dev/null || true

# Create and configure new keychain
security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"  # 6 hour timeout
security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"

# Add to keychain search list
security list-keychains -d user -s "$TEMP_KEYCHAIN" $(security list-keychains -d user | sed s/\"//g)

echo "🔐 Importing certificates into keychain..."

# Import application certificate (for app signing)
echo "📜 Importing application certificate..."
security import "$APP_CERT_PATH" \
    -k "$TEMP_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/productbuild

if [ $? -ne 0 ]; then
    echo "❌ Failed to import application certificate"
    exit 1
fi

# Import installer certificate (for PKG signing)
echo "📜 Importing installer certificate..."
security import "$INSTALLER_CERT_PATH" \
    -k "$TEMP_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/productsign \
    -T /usr/bin/productbuild

if [ $? -ne 0 ]; then
    echo "❌ Failed to import installer certificate"
    exit 1
fi

# Set partition list to allow codesign access without prompts
echo "🔐 Configuring keychain access permissions..."
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$TEMP_KEYCHAIN_PASSWORD" \
    "$TEMP_KEYCHAIN"

echo "🔍 Verifying imported certificates..."

# Find and verify application signing identity
APP_SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$TEMP_KEYCHAIN" | \
    grep "Developer ID Application" | head -1 | \
    sed 's/.*"\(.*\)".*/\1/')

# Find and verify installer signing identity  
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

# Export environment variables for the build script
echo "📝 Saving environment variables for build process..."
cat > .local_build_env << EOF
export TEMP_KEYCHAIN="$TEMP_KEYCHAIN"
export TEMP_KEYCHAIN_PASSWORD="$TEMP_KEYCHAIN_PASSWORD"
export APP_SIGNING_IDENTITY="$APP_SIGNING_IDENTITY"
export INSTALLER_SIGNING_IDENTITY="$INSTALLER_SIGNING_IDENTITY"
export CERTIFICATES_IMPORTED="true"
EOF

echo "✅ Local certificate setup complete!"
echo ""
echo "📋 Summary:"
echo "   • Keychain: $TEMP_KEYCHAIN"
echo "   • App Identity: $APP_SIGNING_IDENTITY"
echo "   • Installer Identity: $INSTALLER_SIGNING_IDENTITY"
echo ""
echo "🚀 You can now run: ./build-all-local.sh"
echo ""
echo "🧹 To clean up later, run:"
echo "   security delete-keychain \"$TEMP_KEYCHAIN\""
echo "   rm -f .local_build_env"