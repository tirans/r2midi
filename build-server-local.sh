#!/bin/bash

# build-server-local.sh - Build R2MIDI Server locally with signing and notarization
# Usage: ./build-server-local.sh [--version VERSION] [--no-sign] [--no-notarize]

set -euo pipefail

# Default values
VERSION=""
SKIP_SIGNING=false
SKIP_NOTARIZATION=false
BUILD_TYPE="local"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --no-sign)
            SKIP_SIGNING=true
            shift
            ;;
        --no-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --dev)
            BUILD_TYPE="dev"
            shift
            ;;
        *)
            echo "Usage: $0 [--version VERSION] [--no-sign] [--no-notarize] [--dev]"
            echo "  --version VERSION   Specify version (otherwise extracted from code)"
            echo "  --no-sign          Skip code signing"
            echo "  --no-notarize      Skip notarization"
            echo "  --dev              Development build (skip some optimizations)"
            exit 1
            ;;
    esac
done

echo "🖥️ Building R2MIDI Server locally..."
echo "Build type: $BUILD_TYPE"
echo "Skip signing: $SKIP_SIGNING"
echo "Skip notarization: $SKIP_NOTARIZATION"

# Check if server virtual environment exists
if [ ! -d "venv_server" ]; then
    echo "❌ Server virtual environment not found"
    echo "Run: ./setup-virtual-environments.sh --server-only"
    exit 1
fi

# Extract version if not provided
if [ -z "$VERSION" ]; then
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "
import sys
sys.path.insert(0, 'server')
from version import __version__
print(__version__)
")
        echo "📋 Extracted version: $VERSION"
    else
        VERSION="1.0.0"
        echo "⚠️ Using fallback version: $VERSION"
    fi
fi

# Create build directories
echo "📁 Setting up build directories..."
mkdir -p build_server/{build,dist,artifacts}
mkdir -p artifacts

# Activate server virtual environment
echo "🐍 Activating server virtual environment..."
source venv_server/bin/activate

# Verify environment
echo "🧪 Verifying server environment..."
python -c "
import sys
print(f'Python: {sys.version}')

# Check required packages
required = ['fastapi', 'uvicorn', 'rtmidi', 'py2app']
missing = []
for pkg in required:
    try:
        __import__(pkg)
        print(f'✅ {pkg}')
    except ImportError:
        missing.append(pkg)
        print(f'❌ {pkg}')

if missing:
    print(f'Missing packages: {missing}')
    exit(1)
"

# Copy setup file to build directory
echo "📝 Preparing build configuration..."
cp setup_server.py build_server/setup.py

# Copy server directory to build directory (excluding .git)
echo "📁 Copying server directory..."
rsync -av --exclude='.git' server/ build_server/server/

# Change to build directory
cd build_server

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf build dist *.app setup_*.py 2>/dev/null || true

# Update version in setup file
echo "🔢 Setting version to $VERSION..."
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py
rm setup.py.bak

# Build with py2app
echo "📦 Building server with py2app..."
echo "🔧 Build command: python setup.py py2app"

if python setup.py py2app; then
    echo "✅ py2app build completed successfully"
else
    echo "❌ py2app build failed"
    echo "📋 Build directory contents:"
    ls -la . || true
    echo "🔍 Checking for partial builds..."
    if [ -d "build" ]; then
        echo "📁 Build directory contents:"
        find build -type f 2>/dev/null | head -10
    fi
    deactivate
    exit 1
fi

# Check build results
echo "🔍 Checking build results..."
APP_PATH=""
if [ -d "dist/R2MIDI Server.app" ]; then
    APP_PATH="dist/R2MIDI Server.app"
    echo "✅ Server app found: $APP_PATH"
elif [ -d "dist/main.app" ]; then
    mv "dist/main.app" "dist/R2MIDI Server.app"
    APP_PATH="dist/R2MIDI Server.app"
    echo "✅ Server app renamed: $APP_PATH"
else
    echo "❌ Server app not found"
    echo "📁 dist/ directory contents:"
    ls -la dist/ || echo "dist/ directory not found"
    deactivate
    exit 1
fi

# Verify app bundle
echo "🔍 Verifying app bundle..."
if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    bundle_name=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    bundle_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    echo "📋 Bundle Name: $bundle_name"
    echo "📋 Bundle Version: $bundle_version"
