#!/bin/bash

# create-pkg-installers.sh - Create signed PKG installers with native pkgbuild
# Usage: ./create-pkg-installers.sh [version]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}

echo "📦 Creating signed PKG installers with native pkgbuild..."
echo "🚫 IMPORTANT: Not using Briefcase - using native macOS pkgbuild"
echo "Version: $VERSION"

# Check required environment variables
if [ -z "${INSTALLER_SIGNING_IDENTITY:-}" ]; then
    echo "❌ INSTALLER_SIGNING_IDENTITY not set. Run setup-apple-certificates.sh first."
    exit 1
fi

echo "🔐 Using installer signing identity: $INSTALLER_SIGNING_IDENTITY"

# Create artifacts directory
mkdir -p artifacts

# Function to create PKG with native tools
create_pkg_native() {
    local app_path="$1"
    local app_name="$2"
    local bundle_id="$3"
    local pkg_name="$4"
    
    echo ""
    echo "📦 Creating PKG installer for $app_name..."
    
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
    
    # Create temporary directory structure for PKG contents
    local temp_dir=$(mktemp -d)
    local pkg_root="$temp_dir/pkg_root"
    local applications_dir="$pkg_root/Applications"
    mkdir -p "$applications_dir"
    
    echo "  📁 Copying app to PKG payload..."
    # Copy app to Applications directory in PKG
    if ! cp -R "$app_path" "$applications_dir/"; then
        echo "  ❌ Failed to copy app to PKG payload"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify copied app
    local copied_app="$applications_dir/$(basename "$app_path")"
    if [ ! -d "$copied_app" ]; then
        echo "  ❌ App not found in PKG payload after copy"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo "  📊 PKG payload size: $(du -sh "$pkg_root" | cut -f1)"
    
    echo "  🔨 Building PKG with native pkgbuild..."
    # Create the PKG with native pkgbuild
    if pkgbuild \
        --root "$pkg_root" \
        --install-location "/" \
        --identifier "$bundle_id.installer" \
        --version "$VERSION" \
        --timestamp \
        --sign "$INSTALLER_SIGNING_IDENTITY" \
        "artifacts/$pkg_name"; then
        echo "  ✅ PKG created successfully with native pkgbuild"
    else
        echo "  ❌ PKG creation failed"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    echo "  🔍 Verifying PKG signature..."
    # Verify PKG signature
    if pkgutil --check-signature "artifacts/$pkg_name"; then
        echo "  ✅ PKG signature verification passed"
    else
        echo "  ❌ PKG signature verification failed"
        return 1
    fi
    
    # Test PKG with spctl
    echo "  🔍 Testing PKG with Gatekeeper..."
    if spctl --assess --type install "artifacts/$pkg_name"; then
        echo "  ✅ PKG Gatekeeper test passed"
    else
        echo "  ⚠️ PKG Gatekeeper test failed (may pass after notarization)"
    fi
    
    echo "✅ PKG installer created and verified: $pkg_name"
    
    # Show PKG info
    local pkg_size=$(du -h "artifacts/$pkg_name" | cut -f1)
    echo "  📊 PKG size: $pkg_size"
    
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

# Create PKG installers
PKG_SUCCESS=true

echo ""
echo "📦 Creating PKG installers..."

# Create PKG for server
if ! create_pkg_native \
    "$SERVER_APP" \
    "R2MIDI Server" \
    "com.tirans.m2midi.r2midi.server" \
    "R2MIDI-Server-$VERSION.pkg"; then
    echo "❌ Failed to create server PKG"
    PKG_SUCCESS=false
fi

# Create PKG for client
if ! create_pkg_native \
    "$CLIENT_APP" \
    "R2MIDI Client" \
    "com.tirans.m2midi.r2midi.client" \
    "R2MIDI-Client-$VERSION.pkg"; then
    echo "❌ Failed to create client PKG"
    PKG_SUCCESS=false
fi

if [ "$PKG_SUCCESS" = "false" ]; then
    echo ""
    echo "❌ Some PKG installers failed to create"
    exit 1
fi

echo ""
echo "🎉 All PKG installers created successfully!"
echo "📦 Created packages:"
for pkg in artifacts/*.pkg; do
    if [ -f "$pkg" ]; then
        size=$(du -h "$pkg" | cut -f1)
        echo "  ✅ $(basename "$pkg") ($size)"
    fi
done

echo ""
echo "📋 PKG Creation Summary:"
echo "  Signing Identity: $INSTALLER_SIGNING_IDENTITY"
echo "  Version: $VERSION"
echo "  Install Location: /Applications"
echo "  Signed: Yes"
echo "  Ready for notarization: Yes"
