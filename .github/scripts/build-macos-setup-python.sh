#!/bin/bash

# build-macos-setup-python.sh - Setup Python environment for GitHub Actions
# Usage: ./build-macos-setup-python.sh RUNNER_TYPE

set -euo pipefail

RUNNER_TYPE="$1"

echo "🐍 Setting up Python environment..."
echo "Runner type: $RUNNER_TYPE"

# Function to check Python version
check_python_version() {
    local python_cmd="$1"
    if command -v "$python_cmd" >/dev/null 2>&1; then
        local version=$($python_cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        
        # Check if version is 3.10 or higher
        if [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; then
            echo "$python_cmd"
            return 0
        fi
    fi
    return 1
}

# Find suitable Python executable
PYTHON_EXE=""
echo "🔍 Searching for suitable Python executable..."

# Try different Python commands in order of preference
for py_cmd in python3.12 python3.11 python3.10 python3 python; do
    if PYTHON_EXE=$(check_python_version "$py_cmd"); then
        PYTHON_VERSION_FULL=$($PYTHON_EXE --version 2>&1)
        echo "✅ Found suitable Python: $PYTHON_EXE ($PYTHON_VERSION_FULL)"
        break
    fi
done

if [ -z "$PYTHON_EXE" ]; then
    echo "❌ No suitable Python executable found (requires Python 3.10+)"
    echo "Available Python versions:"
    for py_cmd in python3 python; do
        if command -v "$py_cmd" >/dev/null 2>&1; then
            echo "  $py_cmd: $($py_cmd --version 2>&1)"
        fi
    done
    exit 1
fi

# Export Python executable for other scripts
echo "PYTHON_EXE=$PYTHON_EXE" >> "$GITHUB_ENV"

# Update pip and essential packages
echo "⬆️ Updating pip and essential packages..."
$PYTHON_EXE -m pip install --upgrade pip setuptools wheel

# Install UV for faster package installation (if not already installed)
if ! command -v uv >/dev/null 2>&1; then
    echo "⚡ Installing UV for faster package management..."
    $PYTHON_EXE -m pip install uv
fi

# Verify installation
echo "🧪 Verifying Python setup..."
echo "  Python executable: $PYTHON_EXE"
echo "  Python version: $($PYTHON_EXE --version)"
echo "  Pip version: $($PYTHON_EXE -m pip --version)"

# Check if UV is available
if command -v uv >/dev/null 2>&1; then
    echo "  UV version: $(uv --version)"
    echo "UV_AVAILABLE=true" >> "$GITHUB_ENV"
else
    echo "  UV: Not available"
    echo "UV_AVAILABLE=false" >> "$GITHUB_ENV"
fi

# Platform-specific optimizations
if [ "$RUNNER_TYPE" = "self-hosted" ] && [ "$(uname -m)" = "arm64" ]; then
    echo "🚀 Applying Apple Silicon optimizations..."
    
    # Set environment variables for native compilation
    echo "ARCHFLAGS=-arch arm64" >> "$GITHUB_ENV"
    echo "_PYTHON_HOST_PLATFORM=macosx-11.0-arm64" >> "$GITHUB_ENV"
    
    # Check for Homebrew Python optimization
    if command -v brew >/dev/null 2>&1; then
        BREW_PYTHON=$(brew --prefix)/bin/python3
        if [ -x "$BREW_PYTHON" ]; then
            echo "  🍺 Homebrew Python available: $BREW_PYTHON"
        fi
    fi
fi

echo "✅ Python environment setup completed"