else
    echo "⚠️ Info.plist not found"
fi

# Check for MIDI components
echo "🎵 Checking MIDI components..."
if find "$APP_PATH" -name "*midi*" -type f | head -3 | grep -q .; then
    echo "✅ MIDI components found in app bundle"
    midi_count=$(find "$APP_PATH" -name "*midi*" -type f | wc -l)
    echo "🎵 MIDI files: $midi_count"
else
    echo "⚠️ MIDI components not found - server may not work properly"
fi

# Show app size
if command -v du >/dev/null 2>&1; then
    app_size=$(du -sh "$APP_PATH" | cut -f1)
    echo "📦 App bundle size: $app_size"
fi

# Code signing (if not skipped)
if [ "$SKIP_SIGNING" = "false" ]; then
    echo ""
    echo "🔐 Code signing server app..."

    # Check for signing identity
    SIGNING_IDENTITY="Developer ID Application"
    if security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
        echo "✅ Found signing identity: $SIGNING_IDENTITY"

        # Sign the app with entitlements for server functionality
        echo "🔏 Signing app bundle with server entitlements..."

        # Create entitlements for server
        cat > entitlements.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
</dict>
</plist>
EOF

        codesign --force --options runtime --entitlements entitlements.plist --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"

        # Verify signature
        echo "🔍 Verifying signature..."
        if codesign --verify --verbose "$APP_PATH"; then
            echo "✅ App successfully signed"
        else
            echo "❌ App signing verification failed"
            if [ "$BUILD_TYPE" != "dev" ]; then
                deactivate
                exit 1
            fi
        fi
    else
        echo "⚠️ No signing identity found - creating unsigned build"
        if [ "$BUILD_TYPE" != "dev" ]; then
            echo "💡 For signed builds, install Apple Developer certificates"
        fi
    fi
else
    echo "⏭️ Skipping code signing"
fi

# Create PKG installer
echo ""
echo "📦 Creating PKG installer..."

PKG_NAME="R2MIDI-Server-${VERSION}.pkg"
INSTALLER_PATH="artifacts/${PKG_NAME}"

# Create component package
pkgbuild --identifier "com.r2midi.server" \
         --version "$VERSION" \
         --install-location "/Applications" \
         --component "dist/R2MIDI Server.app" \
         "$INSTALLER_PATH"

if [ -f "$INSTALLER_PATH" ]; then
    echo "✅ PKG installer created: $INSTALLER_PATH"

    # Show installer size
    if command -v du >/dev/null 2>&1; then
        pkg_size=$(du -sh "$INSTALLER_PATH" | cut -f1)
        echo "📦 PKG installer size: $pkg_size"
    fi
else
    echo "❌ PKG installer creation failed"
    deactivate
    exit 1
fi

# Sign PKG installer (if not skipped)
if [ "$SKIP_SIGNING" = "false" ]; then
    echo ""
    echo "🔐 Signing PKG installer..."

    # Check for installer signing identity
    INSTALLER_SIGNING_IDENTITY="Developer ID Installer"
    if security find-identity -v -p codesigning | grep -q "$INSTALLER_SIGNING_IDENTITY"; then
        echo "✅ Found installer signing identity: $INSTALLER_SIGNING_IDENTITY"

        # Sign the PKG
        echo "🔏 Signing PKG installer..."
        productsign --sign "$INSTALLER_SIGNING_IDENTITY" "$INSTALLER_PATH" "${INSTALLER_PATH}.signed"

        if [ -f "${INSTALLER_PATH}.signed" ]; then
            mv "${INSTALLER_PATH}.signed" "$INSTALLER_PATH"
            echo "✅ PKG installer successfully signed"
        else
            echo "❌ PKG installer signing failed"
            if [ "$BUILD_TYPE" != "dev" ]; then
                deactivate
                exit 1
            fi
        fi
    else
        echo "⚠️ No installer signing identity found"
        if [ "$BUILD_TYPE" != "dev" ]; then
            echo "💡 For signed PKGs, install Apple Developer certificates"
        fi
    fi
else
    echo "⏭️ Skipping PKG signing"
fi

