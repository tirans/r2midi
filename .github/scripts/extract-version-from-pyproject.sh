#!/bin/bash
set -euo pipefail

# Extract version from pyproject.toml with multiple fallback methods
# Usage: extract-version-from-pyproject.sh

echo "📋 Extracting version from pyproject.toml..."

# Function to extract version from pyproject.toml with multiple fallbacks
extract_version() {
    # Method 1: Try tomllib (Python 3.11+)
    local version=$(python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    config = tomllib.load(f)
print(config['project']['version'])
" 2>/dev/null)
    
    if [ -n "$version" ] && [ "$version" != "" ]; then
        echo "$version"
        return 0
    fi
    
    # Method 2: Try toml library fallback
    version=$(python3 -c "
import toml
with open('pyproject.toml', 'r') as f:
    config = toml.load(f)
print(config['project']['version'])
" 2>/dev/null)
    
    if [ -n "$version" ] && [ "$version" != "" ]; then
        echo "$version"
        return 0
    fi
    
    # Method 3: Simple regex fallback
    version=$(grep -E '^version = ".*"' pyproject.toml | sed 's/version = "\(.*\)"/\1/' 2>/dev/null)
    
    if [ -n "$version" ] && [ "$version" != "" ]; then
        echo "$version"
        return 0
    fi
    
    # Method 4: Default fallback
    echo "0.1.0"
}

# Extract version
VERSION=$(extract_version)

# Validate extracted version
if [ -z "$VERSION" ] || [ "$VERSION" = "" ]; then
    echo "⚠️ Warning: Could not extract version, using default"
    VERSION="0.1.0"
fi

echo "📋 Extracted version: $VERSION"

# Set outputs for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "version=$VERSION" >> "$GITHUB_OUTPUT"
    echo "app_version=$VERSION" >> "$GITHUB_OUTPUT"
fi

# Set environment variables
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "APP_VERSION=$VERSION" >> "$GITHUB_ENV"
fi

# Export for current session
export APP_VERSION="$VERSION"

echo "✅ Version extraction complete: $VERSION"
