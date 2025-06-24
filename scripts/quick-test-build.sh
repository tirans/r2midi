#!/bin/bash
set -euo pipefail

# quick-test-build.sh - Quick test of the fixed build process
# Usage: ./scripts/quick-test-build.sh

echo "🧪 Quick Test: Fixed Build Process"
echo "================================="

# Test the server build script with help
echo ""
echo "📋 Testing server build script help:"
./build-server-local.sh --help

echo ""
echo "📋 Testing client build script help:"
./build-client-local.sh --help

echo ""
echo "🚀 Testing a quick development build..."
echo "This will test the process without full signing/notarization"

# Test with a development build (faster)
echo ""
echo "📦 Building server (development mode)..."
if ./build-server-local.sh --version "1.0.0-test" --build-type dev --no-notarize; then
    echo "✅ Server build test passed!"
else
    echo "❌ Server build test failed"
    exit 1
fi

echo ""
echo "🎉 Build process is working correctly!"
echo ""
echo "Ready for full production builds:"
echo "  ./scripts/build-local-with-pkg-builder.sh 1.0.0 production"
