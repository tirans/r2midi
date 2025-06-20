#!/bin/bash
set -euo pipefail

# Sign Apps with Native codesign (NOT Briefcase)
# Usage: sign-native-apps.sh

echo "🔐 Signing applications with native codesign (bypassing Briefcase)..."
echo "🚫 IMPORTANT: Not using Briefcase signing - using native macOS codesign"

# Create entitlements for notarization compatibility
echo "📝 Creating entitlements.plist..."
cat > entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
EOF

# Function to sign an app bundle with native codesign
sign_app_native() {
    local app_path="$1"
    local app_name=$(basename "$app_path")
    
    echo "🔐 Signing $app_name with native codesign..."
    
    # Remove any existing signatures
    find "$app_path" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
    
    echo "  📦 Signing nested components (inside-out approach)..."
    
    # Sign all dylibs first
    find "$app_path" -name "*.dylib" -type f | while read dylib; do
        echo "    🔗 Signing dylib: $(basename "$dylib")"
        codesign --force --sign "$APP_SIGNING_IDENTITY" \
            --options runtime --timestamp \
            "$dylib" 2>/dev/null || echo "    ⚠️ Warning: Failed to sign $(basename "$dylib")"
    done
    
    # Sign all frameworks (deepest first for nested frameworks)
    find "$app_path" -name "*.framework" -type d | sort -r | while read framework; do
        echo "    🔗 Signing framework: $(basename "$framework")"
        codesign --force --sign "$APP_SIGNING_IDENTITY" \
            --options runtime --timestamp \
            "$framework" 2>/dev/null || echo "    ⚠️ Warning: Failed to sign $(basename "$framework")"
    done
    
    # Sign any nested applications
    find "$app_path" -name "*.app" -not -path "$app_path" -type d | while read nested_app; do
        echo "    📱 Signing nested app: $(basename "$nested_app")"
        codesign --force --sign "$APP_SIGNING_IDENTITY" \
            --options runtime --timestamp \
            --entitlements entitlements.plist \
            "$nested_app" 2>/dev/null || echo "    ⚠️ Warning: Failed to sign $(basename "$nested_app")"
    done
    
    # Sign executables in Contents/MacOS
    if [ -d "$app_path/Contents/MacOS" ]; then
        find "$app_path/Contents/MacOS" -type f -perm +111 | while read executable; do
            if file "$executable" | grep -q "Mach-O"; then
                echo "    ⚡ Signing executable: $(basename "$executable")"
                codesign --force --sign "$APP_SIGNING_IDENTITY" \
                    --options runtime --timestamp \
                    "$executable" 2>/dev/null || echo "    ⚠️ Warning: Failed to sign $(basename "$executable")"
            fi
        done
    fi
    
    echo "  🎯 Signing main app bundle..."
    # Sign the main app bundle with entitlements
    codesign --force --sign "$APP_SIGNING_IDENTITY" \
        --options runtime --timestamp \
        --entitlements entitlements.plist \
        "$app_path"
    
    if [ $? -eq 0 ]; then
        echo "  ✅ Main app bundle signed successfully"
    else
        echo "  ❌ Failed to sign main app bundle"
        exit 1
    fi
    
    echo "  🔍 Verifying signature..."
    # Verify signature
    codesign --verify --deep --strict "$app_path"
    if [ $? -eq 0 ]; then
        echo "  ✅ Signature verification passed"
    else
        echo "  ❌ Signature verification failed"
        exit 1
    fi
    
    # Test with spctl (Gatekeeper)
    echo "  🔍 Testing Gatekeeper compatibility..."
    spctl --assess --type exec "$app_path" && echo "  ✅ Gatekeeper assessment passed" || echo "  ⚠️ Gatekeeper assessment failed (may pass after notarization)"
    
    echo "✅ $app_name signed and verified successfully"
}

# Verify required environment variables
if [ -z "${APP_SIGNING_IDENTITY:-}" ]; then
    echo "❌ APP_SIGNING_IDENTITY not set. Run setup-github-secrets-certificates.sh first"
    exit 1
fi

# Sign both applications with native codesign
if [ -d "build_native/server/dist/R2MIDI Server.app" ]; then
    sign_app_native "build_native/server/dist/R2MIDI Server.app"
else
    echo "⚠️ Warning: Server app not found at build_native/server/dist/R2MIDI Server.app"
fi

if [ -d "build_native/client/dist/R2MIDI Client.app" ]; then
    sign_app_native "build_native/client/dist/R2MIDI Client.app"
else
    echo "⚠️ Warning: Client app not found at build_native/client/dist/R2MIDI Client.app"
fi

echo "✅ Native app signing complete"
