#!/bin/bash
# Simple wrapper for GitHub Secrets Manager

set -euo pipefail

echo "🔐 R2MIDI GitHub Secrets Manager"
echo "================================"
echo ""

cd /Users/tirane/Desktop/r2midi

# Parse arguments
PYTHON_ARGS=""
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            PYTHON_ARGS="$PYTHON_ARGS --force"
            FORCE_MODE=true
            shift
            ;;
        --install-deps)
            PYTHON_ARGS="$PYTHON_ARGS --install-deps"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --force        Force update all secrets"
            echo "  --install-deps     Install dependencies first"
            echo "  -h, --help         Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                 # Normal run"
            echo "  $0 --force         # Force update all secrets"
            echo "  $0 --install-deps  # Install deps and run"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

if [ "$FORCE_MODE" = true ]; then
    echo "🔥 Force mode enabled - all secrets will be updated"
    echo ""
fi

# Check for Python
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "❌ Python not found. Please install Python 3.8+"
    exit 1
fi

# Run the main script
echo "🚀 Running GitHub Secrets Manager..."
echo ""

if $PYTHON_CMD scripts/setup_github_secrets.py $PYTHON_ARGS; then
    echo ""
    echo "🎉 SUCCESS!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Push a commit to trigger your macOS build workflow"
    echo "2. Check GitHub Actions to see signed apps being built"
    echo ""
    repository=$(jq -r '.github.repository // "your-repo"' apple_credentials/config/app_config.json 2>/dev/null || echo "your-repo")
    echo "🔗 GitHub Actions: https://github.com/$repository/actions"
else
    echo ""
    echo "❌ Setup failed. Check the error messages above."
    echo ""
    echo "💡 Try:"
    echo "  $0 --install-deps  # Install dependencies"
    echo "  $0 --force         # Force update all secrets"
    exit 1
fi
