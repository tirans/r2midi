#!/bin/bash
# setup-notarization-api.sh - Configure App Store Connect API for notarization
set -euo pipefail

echo "🔐 Setting up App Store Connect API for notarization..."

# Check if we have App Store Connect API credentials
if [ -n "${APP_STORE_CONNECT_API_KEY:-}" ] && [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] && [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
    echo "✅ App Store Connect API credentials found"
    
    # Create API key directory
    API_KEY_DIR="$HOME/.appstoreconnect/private_keys"
    mkdir -p "$API_KEY_DIR"
    
    # Save the API key
    API_KEY_FILE="$API_KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
    echo "$APP_STORE_CONNECT_API_KEY" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    
    echo "✅ API key saved to: $API_KEY_FILE"
    
    # Create notarytool store profile
    echo "📝 Creating notarytool store profile..."
    
    xcrun notarytool store-credentials "r2midi-ci" \
        --key "$API_KEY_FILE" \
        --key-id "$APP_STORE_CONNECT_KEY_ID" \
        --issuer "$APP_STORE_CONNECT_ISSUER_ID"
    
    if [ $? -eq 0 ]; then
        echo "✅ Store profile 'r2midi-ci' created successfully"
        
        # Export environment variable to use this profile
        export NOTARIZATION_PROFILE="r2midi-ci"
        echo "export NOTARIZATION_PROFILE='r2midi-ci'" >> .local_build_env
        
        # Verify the profile
        echo "🔍 Verifying store profile..."
        xcrun notarytool history --keychain-profile "r2midi-ci" --limit 1 2>&1 || echo "No previous submissions"
        
        return 0
    else
        echo "❌ Failed to create store profile"
        return 1
    fi
else
    echo "⚠️ App Store Connect API credentials not found"
    echo "   Will fall back to Apple ID authentication for notarization"
    return 0
fi
