#!/bin/bash

# build-macos-configure.sh - Configure build parameters for macOS workflow
# Usage: ./build-macos-configure.sh EVENT_NAME VERSION BUILD_TYPE BUILD_TARGET RUNNER_TYPE DEFAULT_BUILD_TYPE DEFAULT_BUILD_TARGET

set -euo pipefail

EVENT_NAME="$1"
INPUT_VERSION="$2"
INPUT_BUILD_TYPE="$3"
INPUT_BUILD_TARGET="$4"
RUNNER_TYPE="$5"
DEFAULT_BUILD_TYPE="$6"
DEFAULT_BUILD_TARGET="$7"

echo "🔧 Configuring build parameters..."

# Determine version
VERSION="$INPUT_VERSION"
if [ -z "$VERSION" ]; then
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "import sys; sys.path.insert(0, 'server'); from version import __version__; print(__version__)")
        echo "📋 Extracted version from code: $VERSION"
    else
        VERSION="1.0.0"
        echo "⚠️ Using fallback version: $VERSION"
    fi
else
    echo "📋 Using provided version: $VERSION"
fi

# Determine build type
BUILD_TYPE="$INPUT_BUILD_TYPE"
if [ -z "$BUILD_TYPE" ]; then
    BUILD_TYPE="$DEFAULT_BUILD_TYPE"
fi

# Determine build target
BUILD_TARGET="$INPUT_BUILD_TARGET"
if [ -z "$BUILD_TARGET" ]; then
    BUILD_TARGET="$DEFAULT_BUILD_TARGET"
fi

# Check if M3 Max self-hosted runner
IS_M3_MAX="false"
CPU_CORES="4"
if [ "$RUNNER_TYPE" = "self-hosted" ] && [ "$(uname -m)" = "arm64" ]; then
    if sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "M3 Max"; then
        IS_M3_MAX="true"
        CPU_CORES=$(sysctl -n hw.ncpu)
        echo "🚀 M3 Max detected with $CPU_CORES cores"
    fi
fi

# Validate build target
case "$BUILD_TARGET" in
    "client"|"server"|"both")
        echo "✅ Valid build target: $BUILD_TARGET"
        ;;
    *)
        echo "❌ Invalid build target: $BUILD_TARGET"
        echo "Valid options: client, server, both"
        exit 1
        ;;
esac

# Validate build type
case "$BUILD_TYPE" in
    "dev"|"staging"|"production")
        echo "✅ Valid build type: $BUILD_TYPE"
        ;;
    *)
        echo "❌ Invalid build type: $BUILD_TYPE"
        echo "Valid options: dev, staging, production"
        exit 1
        ;;
esac

# Export to GitHub outputs and environment
{
    echo "version=$VERSION"
    echo "build-type=$BUILD_TYPE"
    echo "build-target=$BUILD_TARGET"
    echo "runner-type=$RUNNER_TYPE"
    echo "is-m3-max=$IS_M3_MAX"
    echo "cpu-cores=$CPU_CORES"
} >> "$GITHUB_OUTPUT"

# Export to GitHub environment
{
    echo "VERSION=$VERSION"
    echo "BUILD_TYPE=$BUILD_TYPE"
    echo "BUILD_TARGET=$BUILD_TARGET"
    echo "RUNNER_TYPE=$RUNNER_TYPE"
    echo "IS_M3_MAX=$IS_M3_MAX"
    echo "CPU_CORES=$CPU_CORES"
} >> "$GITHUB_ENV"

echo ""
echo "✅ Build configuration completed:"
echo "  Version: $VERSION"
echo "  Build Type: $BUILD_TYPE"
echo "  Build Target: $BUILD_TARGET"
echo "  Runner: $RUNNER_TYPE"
echo "  M3 Max: $IS_M3_MAX"
echo "  CPU Cores: $CPU_CORES"
echo "  Event: $EVENT_NAME"
