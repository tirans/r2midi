#!/bin/bash
set -euo pipefail

# test-simplified-build.sh - Test the macOS-Pkg-Builder build system
# Usage: ./test-simplified-build.sh [--component server|client|both] [--dev]

echo "🧪 Testing R2MIDI Build System (macOS-Pkg-Builder)"
echo "=================================================="

# Default values
COMPONENT="both"
BUILD_TYPE="production"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        --dev)
            BUILD_TYPE="dev"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --component TYPE    Test component (server, client, both)"
            echo "  --dev              Development build (unsigned)"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Test configuration:"
echo "  Component: $COMPONENT"
echo "  Build type: $BUILD_TYPE"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

if [ "$(uname)" != "Darwin" ]; then
    echo "❌ This test requires macOS"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python 3 is required"
    exit 1
fi

if ! command -v security >/dev/null 2>&1; then
    echo "❌ macOS security command is required"
    exit 1
fi

echo "✅ Prerequisites OK"
echo ""

# Test the new build system
echo "🚀 Testing macOS-Pkg-Builder build system..."

if [ "$BUILD_TYPE" = "dev" ]; then
    echo "📦 Testing development build (unsigned)..."
    if ./build-all-local.sh --component "$COMPONENT" --no-sign; then
        echo "✅ Development build test passed"
    else
        echo "❌ Development build test failed"
        exit 1
    fi
else
    echo "🔨 Testing production build..."
    
    # Check for certificates
    if [ -f "apple_credentials/certificates/app_cert.p12" ] && [ -f "apple_credentials/certificates/installer_cert.p12" ]; then
        echo "✅ Local certificates found"
        
        # Test with signing but no notarization for faster testing
        if ./build-all-local.sh --component "$COMPONENT" --no-notarize; then
            echo "✅ Production build test passed"
            
            # Check artifacts
            if [ -d "artifacts" ]; then
                echo "📦 Generated artifacts:"
                find artifacts -name "*.pkg" -exec ls -lh {} \;
                
                # Test PKG signatures
                for pkg in artifacts/*.pkg; do
                    if [ -f "$pkg" ]; then
                        echo "🔍 Checking signature of $(basename "$pkg")..."
                        if pkgutil --check-signature "$pkg" >/dev/null 2>&1; then
                            echo "✅ $(basename "$pkg") is signed"
                        else
                            echo "ℹ️  $(basename "$pkg") is not signed"
                        fi
                    fi
                done
            fi
        else
            echo "❌ Production build test failed"
            exit 1
        fi
    else
        echo "⚠️  No local certificates found, testing unsigned build..."
        if ./build-all-local.sh --component "$COMPONENT" --no-sign; then
            echo "✅ Unsigned build test passed"
        else
            echo "❌ Unsigned build test failed"
            exit 1
        fi
    fi
fi

echo ""
echo "🎉 Build system tests completed successfully!"
echo ""
echo "Available build commands:"
echo "  ./build-all-local.sh                    # Build both components (signed & notarized)"
echo "  ./build-all-local.sh --no-sign          # Build unsigned (development)"
echo "  ./build-all-local.sh --component server # Build only server component"
echo "  python3 build-pkg.py --help            # See all build options"
echo ""
echo "Certificate configuration:"
echo "  Local: apple_credentials/config/app_config.json"
echo "  GitHub: Environment variables (APPLE_ID, APPLE_CERT_PASSWORD, etc.)"