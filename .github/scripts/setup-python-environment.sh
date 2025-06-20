#!/bin/bash

# setup-python-environment.sh - Setup Python environment and verify macOS tools
# Usage: ./setup-python-environment.sh [runner_type]

set -euo pipefail

RUNNER_TYPE=${1:-${RUNNER_TYPE:-"self-hosted"}}

echo "🐍 Setting up Python environment for native macOS build..."
echo "⚠️ IMPORTANT: This workflow bypasses Briefcase completely!"
echo "🔧 Using: py2app + codesign + pkgbuild + notarytool"
echo ""
echo "Runner type: $RUNNER_TYPE"
echo "Architecture: $(uname -m)"
echo "macOS version: $(sw_vers -productVersion)"

# Ensure we're using the right Python
python3 --version
echo "PYTHON_CMD=python3" >> "${GITHUB_ENV:-/dev/null}"

# Detect if this is the M3 Max self-hosted runner
if [ "$RUNNER_TYPE" = "self-hosted" ] && [ "$(uname -m)" = "arm64" ]; then
    echo "🚀 M3 Max Self-Hosted Runner detected - enabling optimizations"
    echo "IS_M3_MAX=true" >> "${GITHUB_ENV:-/dev/null}"
    echo "RUNNER_TYPE=m3-max-self-hosted" >> "${GITHUB_ENV:-/dev/null}"
    echo "CPU_CORES=$(sysctl -n hw.logicalcpu)" >> "${GITHUB_ENV:-/dev/null}"
    export IS_M3_MAX=true
    export CPU_CORES=$(sysctl -n hw.logicalcpu)
elif [ "$RUNNER_TYPE" = "self-hosted" ]; then
    echo "🖥️ Self-hosted runner detected"
    echo "IS_M3_MAX=false" >> "${GITHUB_ENV:-/dev/null}"
    echo "RUNNER_TYPE=self-hosted" >> "${GITHUB_ENV:-/dev/null}"
    export IS_M3_MAX=false
else
    echo "☁️ GitHub-hosted runner detected"
    echo "IS_M3_MAX=false" >> "${GITHUB_ENV:-/dev/null}"
    echo "RUNNER_TYPE=github-hosted" >> "${GITHUB_ENV:-/dev/null}"
    export IS_M3_MAX=false
fi

# Verify required macOS tools - CRITICAL CHECK
echo "🔍 Verifying macOS development tools..."

check_tool() {
    local tool=$1
    local description=$2
    
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ $tool not found - $description"
        return 1
    else
        echo "✅ $tool found"
        return 0
    fi
}

# Check all required tools
TOOLS_OK=true

check_tool "codesign" "install Xcode Command Line Tools" || TOOLS_OK=false
check_tool "pkgbuild" "install Xcode Command Line Tools" || TOOLS_OK=false
check_tool "xcrun" "install Xcode Command Line Tools" || TOOLS_OK=false
check_tool "security" "security framework should be available" || TOOLS_OK=false
check_tool "hdiutil" "install Xcode Command Line Tools" || TOOLS_OK=false

if [ "$TOOLS_OK" = "false" ]; then
    echo "❌ Some required macOS tools are missing"
    echo "📋 Please install Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

echo "✅ All required macOS tools verified"

# Show tool versions
echo ""
echo "🔧 Tool versions:"
codesign --version || echo "codesign version not available"
echo "pkgbuild available: $(pkgbuild --version 2>/dev/null || echo 'yes')"
xcrun --version || echo "xcrun version not available"
echo "hdiutil available: yes"

# Performance info for M3 Max
if [ "${IS_M3_MAX:-false}" = "true" ]; then
    echo ""
    echo "🚀 M3 Max Performance Info:"
    echo "  CPU cores: ${CPU_CORES:-unknown}"
    echo "  Memory: $(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024) "GB"}' 2>/dev/null || echo 'unknown')"
    echo "  GPU cores: $(system_profiler SPDisplaysDataType | grep -i "Total Number of Cores" | head -1 | awk -F': ' '{print $2}' 2>/dev/null || echo 'unknown')"
fi

echo ""
echo "✅ Python environment and macOS tools setup complete"
