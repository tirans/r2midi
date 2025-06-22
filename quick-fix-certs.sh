#!/bin/bash
# quick-fix-certs.sh - Quick fix to import certificates for build

set -euo pipefail

echo "🔧 Quick Certificate Fix for R2MIDI Build"
echo ""

# Source the environment to get paths
if [ -f ".local_build_env" ]; then
    source .local_build_env
else
    echo "❌ Run ./setup-local-certificates.sh first"
    exit 1
fi

# Import certificates to login keychain
echo "📥 Importing certificates to login keychain..."
security import "$P12_PATH/app_cert.p12" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || echo "  ℹ️ App cert already imported or failed"
security import "$P12_PATH/installer_cert.p12" -P "$P12_PASSWORD" -T /usr/bin/productsign -T /usr/bin/security 2>/dev/null || echo "  ℹ️ Installer cert already imported or failed"

# Set partition list to avoid prompts
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" login.keychain-db 2>/dev/null || true

# Verify
echo ""
echo "🔍 Verifying certificates:"
security find-identity -v -p codesigning | grep "Developer ID" | head -5

echo ""
echo "✅ Done! Now run: ./test-build.sh"
