#!/bin/bash
# Quick setup script for macOS GitHub secrets

set -euo pipefail

echo "🍎 R2MIDI macOS GitHub Secrets Setup"
echo "====================================="
echo ""

PROJECT_ROOT="/Users/tirane/Desktop/r2midi"
cd "$PROJECT_ROOT"

# Check if we have the required files
echo "🔍 Checking prerequisites..."

if [ ! -f "apple_credentials/config/app_config.json" ]; then
    echo "❌ Configuration file not found: apple_credentials/config/app_config.json"
    exit 1
fi

echo "✅ Configuration file found"

# Look for P12 certificates
P12_FOUND=false
SEARCH_PATHS=(
    "apple_credentials/certificates"
    ".github/scripts"
    "."
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path/app_cert.p12" ] && [ -f "$path/installer_cert.p12" ]; then
        echo "✅ P12 certificates found in: $path"
        P12_FOUND=true
        break
    fi
done

if [ "$P12_FOUND" = false ]; then
    echo "❌ P12 certificates not found"
    echo ""
    echo "Please ensure you have these files in one of these locations:"
    for path in "${SEARCH_PATHS[@]}"; do
        echo "  - $path/app_cert.p12"
        echo "  - $path/installer_cert.p12"
    done
    echo ""
    echo "To create P12 certificates, run:"
    echo "  cd .github/scripts"
    echo "  ./setup-macos-signing.sh"
    exit 1
fi

# Run the Python script
echo ""
echo "🚀 Running GitHub secrets generator..."
echo ""

if command -v python3 >/dev/null 2>&1; then
    python3 scripts/setup_github_secrets.py
elif command -v python >/dev/null 2>&1; then
    python scripts/setup_github_secrets.py
else
    echo "❌ Python not found. Please install Python 3.8+"
    exit 1
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Open the generated 'github_secrets_macos.txt' file"
echo "2. Copy each secret to your GitHub repository"
echo "3. Delete the secrets file for security"
echo "4. Test by pushing a commit"
