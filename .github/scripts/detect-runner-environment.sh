#!/bin/bash
# detect-runner-environment.sh - Detect and configure for GitHub-hosted vs self-hosted runners
set -euo pipefail

echo "🔍 Detecting runner environment..."

# Function to detect runner type
detect_runner_type() {
    if [ -n "${RUNNER_NAME:-}" ]; then
        echo "📋 Runner name: $RUNNER_NAME"
    fi
    
    if [ -n "${RUNNER_OS:-}" ]; then
        echo "📋 Runner OS: $RUNNER_OS"
    fi
    
    if [ -n "${RUNNER_ARCH:-}" ]; then
        echo "📋 Runner architecture: $RUNNER_ARCH"
    fi
    
    # Check if we're on a self-hosted runner
    if [ -n "${RUNNER_ENVIRONMENT:-}" ] && [ "$RUNNER_ENVIRONMENT" = "self-hosted" ]; then
        echo "✅ Detected self-hosted runner"
        export IS_SELF_HOSTED="true"
    elif [ -d "/Users/runner" ] || [ -d "/home/runner" ]; then
        echo "✅ Detected GitHub-hosted runner"
        export IS_SELF_HOSTED="false"
    else
        # Assume self-hosted if we can't determine
        echo "⚠️ Could not determine runner type, assuming self-hosted"
        export IS_SELF_HOSTED="true"
    fi
}

# Function to check and install dependencies for self-hosted runners
check_dependencies() {
    if [ "$IS_SELF_HOSTED" = "true" ] && [ "$(uname)" = "Darwin" ]; then
        echo "🔍 Checking dependencies on self-hosted macOS runner..."
        
        # Check Xcode Command Line Tools
        if xcode-select -p &>/dev/null; then
            echo "✅ Xcode Command Line Tools installed"
            echo "   Path: $(xcode-select -p)"
        else
            echo "❌ Xcode Command Line Tools not installed"
            echo "   Run: xcode-select --install"
        fi
        
        # Check Python
        if command -v python3 &>/dev/null; then
            echo "✅ Python3 installed: $(python3 --version)"
        else
            echo "❌ Python3 not found"
        fi
        
        # Check for py2app
        if python3 -c "import py2app" 2>/dev/null; then
            echo "✅ py2app is available"
        else
            echo "⚠️ py2app not found in Python environment"
        fi
        
        # Check codesign
        if command -v codesign &>/dev/null; then
            echo "✅ codesign available"
        else
            echo "❌ codesign not found"
        fi
        
        # Check productbuild
        if command -v productbuild &>/dev/null; then
            echo "✅ productbuild available"
        else
            echo "❌ productbuild not found"
        fi
        
        # Check notarytool (requires Xcode 13+)
        if xcrun --find notarytool &>/dev/null 2>&1; then
            echo "✅ notarytool available"
            # Check notarytool version
            if xcrun notarytool --version &>/dev/null 2>&1; then
                xcrun notarytool --version | head -1
            fi
        else
            echo "⚠️ notarytool not found (requires Xcode 13+)"
        fi
    fi
}

# Function to setup environment variables
setup_environment() {
    echo "🔧 Setting up environment variables..."
    
    # For self-hosted runners, ensure PATH includes common tool locations
    if [ "$IS_SELF_HOSTED" = "true" ]; then
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        
        # Add Homebrew paths if available
        if [ -d "/opt/homebrew/bin" ]; then
            export PATH="/opt/homebrew/bin:$PATH"
        fi
        if [ -d "/usr/local/opt" ]; then
            export PATH="/usr/local/opt:$PATH"
        fi
    fi
    
    # Set Python UTF-8 encoding
    export PYTHONIOENCODING=utf-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    # Disable Python bytecode generation
    export PYTHONDONTWRITEBYTECODE=1
    
    # Set build flags for universal binaries on Apple Silicon
    if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
        echo "🏗️ Detected Apple Silicon, configuring for universal binary support..."
        export ARCHFLAGS="-arch arm64 -arch x86_64"
    fi
}

# Main execution
detect_runner_type
check_dependencies
setup_environment

# Export runner type for use in other scripts
echo "export IS_SELF_HOSTED='$IS_SELF_HOSTED'" > .runner_environment

echo "✅ Runner environment detection complete"
