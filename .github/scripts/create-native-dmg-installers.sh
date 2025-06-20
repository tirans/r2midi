#!/bin/bash
set -euo pipefail

# Create Signed DMG Installers with native hdiutil
# Usage: create-native-dmg-installers.sh [version]

VERSION="${1:-${APP_VERSION:-1.0.0}}"

echo "💽 Creating signed DMG installers with native hdiutil..."
echo "🚫 IMPORTANT: Not using Briefcase - using native macOS hdiutil"

mkdir -p artifacts

# Function to create DMG
create_dmg_native() {
    local app_path="$1"
    local app_name="$2"
    local dmg_name="$3"
    
    echo "💽 Creating DMG installer for $app_name..."
    
    # Create temporary directory for DMG contents
    local temp_dir=$(mktemp -d)
    local dmg_contents="$temp_dir/dmg_contents"
    mkdir -p "$dmg_contents"
    
    echo "  📁 Preparing DMG contents..."
    # Copy app to DMG contents
    cp -R "$app_path" "$dmg_contents/"
    
    # Create Applications symlink for easy installation
    ln -s /Applications "$dmg_contents/Applications"
    
    # Create installation instructions
    cat > "$dmg_contents/Install Instructions.txt" << EOF
$app_name Installation
=====================

1. Drag $app_name to the Applications folder
2. Launch from Applications folder
3. The app is signed and notarized - no security warnings

For support, visit: https://github.com/tirans/r2midi
EOF
    
    echo "  🔨 Creating DMG with native hdiutil..."
    # Create the DMG with better compression and settings
    hdiutil create \
        -format UDZO \
        -srcfolder "$dmg_contents" \
        -volname "$app_name $VERSION" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        "artifacts/$dmg_name"
    
    if [ $? -eq 0 ]; then
        echo "  ✅ DMG created successfully with native hdiutil"
    else
        echo "  ❌ DMG creation failed"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    echo "  🔐 Signing DMG with native codesign..."
    # Sign the DMG
    codesign --force --sign "$APP_SIGNING_IDENTITY" --timestamp "artifacts/$dmg_name"
    if [ $? -eq 0 ]; then
        echo "  ✅ DMG signed successfully"
    else
        echo "  ❌ DMG signing failed"
        exit 1
    fi
    
    echo "✅ DMG installer created and signed: $dmg_name"
    
    # Show DMG info
    local dmg_size=$(du -h "artifacts/$dmg_name" | cut -f1)
    echo "  📊 DMG size: $dmg_size"
}

# Verify required environment variables
if [ -z "${APP_SIGNING_IDENTITY:-}" ]; then
    echo "❌ APP_SIGNING_IDENTITY not set. Run setup-github-secrets-certificates.sh first"
    exit 1
fi

# Create DMG for server
if [ -d "build_native/server/dist/R2MIDI Server.app" ]; then
    create_dmg_native \
        "build_native/server/dist/R2MIDI Server.app" \
        "R2MIDI Server" \
        "R2MIDI-Server-$VERSION.dmg"
else
    echo "⚠️ Warning: Server app not found, skipping DMG creation"
fi

# Create DMG for client
if [ -d "build_native/client/dist/R2MIDI Client.app" ]; then
    create_dmg_native \
        "build_native/client/dist/R2MIDI Client.app" \
        "R2MIDI Client" \
        "R2MIDI-Client-$VERSION.dmg"
else
    echo "⚠️ Warning: Client app not found, skipping DMG creation"
fi

echo "✅ DMG installer creation complete"
