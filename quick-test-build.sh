#!/bin/bash

# quick-test-build.sh - Quick test to check if builds can create PKGs without certificates

set -euo pipefail

echo "Quick Build Test"
echo "==============="

# Check if we have the app bundles from previous builds
echo ""
echo "Checking for existing app bundles..."

if [ -d "build_client/dist/R2MIDI Client.app" ]; then
    echo "✅ Found client app bundle"
    
    # Try to create a PKG
    echo "Creating unsigned PKG for client..."
    mkdir -p artifacts
    
    if pkgbuild --identifier "com.r2midi.client" \
                --version "test-1.0" \
                --install-location "/Applications" \
                --component "build_client/dist/R2MIDI Client.app" \
                "artifacts/R2MIDI-Client-test.pkg"; then
        echo "✅ Successfully created client PKG"
        ls -la artifacts/R2MIDI-Client-test.pkg
    else
        echo "❌ Failed to create client PKG"
    fi
else
    echo "❌ Client app bundle not found"
fi

echo ""
if [ -d "build_server/dist/R2MIDI Server.app" ]; then
    echo "✅ Found server app bundle"
    
    # Try to create a PKG
    echo "Creating unsigned PKG for server..."
    mkdir -p artifacts
    
    if pkgbuild --identifier "com.r2midi.server" \
                --version "test-1.0" \
                --install-location "/Applications" \
                --component "build_server/dist/R2MIDI Server.app" \
                "artifacts/R2MIDI-Server-test.pkg"; then
        echo "✅ Successfully created server PKG"
        ls -la artifacts/R2MIDI-Server-test.pkg
    else
        echo "❌ Failed to create server PKG"
    fi
else
    echo "❌ Server app bundle not found"
fi

echo ""
echo "Test complete!"
echo ""
echo "PKGs in artifacts directory:"
ls -la artifacts/*.pkg 2>/dev/null || echo "No PKG files found"
