#!/bin/bash
set -euo pipefail

# Create Signed PKG Installers with Native pkgbuild
# Usage: create-native-pkg-installers.sh [version]

VERSION="${1:-${APP_VERSION:-1.0.0}}"

echo "📦 Creating signed PKG installers with native pkgbuild..."
echo "🚫 IMPORTANT: Not using Briefcase - using native macOS pkgbuild"

mkdir -p artifacts

# Function to create PKG with native tools
create_pkg_native() {
    local app_path="$1"
    local app_name="$2"
    local bundle_id="$3"
    local pkg_name="$4"
    
    echo "📦 Creating PKG installer for $app_name..."
    
    # Create temporary directory structure for PKG contents
    local temp_dir=$(mktemp -d)
    local pkg_root="$temp_dir/pkg_root"
    local applications_dir="$pkg_root/Applications"
    mkdir -p "$applications_dir"
    
    echo "  📁 Copying app to PKG payload..."
    # Copy app to Applications directory in PKG
    cp -R "$app_path" "$applications_dir/"
    
    echo "  🔨 Building PKG with native pkgbuild..."
    # Create the PKG with native pkgbuild
    pkgbuild \
        --root "$pkg_root" \
        --install-location "/" \
        --identifier "$bundle_id.installer" \
        --version "$VERSION" \
        --timestamp \
        --sign "$INSTALLER_SIGNING_IDENTITY" \
        "artifacts/$pkg_name"
    
    if [ $? -eq 0 ]; then
        echo "  ✅ PKG created successfully with native pkgbuild"
    else
        echo "  ❌ PKG creation failed"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    echo "  🔍 Verifying PKG signature..."
    # Verify PKG signature
    pkgutil --check-signature "artifacts/$pkg_name"
    if [ $? -eq 0 ]; then
        echo "  ✅ PKG signature verification passed"
    else
        echo "  ❌ PKG signature verification failed"
        exit 1
    fi
    
    # Test PKG with spctl
    echo "  🔍 Testing PKG with Gatekeeper..."
    spctl --assess --type install "artifacts/$pkg_name" && echo "  ✅ PKG Gatekeeper test passed" || echo "  ⚠️ PKG Gatekeeper test failed (may pass after notarization)"
    
    echo "✅ PKG installer created and verified: $pkg_name"
    
    # Show PKG info
    local pkg_size=$(du -h "artifacts/$pkg_name" | cut -f1)
    echo "  📊 PKG size: $pkg_size"
}

# Verify required environment variables
if [ -z "${INSTALLER_SIGNING_IDENTITY:-}" ]; then
    echo "❌ INSTALLER_SIGNING_IDENTITY not set. Run setup-github-secrets-certificates.sh first"
    exit 1
fi

# Create PKG for server
if [ -d "build_native/server/dist/R2MIDI Server.app" ]; then
    create_pkg_native \
        "build_native/server/dist/R2MIDI Server.app" \
        "R2MIDI Server" \
        "com.tirans.m2midi.r2midi.server" \
        "R2MIDI-Server-$VERSION.pkg"
else
    echo "⚠️ Warning: Server app not found, skipping PKG creation"
fi

# Create PKG for client
if [ -d "build_native/client/dist/R2MIDI Client.app" ]; then
    create_pkg_native \
        "build_native/client/dist/R2MIDI Client.app" \
        "R2MIDI Client" \
        "com.tirans.m2midi.r2midi.client" \
        "R2MIDI-Client-$VERSION.pkg"
else
    echo "⚠️ Warning: Client app not found, skipping PKG creation"
fi

echo "✅ PKG installer creation complete"
