#!/bin/bash
set -euo pipefail

# Setup native macOS build environment
# Usage: setup-native-macos-environment.sh [runner_type]

RUNNER_TYPE="${1:-self-hosted}"

echo "🐍 Setting up Python environment for native macOS build..."
echo "⚠️ IMPORTANT: This workflow bypasses Briefcase completely!"
echo "🔧 Using: py2app + codesign + pkgbuild + notarytool"
echo ""
echo "Runner type: $RUNNER_TYPE"
echo "Architecture: $(uname -m)"
echo "macOS version: $(sw_vers -productVersion)"

# Ensure we're using the right Python
python3 --version
echo "PYTHON_CMD=python3" >> "$GITHUB_ENV"

# Detect if this is the M3 Max self-hosted runner
if [ "$RUNNER_TYPE" = "self-hosted" ] && [ "$(uname -m)" = "arm64" ]; then
    echo "🚀 M3 Max Self-Hosted Runner detected - enabling optimizations"
    echo "IS_M3_MAX=true" >> "$GITHUB_ENV"
    echo "RUNNER_TYPE=m3-max-self-hosted" >> "$GITHUB_ENV"
    echo "CPU_CORES=$(sysctl -n hw.logicalcpu)" >> "$GITHUB_ENV"
elif [ "$RUNNER_TYPE" = "self-hosted" ]; then
    echo "🖥️ Self-hosted runner detected"
    echo "IS_M3_MAX=false" >> "$GITHUB_ENV"
    echo "RUNNER_TYPE=self-hosted" >> "$GITHUB_ENV"
else
    echo "☁️ GitHub-hosted runner detected"
    echo "IS_M3_MAX=false" >> "$GITHUB_ENV"
    echo "RUNNER_TYPE=github-hosted" >> "$GITHUB_ENV"
fi

# Verify required macOS tools - CRITICAL CHECK
echo "🔍 Verifying macOS development tools..."
if ! command -v codesign >/dev/null 2>&1; then
    echo "❌ codesign not found - install Xcode Command Line Tools"
    exit 1
fi
if ! command -v pkgbuild >/dev/null 2>&1; then
    echo "❌ pkgbuild not found - install Xcode Command Line Tools"
    exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
    echo "❌ xcrun not found - install Xcode Command Line Tools"
    exit 1
fi
if ! command -v security >/dev/null 2>&1; then
    echo "❌ security framework not available"
    exit 1
fi

echo "✅ All required macOS tools verified"
codesign --version
echo "pkgbuild available: $(pkgbuild --version 2>/dev/null || echo 'yes')"
xcrun --version

echo "✅ Native macOS environment setup complete"
