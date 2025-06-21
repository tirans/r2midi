#!/bin/bash

# build-macos-clean-environment.sh - Clean environment for GitHub Actions build
# Usage: ./build-macos-clean-environment.sh BUILD_TYPE

set -euo pipefail

BUILD_TYPE="$1"

echo "🧹 Cleaning environment for GitHub Actions build..."
echo "Build type: $BUILD_TYPE"

# Use the main clean environment script with appropriate flags
if [ -f "./clean-environment.sh" ]; then
    echo "📋 Using main clean-environment.sh script..."
    
    # For production builds, keep cache for faster subsequent builds
    if [ "$BUILD_TYPE" = "production" ]; then
        ./clean-environment.sh --keep-cache
    else
        ./clean-environment.sh
    fi
else
    echo "⚠️ clean-environment.sh not found, performing basic cleanup..."
    
    # Basic cleanup if main script is missing
    rm -rf build dist build_native build_client build_server artifacts *.app *.pkg *.dmg 2>/dev/null || true
    rm -rf venv venv_client venv_server .venv env 2>/dev/null || true
    rm -rf __pycache__ .pytest_cache htmlcov 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "*.pyo" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
fi

# GitHub Actions specific cleanup
echo "🔄 GitHub Actions specific cleanup..."

# Clean any previous certificate files
rm -f app_cert.p12 installer_cert.p12 *.p12 2>/dev/null || true

# Clean any previous keychains
if security list-keychains | grep -q "r2midi-build"; then
    echo "  🔐 Removing previous build keychains..."
    security delete-keychain r2midi-build.keychain 2>/dev/null || true
fi

# Clean temporary directories in runner
if [ -d "/tmp" ]; then
    find /tmp -name "*r2midi*" -user "$(whoami)" -delete 2>/dev/null || true
    find /tmp -name "*py2app*" -user "$(whoami)" -delete 2>/dev/null || true
fi

# Reset any environment variables from previous runs
unset TEMP_KEYCHAIN 2>/dev/null || true
unset TEMP_KEYCHAIN_PASSWORD 2>/dev/null || true
unset APP_SIGNING_IDENTITY 2>/dev/null || true
unset INSTALLER_SIGNING_IDENTITY 2>/dev/null || true

echo "✅ Environment cleanup completed"
