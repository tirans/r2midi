#!/bin/bash
set -euo pipefail

# build-all-local.sh - R2MIDI build system using macOS-Pkg-Builder
# Usage: ./build-all-local.sh [options]

echo "🚀 R2MIDI Build System (macOS-Pkg-Builder)"
echo "==========================================="

# Default values
VERSION=""
COMPONENT="both"
NO_SIGN=false
NO_NOTARIZE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        --no-sign)
            NO_SIGN=true
            shift
            ;;
        --no-notarize)
            NO_NOTARIZE=true
            shift
            ;;
        --help)
            cat << EOF
R2MIDI Build System using macOS-Pkg-Builder

Usage: $0 [options]

Options:
  --version VERSION       Specify version (auto-detected if not provided)
  --component COMPONENT   Build component: server, client, or both (default: both)
  --no-sign              Skip code signing
  --no-notarize          Skip notarization
  --help                 Show this help

Examples:
  $0                                    # Build both components with signing and notarization
  $0 --component server                # Build only server component
  $0 --no-sign                        # Build without signing (development)
  $0 --version 1.2.3 --no-notarize    # Build specific version, signed but not notarized

Certificate Configuration:
  Local builds: Uses apple_credentials/config/app_config.json
  GitHub Actions: Uses environment variables (APPLE_ID, APPLE_CERT_PASSWORD, etc.)
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Build Configuration:"
echo "  Component: $COMPONENT"
echo "  Version: ${VERSION:-auto-detect}"
echo "  Signing: $([ "$NO_SIGN" = true ] && echo "disabled" || echo "enabled")"
echo "  Notarization: $([ "$NO_NOTARIZE" = true ] && echo "disabled" || echo "enabled")"
echo ""

# Check if we're on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ This script requires macOS"
    exit 1
fi

# Check for Python
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python 3 is required"
    exit 1
fi

# Check for required tools
echo "🔍 Checking build environment..."
for tool in security codesign productsign pkgbuild xcrun; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool is available"
    else
        echo "❌ $tool is missing"
        echo "Please install Xcode Command Line Tools"
        exit 1
    fi
done

# Install macOS-Pkg-Builder if needed
echo "📦 Checking macOS-Pkg-Builder..."
if python3 -c "import macos_pkg_builder" 2>/dev/null; then
    echo "✅ macOS-Pkg-Builder is available"
else
    echo "Installing macOS-Pkg-Builder..."
    python3 -m pip install macos-pkg-builder --break-system-packages || {
        echo "❌ Failed to install macOS-Pkg-Builder"
        echo "Try: pip install macos-pkg-builder --break-system-packages"
        exit 1
    }
fi

# Build arguments
BUILD_ARGS=("--component" "$COMPONENT")

if [ -n "$VERSION" ]; then
    BUILD_ARGS+=("--version" "$VERSION")
fi

if [ "$NO_SIGN" = true ]; then
    BUILD_ARGS+=("--no-sign")
fi

if [ "$NO_NOTARIZE" = true ]; then
    BUILD_ARGS+=("--no-notarize")
fi

# Run the Python builder
echo "🔨 Starting build process..."
set +e  # Temporarily disable exit on error to capture exit code
python3 build-pkg.py "${BUILD_ARGS[@]}"
exit_code=$?
set -e  # Re-enable exit on error

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "🎉 Build completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Test installation: sudo installer -pkg artifacts/R2MIDI-*.pkg -target /"
    echo "  2. Launch applications from /Applications/"
    
    if [ "$NO_SIGN" = false ]; then
        echo "  3. Verify signatures: pkgutil --check-signature artifacts/*.pkg"
        if [ "$NO_NOTARIZE" = false ]; then
            echo "  4. Check notarization: spctl --assess --type install artifacts/*.pkg"
        fi
    fi
else
    echo ""
    echo "❌ Build failed with exit code: $exit_code"
    
    case $exit_code in
        1)
            echo "   Reason: PKG creation failed"
            ;;
        2)
            echo "   Reason: Signing required but failed"
            echo "   💡 Try: $0 --no-sign"
            ;;
        3)
            echo "   Reason: Notarization required but failed"
            echo "   💡 Try: $0 --no-notarize"
            ;;
        4)
            echo "   Reason: Certificate setup failed"
            echo "   💡 Try: $0 --no-sign"
            ;;
        *)
            echo "   Reason: Unknown error"
            ;;
    esac
    
    exit $exit_code
fi