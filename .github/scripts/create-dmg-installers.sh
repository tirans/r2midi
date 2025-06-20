#!/bin/bash

# create-dmg-installers.sh - Create signed DMG installers with native hdiutil
# Usage: ./create-dmg-installers.sh [version]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}

echo "💽 Creating signed DMG installers with native hdiutil..."
echo "🚫 IMPORTANT: Not using Briefcase - using native macOS hdiutil"
echo "Version: $VERSION"

# Check required environment variables
if [ -z "${APP_SIGNING_IDENTITY:-}" ]; then
    echo "❌ APP_SIGNING_IDENTITY not set. Run setup-apple-certificates.sh first."
    exit 1
fi

echo "🔐 Using signing identity: $APP_SIGNING_IDENTITY"

# Ensure artifacts directory exists
mkdir -p artifacts

# Function to create DMG
create_dmg_native() {
    local app_path="$1"
    local app_name="$2"
    local dmg_name="$3"
    
    echo ""
    echo "💽 Creating DMG installer for $app_name..."
    
    # Verify app exists and is signed
    if [ ! -d "$app_path" ]; then
        echo "❌ App not found: $app_path"
        return 1
    fi
    
    echo "  🔍 Verifying app signature..."
    if ! codesign --verify --deep --strict "$app_path"; then
        echo "  ❌ App is not properly signed"
        return 1
    fi
    echo "  ✅ App signature verified"
    
    # Create temporary directory for DMG contents
    local temp_dir=$(mktemp -d)
    local dmg_contents="$temp_dir/dmg_contents"
    mkdir -p "$dmg_contents"
    
    echo "  📁 Preparing DMG contents..."
    # Copy app to DMG contents
    if ! cp -R "$app_path" "$dmg_contents/"; then
        echo "  ❌ Failed to copy app to DMG contents"
        rm -rf "$temp_dir"
        return 1
    fi
    
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
    
    # Create a README file
    cat > "$dmg_contents/README.txt" << EOF
R2MIDI - Real-time MIDI Processing
==================================

Version: $VERSION
Application: $app_name

This installer contains a signed and notarized macOS application.

Installation:
1. Drag the application to the Applications folder
2. The first launch may take a moment for macOS to verify the app
3. No security warnings should appear

System Requirements:
- macOS 11.0 (Big Sur) or later
- 512MB RAM minimum
- 200MB disk space

For more information, documentation, and support:
https://github.com/tirans/r2midi

© 2024 R2MIDI Project
EOF
    
    echo "  📊 DMG contents size: $(du -sh "$dmg_contents" | cut -f1)"
    echo "  📁 DMG contents:"
    ls -la "$dmg_contents"
    
    echo "  🔨 Creating DMG with native hdiutil..."
    # Create the DMG with better compression and settings
    if hdiutil create \
        -format UDZO \
        -srcfolder "$dmg_contents" \
        -volname "$app_name $VERSION" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        "artifacts/$dmg_name"; then
        echo "  ✅ DMG created successfully with native hdiutil"
    else
        echo "  ❌ DMG creation failed"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    echo "  🔐 Signing DMG with native codesign..."
    # Sign the DMG
    if codesign --force --sign "$APP_SIGNING_IDENTITY" --timestamp "artifacts/$dmg_name"; then
        echo "  ✅ DMG signed successfully"
    else
        echo "  ❌ DMG signing failed"
        return 1
    fi
    
    echo "  🔍 Verifying DMG signature..."
    if codesign --verify --verbose "artifacts/$dmg_name"; then
        echo "  ✅ DMG signature verification passed"
    else
        echo "  ❌ DMG signature verification failed"
        return 1
    fi
    
    echo "✅ DMG installer created and signed: $dmg_name"
    
    # Show DMG info
    local dmg_size=$(du -h "artifacts/$dmg_name" | cut -f1)
    echo "  📊 DMG size: $dmg_size"
    
    # Test mounting the DMG
    echo "  🔍 Testing DMG mount..."
    local mount_point=$(mktemp -d)
    if hdiutil attach "artifacts/$dmg_name" -mountpoint "$mount_point" -quiet; then
        echo "  ✅ DMG mounts successfully"
        echo "  📁 Mounted contents:"
        ls -la "$mount_point"
        hdiutil detach "$mount_point" -quiet
        rmdir "$mount_point"
    else
        echo "  ⚠️ DMG mount test failed"
        rmdir "$mount_point"
    fi
    
    return 0
}

# Check for signed applications
echo "🔍 Checking for signed applications..."

SERVER_APP="build_native/server/dist/R2MIDI Server.app"
CLIENT_APP="build_native/client/dist/R2MIDI Client.app"

if [ ! -d "$SERVER_APP" ]; then
    echo "❌ Server app not found: $SERVER_APP"
    exit 1
fi

if [ ! -d "$CLIENT_APP" ]; then
    echo "❌ Client app not found: $CLIENT_APP"
    exit 1
fi

echo "✅ Found both signed applications"

# Create DMG installers
DMG_SUCCESS=true

echo ""
echo "💽 Creating DMG installers..."

# Create DMG for server
if ! create_dmg_native \
    "$SERVER_APP" \
    "R2MIDI Server" \
    "R2MIDI-Server-$VERSION.dmg"; then
    echo "❌ Failed to create server DMG"
    DMG_SUCCESS=false
fi

# Create DMG for client
if ! create_dmg_native \
    "$CLIENT_APP" \
    "R2MIDI Client" \
    "R2MIDI-Client-$VERSION.dmg"; then
    echo "❌ Failed to create client DMG"
    DMG_SUCCESS=false
fi

if [ "$DMG_SUCCESS" = "false" ]; then
    echo ""
    echo "❌ Some DMG installers failed to create"
    exit 1
fi

echo ""
echo "🎉 All DMG installers created successfully!"
echo "💽 Created disk images:"
for dmg in artifacts/*.dmg; do
    if [ -f "$dmg" ]; then
        size=$(du -h "$dmg" | cut -f1)
        echo "  ✅ $(basename "$dmg") ($size)"
    fi
done

echo ""
echo "📋 DMG Creation Summary:"
echo "  Signing Identity: $APP_SIGNING_IDENTITY"
echo "  Version: $VERSION"
echo "  Format: UDZO (compressed)"
echo "  File System: HFS+"
echo "  Signed: Yes"
echo "  Ready for notarization: Yes"
echo ""
echo "💡 Installation Instructions:"
echo "  1. Double-click DMG to mount"
echo "  2. Drag app to Applications folder"
echo "  3. Eject DMG when done"
