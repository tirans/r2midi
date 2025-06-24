#!/bin/bash
set -euo pipefail

# fix-signing.sh - Quick fix for macOS signing issues

echo "🔧 R2MIDI macOS Signing Fix"
echo "==========================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Step 1: Make all scripts executable
echo "Step 1: Making scripts executable..."
chmod +x scripts/bulletproof_clean_app_bundle.py
chmod +x scripts/clean-app-bundles.sh
chmod +x build-all-local.sh
chmod +x build-client-local.sh
chmod +x build-server-local.sh
chmod +x setup-local-certificates.sh
chmod +x clean-for-signing.sh
chmod +x emergency-fix-python-framework.sh
chmod +x .github/scripts/clean-app.sh
chmod +x test-signing-environment.sh
echo "✅ Scripts are now executable"
echo ""

# Step 2: Clean any existing app bundles
echo "Step 2: Cleaning existing app bundles..."
if [ -d "build_client/dist" ] || [ -d "build_server/dist" ]; then
    ./scripts/clean-app-bundles.sh || true
fi
echo ""

# Step 4: Setup certificates
echo "Step 4: Setting up certificates..."
if [ -f "setup-local-certificates.sh" ]; then
    ./setup-local-certificates.sh
else
    echo "⚠️  setup-local-certificates.sh not found"
fi
echo ""

# Step 5: Ready to build
echo "✅ Signing fix complete!"
echo ""
echo "Now you can build with:"
echo "  ./build-all-local.sh --clean --version 0.1.207"
echo ""
echo "The build process will now:"
echo "  1. Deep clean app bundles to remove all extended attributes"
echo "  2. Sign without 'resource fork' errors"
echo "  3. Successfully notarize (if credentials are configured)"
echo ""
echo "If you still see signing errors, use the bulletproof cleaner:"
echo "  python3 scripts/bulletproof_clean_app_bundle.py 'build_client/dist/R2MIDI Client.app'"
echo "  python3 scripts/bulletproof_clean_app_bundle.py 'build_server/dist/R2MIDI Server.app'"
echo ""
echo "Or use the convenient wrapper:"
echo "  ./clean-for-signing.sh"
