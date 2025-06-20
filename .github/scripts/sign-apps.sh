#!/bin/bash

# sign-apps.sh - Sign apps with native codesign
# Usage: ./sign-apps.sh

set -euo pipefail

echo "🔐 Signing applications with native codesign (bypassing Briefcase)..."
echo "🚫 IMPORTANT: Not using Briefcase signing - using native macOS codesign"

# Check required environment variables
if [ -z "${APP_SIGNING_IDENTITY:-}" ]; then
    echo "❌ APP_SIGNING_IDENTITY not set. Run setup-apple-certificates.sh first."
    exit 1
fi

echo "🔐 Using signing identity: $APP_SIGNING_IDENTITY"

# Create entitlements for notarization compatibility
echo "📜 Creating entitlements file..."
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

echo "✅ Entitlements file created"

# Function to sign an app bundle with native codesign
sign_app_native() {
    local app_path="$1"
    local app_name=$(basename "$app_path")
    
    echo ""
    echo "🔐 Signing $app_name with native codesign..."
    
    # Verify app exists
    if [ ! -d "$app_path" ]; then
        echo "❌ App not found: $app_path"
        return 1
    fi
    
    # Remove any existing signatures
    echo "  🧹 Removing existing signatures..."
    find "$app_path" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
    
    echo "  📦 Signing nested components (inside-out approach)..."
    
    # Sign all dylibs first
    echo "    🔗 Signing dynamic libraries..."
    find "$app_path" -name "*.dylib" -type f | while read dylib; do
        echo "      Signing dylib: $(basename "$dylib")"
        codesign --force --sign "$APP_SIGNING_IDENTITY" \
          --options runtime --timestamp \
          "$dylib" 2>/dev/null || echo "      ⚠️ Warning: Failed to sign $(basename "$dylib")"
    done
    
    # Sign all frameworks (deepest first for nested frameworks)
    echo "    📚 Signing frameworks..."
    find "$app_path" -name "*.framework" -type d | sort -r | while read framework; do
        echo "      Signing framework: $(basename "$framework")"
        codesign --force --sign "$APP_SIGNING_IDENTITY" \
          --options runtime --timestamp \
          "$framework" 2>/dev/null || echo "      ⚠️ Warning: Failed to sign $(basename "$framework")"
    done
    
    # Sign any nested applications
    echo "    📱 Checking for nested applications..."
    find "$app_path" -name "*.app" -not -path "$app_path" -type d | while read nested_app; do
        echo "      Signing nested app: $(basename "$nested_app")"
        codesign --force --sign "$APP_SIGNING_IDENTITY" \
          --options runtime --timestamp \
          --entitlements entitlements.plist \
          "$nested_app" 2>/dev/null || echo "      ⚠️ Warning: Failed to sign $(basename "$nested_app")"
    done
    
    # Sign executables in Contents/MacOS
    if [ -d "$app_path/Contents/MacOS" ]; then
        echo "    ⚡ Signing executables..."
        find "$app_path/Contents/MacOS" -type f -perm +111 | while read executable; do
            if file "$executable" | grep -q "Mach-O"; then
                echo "      Signing executable: $(basename "$executable")"
                codesign --force --sign "$APP_SIGNING_IDENTITY" \
                  --options runtime --timestamp \
                  "$executable" 2>/dev/null || echo "      ⚠️ Warning: Failed to sign $(basename "$executable")"
            fi
        done
    fi
    
    echo "  🎯 Signing main app bundle..."
    # Sign the main app bundle with entitlements
    if codesign --force --sign "$APP_SIGNING_IDENTITY" \
        --options runtime --timestamp \
        --entitlements entitlements.plist \
        "$app_path"; then
        echo "  ✅ Main app bundle signed successfully"
    else
        echo "  ❌ Failed to sign main app bundle"
        return 1
    fi
    
    echo "  🔍 Verifying signature..."
    # Verify signature
    if codesign --verify --deep --strict "$app_path"; then
        echo "  ✅ Signature verification passed"
    else
        echo "  ❌ Signature verification failed"
        return 1
    fi
    
    # Test with spctl (Gatekeeper)
    echo "  🔍 Testing Gatekeeper compatibility..."
    if spctl --assess --type exec "$app_path"; then
        echo "  ✅ Gatekeeper assessment passed"
    else
        echo "  ⚠️ Gatekeeper assessment failed (may pass after notarization)"
    fi
    
    echo "✅ $app_name signed and verified successfully"
    return 0
}

# Check for built applications
echo "🔍 Looking for built applications..."

SERVER_APP="build_native/server/dist/R2MIDI Server.app"
CLIENT_APP="build_native/client/dist/R2MIDI Client.app"

if [ ! -d "$SERVER_APP" ]; then
    echo "❌ Server app not found: $SERVER_APP"
    echo "📁 Available files in build_native/server/dist/:"
    ls -la build_native/server/dist/ 2>/dev/null || echo "Directory not found"
    exit 1
fi

if [ ! -d "$CLIENT_APP" ]; then
    echo "❌ Client app not found: $CLIENT_APP"
    echo "📁 Available files in build_native/client/dist/:"
    ls -la build_native/client/dist/ 2>/dev/null || echo "Directory not found"
    exit 1
fi

echo "✅ Found both applications"

# Sign both applications with native codesign
SIGNING_SUCCESS=true

if ! sign_app_native "$SERVER_APP"; then
    echo "❌ Failed to sign server app"
    SIGNING_SUCCESS=false
fi

if ! sign_app_native "$CLIENT_APP"; then
    echo "❌ Failed to sign client app"
    SIGNING_SUCCESS=false
fi

if [ "$SIGNING_SUCCESS" = "false" ]; then
    echo ""
    echo "❌ Some applications failed to sign"
    exit 1
fi

echo ""
echo "🎉 All applications signed successfully!"
echo "✅ Server app: $SERVER_APP"
echo "✅ Client app: $CLIENT_APP"
echo ""
echo "📋 Signing summary:"
echo "  Identity: $APP_SIGNING_IDENTITY"
echo "  Hardened runtime: Enabled"
echo "  Entitlements: Network, file access, audio input"
echo "  Ready for notarization: Yes"
