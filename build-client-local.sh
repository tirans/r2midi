#!/bin/bash

# build-client-local.sh - Build R2MIDI Client locally with signing and notarization
# Usage: ./build-client-local.sh [--version VERSION] [--no-sign] [--no-notarize]

set -euo pipefail

# Make the common certificate setup script executable
chmod +x scripts/common-certificate-setup.sh 2>/dev/null || true

# Source common certificate setup
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/scripts/common-certificate-setup.sh"

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
echo ""

# Clean environment and recreate virtual environments at the beginning
echo "🧹 Cleaning environment and recreating virtual environments..."
if [ -f "./clean-environment.sh" ]; then
    ./clean-environment.sh
    echo "✅ Environment cleanup completed"
else
    echo "⚠️ clean-environment.sh not found, manual cleanup..."
    rm -rf venv_client build_client 2>/dev/null || true
fi

# Recreate client virtual environment
echo "🔄 Recreating client virtual environment..."
if [ -f "./setup-virtual-environments.sh" ]; then
    ./setup-virtual-environments.sh --client-only
    echo "✅ Client virtual environment recreated"
else
    echo "❌ setup-virtual-environments.sh not found"
    exit 1
fi

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

# Verify environment with detailed progress
echo "🧪 Verifying client environment..."
echo "🔍 Checking Python installation and required packages..."
echo ""

python -c "
import sys
import time
print(f'🐍 Python: {sys.version}')
print(f'📍 Python path: {sys.executable}')
print(f'📦 Site packages: {sys.path[-1] if sys.path else \"unknown\"}')
print('')

# Check required packages with progress
required = ['PyQt6', 'httpx', 'pydantic', 'py2app']
missing = []
checked = 0
total = len(required)

print('🔍 Checking required packages:')
for pkg in required:
    checked += 1
    try:
        module = __import__(pkg)
        version = getattr(module, '__version__', 'unknown')
        print(f'✅ {pkg} ({version}) [{checked}/{total}]')
        time.sleep(0.1)  # Small delay for visual effect
    except ImportError:
        missing.append(pkg)
        print(f'❌ {pkg} [MISSING] [{checked}/{total}]')
        time.sleep(0.1)

print('')
if missing:
    print(f'❌ Missing packages: {missing}')
    print('💡 Run: pip install ' + ' '.join(missing))
    exit(1)
else:
    print('✅ All required packages are available')
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
    cleanup_certificates
    print_build_summary "R2MIDI Client" "failed" "Build failed during py2app compilation"
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
    cleanup_certificates
    print_build_summary "R2MIDI Client" "failed" "App bundle not found after build"
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

# Setup certificates before signing
setup_certificates "$SKIP_SIGNING"

