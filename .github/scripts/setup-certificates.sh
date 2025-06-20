#!/bin/bash
set -euo pipefail

# Setup certificates and keychain for macOS code signing
# Usage: setup-certificates.sh

echo "🔐 Setting up certificates and keychain..."

# Create a temporary keychain
echo "Step 1: Creating temporary keychain..."
TEMP_KEYCHAIN="build.keychain"
TEMP_KEYCHAIN_PASSWORD="temp_password_$(date +%s)"

# Check if keychain already exists and delete it
if security list-keychains -d user | grep -q "$TEMP_KEYCHAIN"; then
  echo "Removing existing keychain: $TEMP_KEYCHAIN"
  security delete-keychain "$TEMP_KEYCHAIN" || true
fi

# Create new keychain
echo "Creating new keychain: $TEMP_KEYCHAIN"
security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
if [ $? -ne 0 ]; then
  echo "❌ Failed to create keychain"
  exit 1
fi
echo "✅ Keychain created successfully"

# Configure keychain settings
echo "Step 2: Configuring keychain settings..."
security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"
if [ $? -ne 0 ]; then
  echo "❌ Failed to set keychain settings"
  exit 1
fi
echo "✅ Keychain settings configured"

# Unlock the keychain
echo "Step 3: Unlocking keychain..."
security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
if [ $? -ne 0 ]; then
  echo "❌ Failed to unlock keychain"
  exit 1
fi
echo "✅ Keychain unlocked"

