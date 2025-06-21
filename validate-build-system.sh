#!/bin/bash
# validate-build-system.sh - Validate enhanced build system
set -euo pipefail

echo "🔍 Validating Enhanced R2MIDI Build System..."

errors=0

check_file() {
    local file="$1"
    local description="$2"
    if [ -f "$file" ] && [ -x "$file" ]; then
        echo "✅ $description: $file"
    else
        echo "❌ $description missing or not executable: $file"
        errors=$((errors + 1))
    fi
}

echo "📋 Checking core scripts..."
check_file "clean-environment.sh" "Environment cleanup script"
check_file "setup-virtual-environments.sh" "Virtual environment setup"
check_file "build-all-local.sh" "Build script"
check_file "test_environments.sh" "Environment testing"
check_file "verify-signing-setup.sh" "Signing setup verification"

echo "📋 Checking setup files..."
[ -f "setup_client.py" ] && echo "✅ Client setup: setup_client.py" || { echo "❌ setup_client.py missing"; errors=$((errors + 1)); }
[ -f "setup_server.py" ] && echo "✅ Server setup: setup_server.py" || { echo "❌ setup_server.py missing"; errors=$((errors + 1)); }
[ -f "entitlements.plist" ] && echo "✅ Entitlements: entitlements.plist" || { echo "❌ entitlements.plist missing"; errors=$((errors + 1)); }

echo "📋 Checking Apple Developer setup..."
if [ -f "apple_credentials/config/app_config.json" ]; then
    echo "✅ Apple credentials configuration found"
else
    echo "⚠️ Apple credentials configuration missing (signing/notarization will be skipped)"
fi

echo "📋 Checking GitHub Actions..."
[ -f ".github/workflows/build-macos.yml" ] && echo "✅ GitHub workflow exists" || echo "⚠️ GitHub workflow missing"

echo "📋 Checking Python version..."
if python3 --version | grep -E "3\.(1[0-9]|[2-9][0-9])" >/dev/null; then
    echo "✅ Python version: $(python3 --version)"
else
    echo "❌ Python 3.10+ required, found: $(python3 --version)"
    errors=$((errors + 1))
fi

if [ $errors -eq 0 ]; then
    echo ""
    echo "🎉 Validation successful! Enhanced build system is ready."
    echo "📋 Next steps:"
    echo "  1. ./verify-signing-setup.sh (check signing setup)"
    echo "  2. ./setup-virtual-environments.sh"
    echo "  3. ./test_environments.sh"
    echo "  4. ./build-all-local.sh (creates signed, notarized .pkg files)"
    echo ""
    echo "🚀 The build system will create:"
    echo "  • R2MIDI-Client-{version}.pkg (signed & notarized)"
    echo "  • R2MIDI-Server-{version}.pkg (signed & notarized)"
    exit 0
else
    echo ""
    echo "❌ Validation failed with $errors errors."
    echo "Please fix the issues above before proceeding."
    exit 1
fi
