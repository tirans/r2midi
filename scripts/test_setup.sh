#!/bin/bash
# Test if the setup_github_secrets.py script works with sample data

echo "🧪 Testing macOS GitHub Secrets Setup"
echo "====================================="

cd /Users/tirane/Desktop/r2midi

# Check if configuration exists
if [ -f "apple_credentials/config/app_config.json" ]; then
    echo "✅ Configuration file found"
    
    # Show current config (without sensitive data)
    echo ""
    echo "📋 Current configuration:"
    echo "Apple ID: $(jq -r '.apple_developer.apple_id // "Not set"' apple_credentials/config/app_config.json)"
    echo "Team ID: $(jq -r '.apple_developer.team_id // "Not set"' apple_credentials/config/app_config.json)"
    echo "Repository: $(jq -r '.github.repository // "Not set"' apple_credentials/config/app_config.json)"
    echo ""
else
    echo "❌ Configuration file not found"
    exit 1
fi

# Check for Python
if command -v python3 >/dev/null 2>&1; then
    echo "✅ Python 3 found: $(python3 --version)"
elif command -v python >/dev/null 2>&1; then
    echo "✅ Python found: $(python --version)"
else
    echo "❌ Python not found"
    exit 1
fi

# Check if P12 files exist
echo ""
echo "🔍 Looking for P12 certificates..."

SEARCH_LOCATIONS=(
    "apple_credentials/certificates"
    ".github/scripts"
    "."
)

FOUND_APP=false
FOUND_INSTALLER=false

for location in "${SEARCH_LOCATIONS[@]}"; do
    if [ -f "$location/app_cert.p12" ]; then
        echo "✅ Found app_cert.p12 in: $location"
        FOUND_APP=true
    fi
    
    if [ -f "$location/installer_cert.p12" ]; then
        echo "✅ Found installer_cert.p12 in: $location"
        FOUND_INSTALLER=true
    fi
done

if [ "$FOUND_APP" = true ] && [ "$FOUND_INSTALLER" = true ]; then
    echo ""
    echo "🎯 Ready to run! Execute:"
    echo "  python scripts/setup_github_secrets.py"
else
    echo ""
    echo "⚠️  P12 certificates missing. To create them:"
    echo "  cd .github/scripts"
    echo "  ./setup-macos-signing.sh"
fi

echo ""
echo "🔧 Script locations:"
echo "  Main script: scripts/setup_github_secrets.py"
echo "  Quick setup: scripts/quick_macos_setup.sh"
echo "  Certificate setup: .github/scripts/setup-macos-signing.sh"
