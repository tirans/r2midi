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
CONFIG_FILE="${CONFIG_FILE:-apple_credentials/config/app_config.json}"
TEAM_ID=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['apple_developer']['team_id'])")
P12_PATH=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['apple_developer']['p12_path'])")
P12_PASSWORD=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['apple_developer']['p12_password'])")
APP_STORE_P12_PASSWORD=$(python3 -c "import json; config = json.load(open('$CONFIG_FILE')); print(config['apple_developer'].get('app_store_p12_password', config['apple_developer']['p12_password']))")

echo "Team ID: $TEAM_ID"
echo "P12 Path: $P12_PATH"

# Check if certificate files exist
DEVELOPER_ID_APP_CERT_PATH="${P12_PATH}/app_cert.p12"
DEVELOPER_ID_INSTALLER_CERT_PATH="${P12_PATH}/installer_cert.p12"
APP_STORE_CERT_PATH="${P12_PATH}/app_store_cert.p12"

# Check for Developer ID certificates (required for "indi" distribution)
if [ ! -f "$DEVELOPER_ID_APP_CERT_PATH" ]; then
    echo "❌ Developer ID Application certificate not found: $DEVELOPER_ID_APP_CERT_PATH"
    exit 1
fi

if [ ! -f "$DEVELOPER_ID_INSTALLER_CERT_PATH" ]; then
    echo "❌ Developer ID Installer certificate not found: $DEVELOPER_ID_INSTALLER_CERT_PATH"
    exit 1
fi

# Check for App Store certificate (optional for App Store distribution)
APP_STORE_CERT_AVAILABLE=false
if [ -f "$APP_STORE_CERT_PATH" ]; then
    APP_STORE_CERT_AVAILABLE=true
    echo "✅ App Store certificate found: $APP_STORE_CERT_PATH"
else
    echo "⚠️ App Store certificate not found: $APP_STORE_CERT_PATH (App Store builds will be skipped)"
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

# Import Developer ID application certificate (for app signing)
echo "📜 Importing Developer ID application certificate..."
security import "$DEVELOPER_ID_APP_CERT_PATH" \
    -k "$TEMP_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/productbuild

if [ $? -ne 0 ]; then
    echo "❌ Failed to import Developer ID application certificate"
    exit 1
fi

# Import Developer ID installer certificate (for PKG signing)
echo "📜 Importing Developer ID installer certificate..."
security import "$DEVELOPER_ID_INSTALLER_CERT_PATH" \
    -k "$TEMP_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/productsign \
    -T /usr/bin/productbuild

if [ $? -ne 0 ]; then
    echo "❌ Failed to import Developer ID installer certificate"
    exit 1
fi

# Import App Store certificate if available
if [ "$APP_STORE_CERT_AVAILABLE" = "true" ]; then
    echo "📜 Importing App Store certificate..."
    security import "$APP_STORE_CERT_PATH" \
        -k "$TEMP_KEYCHAIN" \
        -P "$APP_STORE_P12_PASSWORD" \
        -T /usr/bin/codesign \
        -T /usr/bin/productbuild \
        -T /usr/bin/productsign

    if [ $? -ne 0 ]; then
        echo "❌ Failed to import App Store certificate"
        exit 1
    fi
fi

# Set partition list to allow codesign access without prompts
echo "🔐 Configuring keychain access permissions..."
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$TEMP_KEYCHAIN_PASSWORD" \
    "$TEMP_KEYCHAIN"

echo "🔍 Verifying imported certificates..."

# Find and verify Developer ID application signing identity
DEVELOPER_ID_APP_SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$TEMP_KEYCHAIN" | \
    grep "Developer ID Application" | head -1 | \
    sed 's/.*"\(.*\)".*/\1/')

# Find and verify Developer ID installer signing identity  
DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY=$(security find-identity -v "$TEMP_KEYCHAIN" | \
    grep "Developer ID Installer" | head -1 | \
    sed 's/.*"\(.*\)".*/\1/')

# Find App Store signing identity if certificate was imported
APP_STORE_SIGNING_IDENTITY=""
if [ "$APP_STORE_CERT_AVAILABLE" = "true" ]; then
    APP_STORE_SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$TEMP_KEYCHAIN" | \
        grep -E "(3rd Party Mac Developer Application|Apple Distribution)" | head -1 | \
        sed 's/.*"\(.*\)".*/\1/')
fi

if [ -z "$DEVELOPER_ID_APP_SIGNING_IDENTITY" ]; then
    echo "❌ No Developer ID Application certificate found"
    echo "Available identities:"
    security find-identity -v -p codesigning "$TEMP_KEYCHAIN"
    exit 1
fi

if [ -z "$DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY" ]; then
    echo "❌ No Developer ID Installer certificate found"
    echo "Available identities:"
    security find-identity -v "$TEMP_KEYCHAIN"
    exit 1
fi

echo "✅ Developer ID Application signing identity: $DEVELOPER_ID_APP_SIGNING_IDENTITY"
echo "✅ Developer ID Installer signing identity: $DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY"

if [ -n "$APP_STORE_SIGNING_IDENTITY" ]; then
    echo "✅ App Store signing identity: $APP_STORE_SIGNING_IDENTITY"
else
    echo "⚠️ App Store signing identity not found (App Store builds will be skipped)"
fi

# Export environment variables for the build script
echo "📝 Saving environment variables for build process..."
cat > .local_build_env << EOF
export TEMP_KEYCHAIN="$TEMP_KEYCHAIN"
export TEMP_KEYCHAIN_PASSWORD="$TEMP_KEYCHAIN_PASSWORD"
export DEVELOPER_ID_APP_SIGNING_IDENTITY="$DEVELOPER_ID_APP_SIGNING_IDENTITY"
export DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY="$DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY"
export APP_STORE_SIGNING_IDENTITY="$APP_STORE_SIGNING_IDENTITY"
export APP_STORE_CERT_AVAILABLE="$APP_STORE_CERT_AVAILABLE"
export CERTIFICATES_IMPORTED="true"
# Backward compatibility
export APP_SIGNING_IDENTITY="$DEVELOPER_ID_APP_SIGNING_IDENTITY"
export INSTALLER_SIGNING_IDENTITY="$DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY"
EOF

echo "✅ Local certificate setup complete!"
echo ""
echo "📋 Summary:"
echo "   • Keychain: $TEMP_KEYCHAIN"
echo "   • Developer ID App Identity: $DEVELOPER_ID_APP_SIGNING_IDENTITY"
echo "   • Developer ID Installer Identity: $DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY"
if [ -n "$APP_STORE_SIGNING_IDENTITY" ]; then
    echo "   • App Store Identity: $APP_STORE_SIGNING_IDENTITY"
else
    echo "   • App Store Identity: Not available"
fi
echo ""
echo "🚀 You can now run: ./build-all-local.sh"
echo "   This will create both 'indi' distribution (Developer ID) and App Store signed packages"
echo ""
echo "🧹 To clean up later, run:"
echo "   security delete-keychain \"$TEMP_KEYCHAIN\""
echo "   rm -f .local_build_env"
