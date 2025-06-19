#!/bin/bash
# Setup and run GitHub secrets manager with optional force flag

set -euo pipefail

echo "🔐 R2MIDI GitHub Secrets Manager Setup"
echo "====================================="

# Parse command line arguments
FORCE_FLAG=""
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_FLAG="--force"
            echo "🔥 FORCE MODE enabled - all secrets will be updated"
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            SHOW_HELP=true
            shift
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Force update all secrets even if they already exist"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Normal idempotent update"
    echo "  $0 --force      # Force update all secrets"
    echo "  $0 -f           # Force update (short form)"
    exit 0
fi

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

# Check for Python
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "❌ Python not found. Please install Python 3.8+"
    exit 1
fi

echo "✅ Python found: $($PYTHON_CMD --version)"

# Install requirements
echo ""
echo "📦 Installing Python dependencies..."
echo "Installing: requests (GitHub API) + PyNaCl (encryption)"

if $PYTHON_CMD -m pip install -r scripts/requirements.txt --quiet; then
    echo "✅ Dependencies installed successfully"
else
    echo "❌ Failed to install dependencies"
    echo "Try running manually: $PYTHON_CMD -m pip install requests PyNaCl"
    exit 1
fi

# Check configuration
echo ""
echo "📋 Validating configuration..."

# Extract key values from config (without exposing sensitive data)
APPLE_ID=$(jq -r '.apple_developer.apple_id // "Not set"' apple_credentials/config/app_config.json 2>/dev/null || echo "Not set")
TEAM_ID=$(jq -r '.apple_developer.team_id // "Not set"' apple_credentials/config/app_config.json 2>/dev/null || echo "Not set")
REPOSITORY=$(jq -r '.github.repository // "Not set"' apple_credentials/config/app_config.json 2>/dev/null || echo "Not set")

# Check for GitHub token without exposing it
if jq -r '.github.personal_access_token // "missing"' apple_credentials/config/app_config.json 2>/dev/null | grep -q "github_pat\|ghp_"; then
    HAS_TOKEN="✅ Found"
else
    HAS_TOKEN="❌ Missing"
fi

echo "Apple ID: $APPLE_ID"
echo "Team ID: $TEAM_ID"
echo "Repository: $REPOSITORY"
echo "GitHub Token: $HAS_TOKEN"

if [ "$APPLE_ID" = "Not set" ] || [ "$TEAM_ID" = "Not set" ] || [ "$REPOSITORY" = "Not set" ] || [ "$HAS_TOKEN" = "❌ Missing" ]; then
    echo ""
    echo "❌ Configuration incomplete. Please check apple_credentials/config/app_config.json"
    exit 1
fi

# Look for P12 certificates
echo ""
echo "🔍 Looking for P12 certificates..."

SEARCH_LOCATIONS=(
    "apple_credentials/certificates"
    ".github/scripts"
    "."
)

FOUND_CERTS=false

for location in "${SEARCH_LOCATIONS[@]}"; do
    if [ -f "$location/app_cert.p12" ] && [ -f "$location/installer_cert.p12" ]; then
        echo "✅ Found P12 certificates in: $location"
        FOUND_CERTS=true
        break
    fi
done

if [ "$FOUND_CERTS" = false ]; then
    echo "❌ P12 certificates not found in any location"
    echo ""
    echo "To create P12 certificates, run:"
    echo "  cd .github/scripts"
    echo "  ./setup-macos-signing.sh"
    echo ""
    echo "This will guide you through exporting certificates from Keychain Access."
    exit 1
fi

echo ""
if [ -n "$FORCE_FLAG" ]; then
    echo "🔥 Running GitHub secrets manager in FORCE MODE..."
    echo "All secrets will be updated regardless of current state."
else
    echo "🚀 Running GitHub secrets manager in idempotent mode..."
    echo "Only missing or changed secrets will be updated."
fi
echo ""

# Run the main script with force flag if specified
if $PYTHON_CMD scripts/setup_github_secrets.py $FORCE_FLAG; then
    echo ""
    if [ -n "$FORCE_FLAG" ]; then
        echo "🎉 SUCCESS! All GitHub secrets have been force updated."
    else
        echo "🎉 SUCCESS! All GitHub secrets have been configured."
    fi
    echo ""
    echo "📋 Next steps:"
    echo "1. Push a commit to trigger the macOS build workflow"
    echo "2. Check the Actions tab in your GitHub repository"
    echo "3. Verify that signed .dmg and .pkg files are created"
    echo ""
    echo "🔗 GitHub repository: https://github.com/$REPOSITORY"
    echo "🔗 GitHub Actions: https://github.com/$REPOSITORY/actions"
    
    if [ -n "$FORCE_FLAG" ]; then
        echo ""
        echo "🔥 Note: Force mode was used - all secrets were refreshed from current configuration"
    fi
else
    echo ""
    echo "❌ Failed to configure GitHub secrets."
    echo "Check the error messages above for details."
    echo ""
    echo "💡 Common solutions:"
    echo "  - Ensure dependencies are installed: pip install requests PyNaCl"
    echo "  - Verify GitHub token has admin permissions on repository"
    echo "  - Check that P12 certificates are valid and password is correct"
    echo "  - Try force mode: $0 --force"
    exit 1
fi
