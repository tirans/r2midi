#!/bin/bash
set -euo pipefail

# clean-for-signing.sh - Clean app bundles for signing using bulletproof method

echo "🧹 Bulletproof App Bundle Cleaning"
echo "=================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if we have app bundles to clean
if [ -d "build_client/dist/R2MIDI Client.app" ] || [ -d "build_server/dist/R2MIDI Server.app" ]; then
    echo "Found app bundles to clean"
else
    echo "No app bundles found. Run build first."
    exit 1
fi

# Make scripts executable
chmod +x scripts/bulletproof_clean_app_bundle.py

# Clean client app if it exists
if [ -d "build_client/dist/R2MIDI Client.app" ]; then
    echo ""
    echo "Cleaning R2MIDI Client.app..."
    if python3 scripts/bulletproof_clean_app_bundle.py --method ditto "build_client/dist/R2MIDI Client.app"; then
        echo "✅ Client app cleaned successfully"
    else
        echo "⚠️  Ditto method failed, trying auto method..."
        if python3 scripts/bulletproof_clean_app_bundle.py --method auto "build_client/dist/R2MIDI Client.app"; then
            echo "✅ Client app cleaned with auto method"
        else
            echo "❌ Failed to clean client app"
        fi
    fi
fi

# Clean server app if it exists
if [ -d "build_server/dist/R2MIDI Server.app" ]; then
    echo ""
    echo "Cleaning R2MIDI Server.app..."
    if python3 scripts/bulletproof_clean_app_bundle.py --method ditto "build_server/dist/R2MIDI Server.app"; then
        echo "✅ Server app cleaned successfully"
    else
        echo "⚠️  Ditto method failed, trying auto method..."
        if python3 scripts/bulletproof_clean_app_bundle.py --method auto "build_server/dist/R2MIDI Server.app"; then
            echo "✅ Server app cleaned with auto method"
        else
            echo "❌ Failed to clean server app"
        fi
    fi
fi

echo ""
echo "Verifying cleanup..."
echo ""

# Verify client
if [ -d "build_client/dist/R2MIDI Client.app" ]; then
    echo "R2MIDI Client.app:"
    python3 scripts/bulletproof_clean_app_bundle.py --verify-only "build_client/dist/R2MIDI Client.app"
fi

# Verify server
if [ -d "build_server/dist/R2MIDI Server.app" ]; then
    echo ""
    echo "R2MIDI Server.app:"
    python3 scripts/bulletproof_clean_app_bundle.py --verify-only "build_server/dist/R2MIDI Server.app"
fi

echo ""
echo "✅ Cleaning complete!"
echo ""
echo "You can now run the signing process:"
echo "  ./.github/scripts/sign-and-notarize-macos.sh --version 0.1.207"
