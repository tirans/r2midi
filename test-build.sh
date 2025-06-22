#!/bin/bash
# Quick test of the build system

VERSION="0.1.202"
echo "🧪 Testing R2MIDI build system with version $VERSION"
echo ""

# Source environment if available
if [ -f ".local_build_env" ]; then
    echo "📋 Sourcing build environment..."
    source .local_build_env
fi

# Run a test build
echo "🏗️ Running test build..."
echo "Command: ./build-all-local.sh --version $VERSION --dev --no-notarize"
echo ""

if ./build-all-local.sh --version $VERSION --dev --no-notarize; then
    echo ""
    echo "✅ Test build completed successfully!"
    echo ""
    echo "📦 Generated artifacts:"
    find artifacts -name "*$VERSION*" -type f | while read artifact; do
        echo "  ✅ $(basename "$artifact")"
    done
else
    echo ""
    echo "❌ Test build failed"
    exit 1
fi
