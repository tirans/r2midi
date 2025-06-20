#!/bin/bash

# configure-build.sh - Determine build configuration and version
# Usage: ./configure-build.sh [event_name] [input_version] [input_build_type] [input_runner_type] [default_build_type]

set -euo pipefail

EVENT_NAME=${1:-"push"}
INPUT_VERSION=${2:-""}
INPUT_BUILD_TYPE=${3:-""}
INPUT_RUNNER_TYPE=${4:-"self-hosted"}
DEFAULT_BUILD_TYPE=${5:-"production"}  # Changed default to production

echo "🔧 Configuring build parameters..."

# Function to extract version from pyproject.toml with multiple fallbacks
extract_version() {
    echo "📋 Extracting version from pyproject.toml..." >&2
    
    # Method 1: Try tomllib (Python 3.11+)
    local version=$(python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    config = tomllib.load(f)
print(config['project']['version'])
" 2>/dev/null || echo "")
    
    if [ -n "$version" ] && [ "$version" != "" ]; then
        echo "✅ Version extracted with tomllib: $version" >&2
        echo "$version"  # Only output version to stdout
        return 0
    fi
    
    # Method 2: Try toml library fallback
    version=$(python3 -c "
import toml
with open('pyproject.toml', 'r') as f:
    config = toml.load(f)
print(config['project']['version'])
" 2>/dev/null || echo "")
    
    if [ -n "$version" ] && [ "$version" != "" ]; then
        echo "✅ Version extracted with toml: $version" >&2
        echo "$version"  # Only output version to stdout
        return 0
    fi
    
    # Method 3: Simple regex fallback
    version=$(grep -E '^version = ".*"' pyproject.toml | sed 's/version = "\(.*\)"/\1/' 2>/dev/null || echo "")
    
    if [ -n "$version" ] && [ "$version" != "" ]; then
        echo "✅ Version extracted with regex: $version" >&2
        echo "$version"  # Only output version to stdout
        return 0
    fi
    
    # Method 4: Default fallback
    echo "⚠️ Could not extract version from pyproject.toml, using default" >&2
    echo "0.1.0"  # Only output version to stdout
}

# Determine version and build type based on trigger
if [ "$EVENT_NAME" = "workflow_call" ]; then
    VERSION="$INPUT_VERSION"
    BUILD_TYPE="$INPUT_BUILD_TYPE"
elif [ "$EVENT_NAME" = "workflow_dispatch" ]; then
    # Extract version from pyproject.toml for manual dispatch
    VERSION=$(extract_version)
    BUILD_TYPE="$INPUT_BUILD_TYPE"
else
    # For push/PR triggers, extract version from pyproject.toml
    VERSION=$(extract_version)
    BUILD_TYPE="$DEFAULT_BUILD_TYPE"
fi

# Validate extracted version (clean up any extra whitespace)
VERSION=$(echo "$VERSION" | tr -d '\n' | tr -d '\r' | xargs)
if [ -z "$VERSION" ] || [ "$VERSION" = "" ]; then
    echo "⚠️ Warning: Could not extract version, using default"
    VERSION="0.1.0"
fi

# Set GitHub outputs if GITHUB_OUTPUT exists (in GitHub Actions)
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "version=$VERSION" >> "$GITHUB_OUTPUT"
    echo "build-type=$BUILD_TYPE" >> "$GITHUB_OUTPUT"
    echo "runner-type=$INPUT_RUNNER_TYPE" >> "$GITHUB_OUTPUT"
fi

# Export as environment variables for other scripts
{
    echo "VERSION=$VERSION"
    echo "BUILD_TYPE=$BUILD_TYPE"
    echo "RUNNER_TYPE=$INPUT_RUNNER_TYPE"
} >> "${GITHUB_ENV:-/dev/null}"

echo ""
echo "📋 Build Configuration Summary:"
echo "  Version: $VERSION"
echo "  Build Type: $BUILD_TYPE"
echo "  Runner: $INPUT_RUNNER_TYPE"
echo "  Trigger: $EVENT_NAME"
echo "  Default Build Type: $DEFAULT_BUILD_TYPE"
echo ""

# Output for scripts that source this
export VERSION BUILD_TYPE RUNNER_TYPE="$INPUT_RUNNER_TYPE"