# Notarization (if not skipped)
if [ "$SKIP_NOTARIZATION" = "false" ] && [ "$SKIP_SIGNING" = "false" ]; then
    echo ""
    echo "📋 Notarizing PKG installer..."

    # Check for notarization credentials
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ID_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
        echo "✅ Found notarization credentials"

        # Submit for notarization
        echo "🚀 Submitting to Apple for notarization..."
        NOTARIZATION_LOG="notarization_server_${VERSION}.log"

        if xcrun notarytool submit "$INSTALLER_PATH" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait > "$NOTARIZATION_LOG" 2>&1; then

            echo "✅ Notarization completed successfully"

            # Staple the notarization
            echo "📎 Stapling notarization ticket..."
            if xcrun stapler staple "$INSTALLER_PATH"; then
                echo "✅ Notarization ticket stapled"
            else
                echo "⚠️ Failed to staple notarization ticket"
            fi
        else
            echo "❌ Notarization failed"
            echo "📋 Notarization log:"
            cat "$NOTARIZATION_LOG" || true
            if [ "$BUILD_TYPE" != "dev" ]; then
                deactivate
                exit 1
            fi
        fi
    else
        echo "⚠️ No notarization credentials found"
        echo "💡 Set APPLE_ID, APPLE_ID_PASSWORD, and APPLE_TEAM_ID for notarization"
    fi
else
    echo "⏭️ Skipping notarization"
fi

# Copy artifacts to main artifacts directory
echo ""
echo "📋 Copying artifacts..."

cd ..  # Back to project root
cp "build_server/artifacts/${PKG_NAME}" "artifacts/"

# Create build report
BUILD_REPORT="artifacts/SERVER_BUILD_REPORT_${VERSION}.md"
cat > "$BUILD_REPORT" << EOF
# R2MIDI Server Build Report

**Version:** $VERSION  
**Build Date:** $(date)  
**Build Type:** $BUILD_TYPE  
**Platform:** $(uname -s) $(uname -r)  
**Architecture:** $(uname -m)  

## Build Results

- ✅ App Bundle: R2MIDI Server.app
- ✅ PKG Installer: ${PKG_NAME}
- App Size: $(du -sh "build_server/$APP_PATH" 2>/dev/null | cut -f1 || echo "unknown")
- PKG Size: $(du -sh "artifacts/${PKG_NAME}" 2>/dev/null | cut -f1 || echo "unknown")

## Build Configuration

- Python Version: $(python3 --version)
- Virtual Environment: venv_server
- py2app Options: Enhanced configuration with duplicate file prevention
- Code Signing: $([ "$SKIP_SIGNING" = "false" ] && echo "Enabled" || echo "Disabled")
- Notarization: $([ "$SKIP_NOTARIZATION" = "false" ] && echo "Enabled" || echo "Disabled")

## Package Dependencies

$(pip list | grep -E "(fastapi|uvicorn|rtmidi|mido|py2app)" || echo "Dependencies not listed")

## Server Features

- ✅ FastAPI web server
- ✅ MIDI device management
- ✅ Real-time MIDI processing
- ✅ RESTful API endpoints
- ✅ WebSocket support

## Installation

To install the server:
\`\`\`bash
sudo installer -pkg artifacts/${PKG_NAME} -target /
\`\`\`

The app will be installed to: /Applications/R2MIDI Server.app

## Usage

Start the server:
\`\`\`bash
open "/Applications/R2MIDI Server.app"
\`\`\`

Or from terminal:
\`\`\`bash
"/Applications/R2MIDI Server.app/Contents/MacOS/R2MIDI Server"
\`\`\`
EOF

echo "📄 Build report created: $BUILD_REPORT"

# Deactivate virtual environment
deactivate

# Final summary
echo ""
echo "✅ R2MIDI Server build completed successfully!"
echo ""
echo "📦 Build artifacts:"
echo "  - App bundle: build_server/$APP_PATH"
echo "  - PKG installer: artifacts/${PKG_NAME}"
echo "  - Build report: $BUILD_REPORT"
echo ""
echo "🚀 Ready for distribution!"

# Show next steps
echo ""
echo "📋 Next steps:"
echo "  1. Test the app: open 'build_server/$APP_PATH'"
echo "  2. Test installer: sudo installer -pkg 'artifacts/${PKG_NAME}' -target /"
echo "  3. Start server: open '/Applications/R2MIDI Server.app'"
echo ""
echo "💡 The PKG installer will install the app to /Applications/"
echo "🌐 Server will be available at: http://localhost:8000"
