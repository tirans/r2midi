#!/bin/bash

# build-client-local.sh - Build R2MIDI Client locally with signing and notarization
# Usage: ./build-client-local.sh [--version VERSION] [--no-sign] [--no-notarize]

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

echo "🎨 Building R2MIDI Client locally..."
echo "Build type: $BUILD_TYPE"
echo "Skip signing: $SKIP_SIGNING"
echo "Skip notarization: $SKIP_NOTARIZATION"

# Check if client virtual environment exists
if [ ! -d "venv_client" ]; then
    echo "❌ Client virtual environment not found"
    echo "Run: ./setup-virtual-environments.sh --client-only"
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
mkdir -p build_client/{build,dist,artifacts}
mkdir -p artifacts

# Activate client virtual environment
echo "🐍 Activating client virtual environment..."
source venv_client/bin/activate

# Verify environment
echo "🧪 Verifying client environment..."
python -c "
import sys
print(f'Python: {sys.version}')

# Check required packages
required = ['PyQt6', 'httpx', 'pydantic', 'py2app']
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
cp setup_client.py build_client/setup.py
cp -r r2midi_client build_client/
cp -r resources build_client/ 2>/dev/null || true

# Change to build directory
cd build_client

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf build dist *.app setup_*.py 2>/dev/null || true

# Update version in setup file
echo "🔢 Setting version to $VERSION..."
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py
rm setup.py.bak

# Build with py2app
echo "📦 Building client with py2app..."
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
if [ -d "dist/R2MIDI Client.app" ]; then
    APP_PATH="dist/R2MIDI Client.app"
    echo "✅ Client app found: $APP_PATH"
elif [ -d "dist/main.app" ]; then
    mv "dist/main.app" "dist/R2MIDI Client.app"
    APP_PATH="dist/R2MIDI Client.app"
    echo "✅ Client app renamed: $APP_PATH"
else
    echo "❌ Client app not found"
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

# Show app size
if command -v du >/dev/null 2>&1; then
    app_size=$(du -sh "$APP_PATH" | cut -f1)
    echo "📦 App bundle size: $app_size"
fi

# Code signing and notarization (if not skipped)
if [ "$SKIP_SIGNING" = "false" ]; then
    echo ""
    echo "🔐 Starting signing and notarization..."

    # Check if signing script exists
    if [ -f "../.github/scripts/sign-and-notarize-macos.sh" ]; then
        echo "📋 Using signing script"

        # Build arguments for signing script
        local sign_args="--version $VERSION"

        if [ "$BUILD_TYPE" = "dev" ]; then
            sign_args="$sign_args --dev"
        fi

        if [ "$SKIP_NOTARIZATION" = "true" ]; then
            sign_args="$sign_args --skip-notarize"
        fi

        # Run signing from project root
        cd ..
        if ./.github/scripts/sign-and-notarize-macos.sh $sign_args; then
            echo "✅ Signing and notarization completed"
        else
            echo "❌ Signing failed"
            if [ "$BUILD_TYPE" != "dev" ]; then
                exit 1
            fi
        fi
        cd build_client
    else
        echo "⚠️ Signing script not found, using basic signing"

        # Fallback to basic signing
        SIGNING_IDENTITY="Developer ID Application"
        if security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
            echo "✅ Found signing identity: $SIGNING_IDENTITY"

            # Create basic entitlements for client
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
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
EOF

            codesign --force --options runtime --entitlements entitlements.plist --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"

            # Create PKG installer
            PKG_NAME="R2MIDI-Client-${VERSION}.pkg"
            INSTALLER_PATH="artifacts/${PKG_NAME}"

            pkgbuild --identifier "com.r2midi.client" \
                     --version "$VERSION" \
                     --install-location "/Applications" \
                     --component "dist/R2MIDI Client.app" \
                     "$INSTALLER_PATH"

            echo "✅ Basic signing completed"
        else
            echo "⚠️ No signing identity found - creating unsigned build"
        fi
    fi
else
    echo "⏭️ Skipping code signing"

    # Create unsigned PKG
    echo "📦 Creating unsigned PKG installer..."
    PKG_NAME="R2MIDI-Client-${VERSION}.pkg"
    INSTALLER_PATH="artifacts/${PKG_NAME}"

    pkgbuild --identifier "com.r2midi.client" \
             --version "$VERSION" \
             --install-location "/Applications" \
             --component "dist/R2MIDI Client.app" \
             "$INSTALLER_PATH"
fi

# Copy artifacts to main artifacts directory
echo ""
echo "📋 Copying artifacts..."

cd ..  # Back to project root
cp "build_client/artifacts/${PKG_NAME}" "artifacts/"

# Create build report
BUILD_REPORT="artifacts/CLIENT_BUILD_REPORT_${VERSION}.md"
cat > "$BUILD_REPORT" << EOF
# R2MIDI Client Build Report

**Version:** $VERSION  
**Build Date:** $(date)  
**Build Type:** $BUILD_TYPE  
**Platform:** $(uname -s) $(uname -r)  
**Architecture:** $(uname -m)  

## Build Results

- ✅ App Bundle: R2MIDI Client.app
- ✅ PKG Installer: ${PKG_NAME}
- App Size: $(du -sh "build_client/$APP_PATH" 2>/dev/null | cut -f1 || echo "unknown")
- PKG Size: $(du -sh "artifacts/${PKG_NAME}" 2>/dev/null | cut -f1 || echo "unknown")

## Build Configuration

- Python Version: $(python3 --version)
- Virtual Environment: venv_client
- py2app Options: Optimized configuration with duplicate file prevention
- Code Signing: $([ "$SKIP_SIGNING" = "false" ] && echo "Enabled" || echo "Disabled")
- Notarization: $([ "$SKIP_NOTARIZATION" = "false" ] && echo "Enabled" || echo "Disabled")

## Package Dependencies

$(pip list | grep -E "(PyQt6|httpx|pydantic|py2app)" || echo "Dependencies not listed")

## Installation

To install the client:
\`\`\`bash
sudo installer -pkg artifacts/${PKG_NAME} -target /
\`\`\`

The app will be installed to: /Applications/R2MIDI Client.app
EOF

echo "📄 Build report created: $BUILD_REPORT"

# Deactivate virtual environment
deactivate

# Final summary
echo ""
echo "✅ R2MIDI Client build completed successfully!"
echo ""
echo "📦 Build artifacts:"
echo "  - App bundle: build_client/$APP_PATH"
echo "  - PKG installer: artifacts/${PKG_NAME}"
echo "  - Build report: $BUILD_REPORT"
echo ""
echo "🚀 Ready for distribution!"

# Show next steps
echo ""
echo "📋 Next steps:"
echo "  1. Test the app: open 'build_client/$APP_PATH'"
echo "  2. Test installer: sudo installer -pkg 'artifacts/${PKG_NAME}' -target /"
echo "  3. Build server: ./build-server-local.sh"
echo ""
echo "💡 The PKG installer will install the app to /Applications/"