# Code signing and notarization (if not skipped and certificates available)
if [ "$SKIP_SIGNING" = "false" ] && [ "$CERT_LOADED" = "true" ]; then
    echo ""
    echo "🔐 Starting signing and notarization..."
    
    # Use clean-app.sh before signing if available
    echo "🧹 Pre-signing app cleaning..."
    if [ -f "../.github/scripts/clean-app.sh" ]; then
        echo "📝 Using clean-app.sh for thorough cleaning..."
        if "../.github/scripts/clean-app.sh" "$APP_PATH"; then
            echo "✅ App bundle cleaned with clean-app.sh"
        else
            echo "⚠️ clean-app.sh failed, using fallback cleaning"
            # Fallback cleaning
            find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
            find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
            xattr -rc "$APP_PATH" 2>/dev/null || true
        fi
    else
        echo "⚠️ clean-app.sh not found, using basic cleaning"
        # Basic cleaning
        find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
        find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
        xattr -rc "$APP_PATH" 2>/dev/null || true
    fi

    # Check if signing script exists (preferred)
    if [ -f "../.github/scripts/sign-and-notarize.sh" ]; then
        echo "📝 Using signing script"
        
        # Build arguments for signing script
        sign_args="--version $VERSION"
        
        if [ "$BUILD_TYPE" = "dev" ]; then
            sign_args="$sign_args --dev"
        fi
        
        if [ "$SKIP_NOTARIZATION" = "true" ]; then
            sign_args="$sign_args --skip-notarize"
        fi
        
        # Run signing from project root
        cd ..
        if ./.github/scripts/sign-and-notarize.sh $sign_args; then
            echo "✅ Signing and notarization completed"
        else
            echo "❌ Signing failed"
            if [ "$BUILD_TYPE" != "dev" ]; then
                cleanup_certificates
                exit 1
            fi
        fi
        cd build_client
    elif [ -f "../.github/scripts/sign-notarize.sh" ]; then
        echo "📋 Using signing script"

        # Build arguments for signing script
        sign_args="--version $VERSION"

        if [ "$BUILD_TYPE" = "dev" ]; then
            sign_args="$sign_args --dev"
        fi

        if [ "$SKIP_NOTARIZATION" = "true" ]; then
            sign_args="$sign_args --skip-notarize"
        fi

        # Run signing from project root
        cd ..
        if ./.github/scripts/sign-notarize.sh $sign_args; then
            echo "✅ Signing and notarization completed"
        else
            echo "⚠️ Signing failed, trying development build approach..."
            # Fallback: try with dev flag to skip strict notarization
            if ./.github/scripts/sign-notarize.sh $sign_args --dev; then
                echo "✅ Development signing completed (some steps may have been skipped)"
            else
                echo "❌ Signing failed completely"
                if [ "$BUILD_TYPE" != "dev" ]; then
                    cleanup_certificates
                    exit 1
                fi
            fi
        fi
        cd build_client
    else
        echo "⚠️ Signing script not found, using basic signing"

        # Use certificate identity from common setup
        if [ -n "$CERT_IDENTITY" ]; then
            echo "✅ Using signing identity: $CERT_IDENTITY"

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

            codesign --force --options runtime --entitlements entitlements.plist --deep --sign "$CERT_IDENTITY" "$APP_PATH"

            # Create PKG installer
            PKG_NAME="R2MIDI-Client-${VERSION}.pkg"
            INSTALLER_PATH="artifacts/${PKG_NAME}"

            pkgbuild --identifier "com.r2midi.client" \
                     --version "$VERSION" \
                     --install-location "/Applications" \
                     --component "dist/R2MIDI Client.app" \
                     "$INSTALLER_PATH"

            # Sign and notarize the PKG
            echo "🔐 Signing and notarizing PKG..."
            if [ -f "../.github/scripts/sign-pkg.sh" ]; then
                if "../.github/scripts/sign-pkg.sh" --pkg "$INSTALLER_PATH"; then
                    echo "✅ PKG signed and notarized successfully"
                else
                    echo "⚠️ PKG signing/notarization failed, but continuing..."
                fi
            else
                echo "⚠️ PKG signing script not found, skipping PKG signing"
            fi

            echo "✅ Basic signing completed"
        else
            echo "⚠️ No valid certificate loaded - creating unsigned build"

            # Create PKG installer even without signing
            PKG_NAME="R2MIDI-Client-${VERSION}.pkg"
            INSTALLER_PATH="artifacts/${PKG_NAME}"

            pkgbuild --identifier "com.r2midi.client" \
                     --version "$VERSION" \
                     --install-location "/Applications" \
                     --component "dist/R2MIDI Client.app" \
                     "$INSTALLER_PATH"

            # Sign and notarize the PKG (even for unsigned app builds, we can still sign the PKG)
            echo "🔐 Signing and notarizing PKG..."
            if [ -f "../.github/scripts/sign-pkg.sh" ]; then
                if "../.github/scripts/sign-pkg.sh" --pkg "$INSTALLER_PATH"; then
                    echo "✅ PKG signed and notarized successfully"
                else
                    echo "⚠️ PKG signing/notarization failed, but continuing..."
                fi
            else
                echo "⚠️ PKG signing script not found, skipping PKG signing"
            fi
        fi
    fi
else
    if [ "$SKIP_SIGNING" = "true" ]; then
        echo "⏭️ Skipping code signing (--no-sign specified)"
    else
        echo "⚠️ No valid certificates available - creating unsigned build"
    fi

    # Create unsigned PKG
    echo "📦 Creating unsigned PKG installer..."
    PKG_NAME="R2MIDI-Client-${VERSION}.pkg"
    INSTALLER_PATH="artifacts/${PKG_NAME}"

    pkgbuild --identifier "com.r2midi.client" \
             --version "$VERSION" \
             --install-location "/Applications" \
             --component "dist/R2MIDI Client.app" \
             "$INSTALLER_PATH"

    # Sign and notarize the PKG (even for unsigned app builds, we can still sign the PKG)
    echo "🔐 Signing and notarizing PKG..."
    if [ -f "../.github/scripts/sign-pkg.sh" ]; then
        if "../.github/scripts/sign-pkg.sh" --pkg "$INSTALLER_PATH"; then
            echo "✅ PKG signed and notarized successfully"
        else
            echo "⚠️ PKG signing/notarization failed, but continuing..."
        fi
    else
        echo "⚠️ PKG signing script not found, skipping PKG signing"
    fi
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

# Cleanup certificates
cleanup_certificates

# Final summary with certificate info
print_build_summary "R2MIDI Client" "success" "
📦 Build artifacts:
  - App bundle: build_client/$APP_PATH
  - PKG installer: artifacts/${PKG_NAME}
  - Build report: $BUILD_REPORT

🚀 Ready for distribution!"

# Show next steps
echo ""
echo "📋 Next steps:"
echo "  1. Test the app: open 'build_client/$APP_PATH'"
echo "  2. Test installer: sudo installer -pkg 'artifacts/${PKG_NAME}' -target /"
echo "  3. Build server: ./build-server-local.sh"
echo ""
echo "💡 The PKG installer will install the app to /Applications/"
