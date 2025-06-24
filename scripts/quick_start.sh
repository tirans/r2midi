#!/bin/bash
# Quick start script for GitHub secrets setup with force option

echo "🚀 R2MIDI GitHub Secrets Quick Start"
echo "====================================="
echo ""

# Parse command line arguments
FORCE_FLAG=""
FORCE_TEXT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_FLAG="--force"
            FORCE_TEXT=" (FORCE MODE)"
            echo "🔥 FORCE MODE enabled - all secrets will be updated regardless of current state"
            echo ""
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --force    Force update all secrets even if they already exist"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0              # Normal idempotent setup"
            echo "  $0 --force      # Force update all secrets"
            echo "  $0 -f           # Force update (short form)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

echo "This will set up ALL GitHub secrets for macOS signing automatically"
echo "using your existing configuration in apple_credentials/config/app_config.json"

if [ -n "$FORCE_FLAG" ]; then
    echo ""
    echo "🔥 FORCE MODE: All secrets will be updated even if they already exist"
    echo "This is useful for refreshing secrets or fixing potential issues"
fi

echo ""

read -p "Ready to proceed$FORCE_TEXT? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

cd /Users/tirane/Desktop/r2midi

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x scripts/*.sh
chmod +x scripts/*.py 2>/dev/null || true

echo ""
echo "🧪 Testing configuration first..."
echo ""

# Test configuration
if python3 scripts/test_github_setup.py 2>/dev/null || python scripts/test_github_setup.py; then
    echo ""
    echo "✅ Configuration test passed!"
    echo ""
    
    if [ -n "$FORCE_FLAG" ]; then
        echo "🔥 Running complete GitHub secrets setup in FORCE MODE..."
    else
        echo "🚀 Running complete GitHub secrets setup..."
    fi
    echo ""
    
    # Run the complete setup with force flag if specified
    if ./scripts/setup_complete_github_secrets.sh $FORCE_FLAG; then
        echo ""
        if [ -n "$FORCE_FLAG" ]; then
            echo "🎉 SUCCESS! All GitHub secrets have been force updated."
            echo ""
            echo "🔥 All secrets were refreshed from your current configuration:"
            echo "• Certificates re-encoded from P12 files"
            echo "• Credentials updated from app_config.json"
            echo "• All secrets replaced with fresh values"
        else
            echo "🎉 SUCCESS! All GitHub secrets have been configured."
        fi
        echo ""
        echo "🔗 Next steps:"
        echo "1. Go to https://github.com/$(jq -r '.github.repository' apple_credentials/config/app_config.json 2>/dev/null || echo 'your-repo')"
        echo "2. Push a commit to trigger the macOS build workflow"
        echo "3. Check the Actions tab to see your signed apps being built"
        echo ""
        echo "Your R2MIDI project is now ready for automated macOS builds! 🎯"
    else
        echo ""
        echo "❌ Setup failed. Check the error messages above."
        exit 1
    fi
else
    echo ""
    echo "❌ Configuration test failed. Please fix the issues above first."
    exit 1
fi