# Add to keychain list
echo "Step 4: Adding keychain to search list..."
security list-keychains -d user -s "$TEMP_KEYCHAIN" $(security list-keychains -d user | sed s/\"//g)
if [ $? -ne 0 ]; then
  echo "❌ Failed to add keychain to search list"
  exit 1
fi
echo "✅ Keychain added to search list"

# Function to test P12 with legacy OpenSSL support
test_p12_certificate() {
    local cert_file="$1"
    local password="$2"

    # Try with -legacy flag first (OpenSSL 3.x)
    if openssl pkcs12 -legacy -in "$cert_file" -noout -passin pass:"$password" 2>/dev/null; then
        echo "✅ Certificate valid (using legacy provider)"
        return 0
    # Try without -legacy flag (older OpenSSL)
    elif openssl pkcs12 -in "$cert_file" -noout -passin pass:"$password" 2>/dev/null; then
        echo "✅ Certificate valid (standard provider)"
        return 0
    # Try with system OpenSSL
    elif [ -x "/usr/bin/openssl" ] && /usr/bin/openssl pkcs12 -in "$cert_file" -noout -passin pass:"$password" 2>/dev/null; then
        echo "✅ Certificate valid (system OpenSSL)"
        return 0
    else
        echo "❌ Certificate validation failed"
        return 1
    fi
}

# Check for certificate format - support GitHub secrets, combined P12, and local files
echo "Step 5: Checking certificate format..."

# Method 1: Local certificate files (for self-hosted runners)
if [ -f "apple_credentials/certificates/app_cert.p12" ] && [ -f "apple_credentials/certificates/installer_cert.p12" ] && [ -f "apple_credentials/config/app_config.json" ]; then
    echo "📜 Using local certificate files (self-hosted runner mode)"

    # Load credentials from app_config.json
    if command -v jq >/dev/null 2>&1; then
        LOCAL_CERT_PASSWORD=$(jq -r '.apple_developer.p12_password' apple_credentials/config/app_config.json)
    else
        # Fallback: extract password using grep and sed
        LOCAL_CERT_PASSWORD=$(grep -o '"p12_password"[[:space:]]*:[[:space:]]*"[^"]*"' apple_credentials/config/app_config.json | sed 's/.*"p12_password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi

    if [ -z "$LOCAL_CERT_PASSWORD" ] || [ "$LOCAL_CERT_PASSWORD" = "null" ]; then
        echo "❌ Error: Could not extract p12_password from app_config.json"
        exit 1
    fi

    echo "✅ Loaded certificate password from local config"

    # Copy local certificates to working directory
    echo "Step 6c: Using local certificate files..."
    cp "apple_credentials/certificates/app_cert.p12" "app_cert.p12"
    if [ $? -ne 0 ] || [ ! -s app_cert.p12 ]; then
        echo "❌ Failed to copy local application certificate"
        exit 1
    fi
    echo "✅ Local application certificate ready"

    cp "apple_credentials/certificates/installer_cert.p12" "installer_cert.p12"
    if [ $? -ne 0 ] || [ ! -s installer_cert.p12 ]; then
        echo "❌ Failed to copy local installer certificate"
        rm -f app_cert.p12
        exit 1
    fi
    echo "✅ Local installer certificate ready"

    # Validate P12 files with OpenSSL 3.x compatibility
    echo "Validating local application certificate..."
    if ! test_p12_certificate "app_cert.p12" "$LOCAL_CERT_PASSWORD"; then
        echo "❌ Error: Invalid local application certificate or password"
        echo "🔍 Checking OpenSSL version: $(openssl version)"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi

    echo "Validating local installer certificate..."
    if ! test_p12_certificate "installer_cert.p12" "$LOCAL_CERT_PASSWORD"; then
        echo "❌ Error: Invalid local installer certificate or password"
        echo "🔍 Checking OpenSSL version: $(openssl version)"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi

    # Import certificates
    echo "Step 7c: Importing local application certificate..."
    security import app_cert.p12 -k "$TEMP_KEYCHAIN" -P "$LOCAL_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild
    if [ $? -ne 0 ]; then
        echo "❌ Failed to import local application certificate"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi
    echo "✅ Local application certificate imported"

    echo "Step 8c: Importing local installer certificate..."
    security import installer_cert.p12 -k "$TEMP_KEYCHAIN" -P "$LOCAL_CERT_PASSWORD" -T /usr/bin/productsign -T /usr/bin/productbuild
    if [ $? -ne 0 ]; then
        echo "❌ Failed to import local installer certificate"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi
    echo "✅ Local installer certificate imported"

    # Clean up certificate files
    rm -f app_cert.p12 installer_cert.p12

# Method 2: Individual application and installer certificates (GitHub secrets)
elif [ -n "${APPLE_DEVELOPER_ID_APPLICATION_CERT:-}" ] && [ -n "${APPLE_DEVELOPER_ID_INSTALLER_CERT:-}" ]; then
    echo "📜 Using separate application and installer certificates"

    # Validate environment variables
    if [ -z "${APPLE_CERT_PASSWORD:-}" ]; then
        echo "❌ Error: APPLE_CERT_PASSWORD is required for certificate import"
        exit 1
    fi

    # Decode and save certificates
    echo "Step 6a: Decoding separate certificates..."
    echo "$APPLE_DEVELOPER_ID_APPLICATION_CERT" | base64 --decode > app_cert.p12
    if [ $? -ne 0 ] || [ ! -s app_cert.p12 ]; then
        echo "❌ Failed to decode application certificate"
        exit 1
    fi
    echo "✅ Application certificate decoded"

    echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > installer_cert.p12
    if [ $? -ne 0 ] || [ ! -s installer_cert.p12 ]; then
        echo "❌ Failed to decode installer certificate"
        rm -f app_cert.p12
        exit 1
    fi
    echo "✅ Installer certificate decoded"

    # Validate P12 files with OpenSSL 3.x compatibility
    echo "Validating application certificate..."
    if ! test_p12_certificate "app_cert.p12" "$APPLE_CERT_PASSWORD"; then
        echo "❌ Error: Invalid application certificate or password"
        echo "🔍 Checking OpenSSL version: $(openssl version)"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi

    echo "Validating installer certificate..."
    if ! test_p12_certificate "installer_cert.p12" "$APPLE_CERT_PASSWORD"; then
        echo "❌ Error: Invalid installer certificate or password"
        echo "🔍 Checking OpenSSL version: $(openssl version)"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi

    # Import certificates
    echo "Step 7a: Importing application certificate..."
    security import app_cert.p12 -k "$TEMP_KEYCHAIN" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild
    if [ $? -ne 0 ]; then
        echo "❌ Failed to import application certificate"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi
    echo "✅ Application certificate imported"

    echo "Step 8a: Importing installer certificate..."
    security import installer_cert.p12 -k "$TEMP_KEYCHAIN" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/productsign -T /usr/bin/productbuild
    if [ $? -ne 0 ]; then
        echo "❌ Failed to import installer certificate"
        rm -f app_cert.p12 installer_cert.p12
        exit 1
    fi
    echo "✅ Installer certificate imported"

    # Clean up certificate files
    rm -f app_cert.p12 installer_cert.p12

# Method 2: Single P12 certificate (GitHub workflow format)
elif [ -n "${APPLE_CERTIFICATE_P12:-}" ]; then
    echo "📜 Using combined P12 certificate from GitHub workflow"

    # Validate environment variables
    if [ -z "${APPLE_CERTIFICATE_PASSWORD:-}" ]; then
        echo "❌ Error: APPLE_CERTIFICATE_PASSWORD is required for certificate import"
        exit 1
    fi

    # Decode and save certificate
    echo "Step 6b: Decoding combined certificate..."
    echo "$APPLE_CERTIFICATE_P12" | base64 --decode > combined_cert.p12
    if [ $? -ne 0 ] || [ ! -s combined_cert.p12 ]; then
        echo "❌ Failed to decode combined certificate"
        exit 1
    fi
    echo "✅ Combined certificate decoded"

    # Validate P12 file with OpenSSL 3.x compatibility
    echo "Validating combined certificate..."
    if ! test_p12_certificate "combined_cert.p12" "$APPLE_CERTIFICATE_PASSWORD"; then
        echo "❌ Error: Invalid combined certificate or password"
        echo "🔍 Checking OpenSSL version: $(openssl version)"
        rm -f combined_cert.p12
        exit 1
    fi

    # Import certificate
    echo "Step 7b: Importing combined certificate..."
    security import combined_cert.p12 -k "$TEMP_KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productsign -T /usr/bin/productbuild
    if [ $? -ne 0 ]; then
        echo "❌ Failed to import combined certificate"
        rm -f combined_cert.p12
        exit 1
    fi
    echo "✅ Combined certificate imported"

    # Clean up certificate file
    rm -f combined_cert.p12

else
    echo "❌ Error: No certificates found"
    echo "Required: Either APPLE_DEVELOPER_ID_APPLICATION_CERT + APPLE_DEVELOPER_ID_INSTALLER_CERT"
    echo "       OR APPLE_CERTIFICATE_P12 (GitHub workflow format)"
    exit 1
fi

# Set partition list to allow codesign to access the keys
echo "Step 9: Setting key partition list..."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
if [ $? -ne 0 ]; then
    echo "❌ Failed to set key partition list"
    exit 1
fi
echo "✅ Key partition list set"

# Verify setup
echo "Step 10: Verifying certificate setup..."
echo "Available signing identities:"
security find-identity -v -p codesigning "$TEMP_KEYCHAIN"
echo "Available installer identities:"
security find-identity -v "$TEMP_KEYCHAIN" | grep "Developer ID Installer" || echo "No installer certificates found"

# Check for required certificates
if security find-identity -v -p codesigning "$TEMP_KEYCHAIN" | grep -q "Developer ID Application"; then
    echo "✅ Application signing certificate found"
    APPLICATION_IDENTITY=$(security find-identity -v -p codesigning "$TEMP_KEYCHAIN" | grep "Developer ID Application" | head -1 | cut -d'"' -f2)
    echo "Application Identity: $APPLICATION_IDENTITY"
else
    echo "❌ Application signing certificate not found in keychain"
    exit 1
fi

# Installer certificate is optional but recommended - search in all identities
if security find-identity -v "$TEMP_KEYCHAIN" | grep -q "Developer ID Installer"; then
    echo "✅ Installer signing certificate found"
    INSTALLER_IDENTITY=$(security find-identity -v "$TEMP_KEYCHAIN" | grep "Developer ID Installer" | head -1 | cut -d'"' -f2)
    echo "Installer Identity: $INSTALLER_IDENTITY"
elif security find-identity -v "$TEMP_KEYCHAIN" | grep -q "3rd Party Mac Developer Installer"; then
    echo "⚠️ Warning: Found '3rd Party Mac Developer Installer' certificate"
    echo "This certificate is for Mac App Store distribution, not outside distribution."
    echo "For PKG installers distributed outside the App Store, you need 'Developer ID Installer' certificate."
    echo ""
    echo "📝 Certificate Types:"
    echo "  - '3rd Party Mac Developer Installer' = Mac App Store distribution"
    echo "  - 'Developer ID Installer' = Outside App Store distribution (what you need)"
    echo ""
    echo "PKG creation will be skipped. DMG fallback will be used."
else
    echo "⚠️ Warning: No installer signing certificate found"
    echo "Neither 'Developer ID Installer' nor 'Mac App Store' certificates found."
    echo "PKG creation will be skipped. DMG fallback will be used."
fi

# Export identities for use by other scripts
echo "export APPLICATION_SIGNING_IDENTITY=\"$APPLICATION_IDENTITY\"" > /tmp/signing_identities.sh
if [ -n "${INSTALLER_IDENTITY:-}" ]; then
    echo "export INSTALLER_SIGNING_IDENTITY=\"$INSTALLER_IDENTITY\"" >> /tmp/signing_identities.sh
fi
echo "export TEMP_KEYCHAIN=\"$TEMP_KEYCHAIN\"" >> /tmp/signing_identities.sh
echo "export TEMP_KEYCHAIN_PASSWORD=\"$TEMP_KEYCHAIN_PASSWORD\"" >> /tmp/signing_identities.sh

echo "✅ Certificates and keychain setup complete!"
