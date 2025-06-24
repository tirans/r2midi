#!/bin/bash
# detect-runner-environment.sh - Enhanced detection for GitHub-hosted vs self-hosted runners
set -euo pipefail

echo "🔍 Detecting runner environment..."

# Function to detect runner type with better self-hosted detection
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
    
    # Enhanced self-hosted runner detection
    if [ -n "${RUNNER_ENVIRONMENT:-}" ] && [ "$RUNNER_ENVIRONMENT" = "self-hosted" ]; then
        echo "✅ Detected self-hosted runner (RUNNER_ENVIRONMENT)"    
        export IS_SELF_HOSTED="true"
        export RUNNER_TYPE="self-hosted"
    elif [ -n "${RUNNER_NAME:-}" ] && [[ "$RUNNER_NAME" == *"self-hosted"* ]]; then
        echo "✅ Detected self-hosted runner (RUNNER_NAME)"    
        export IS_SELF_HOSTED="true"
        export RUNNER_TYPE="self-hosted"
    elif [ -d "/Users/runner/actions-runner" ] || [ -d "/home/runner/actions-runner" ]; then
        echo "✅ Detected GitHub-hosted runner (actions-runner directory)"
        export IS_SELF_HOSTED="false"
        export RUNNER_TYPE="github-hosted"
    elif [ -d "/Users/runner" ] && [ "$(whoami)" = "runner" ]; then
        echo "✅ Detected GitHub-hosted runner (runner user)"
        export IS_SELF_HOSTED="false"
        export RUNNER_TYPE="github-hosted"
    elif [ -d "/home/runner" ] && [ "$(whoami)" = "runner" ]; then
        echo "✅ Detected GitHub-hosted runner (runner user)"
        export IS_SELF_HOSTED="false"
        export RUNNER_TYPE="github-hosted"
    elif [ -n "${GITHUB_ACTIONS:-}" ]; then
        # In GitHub Actions but couldn't determine type - check more indicators
        if [ "$(whoami)" = "runner" ] || [ -n "${ACTIONS_RUNNER_DEBUG:-}" ]; then
            echo "⚠️ In GitHub Actions, likely GitHub-hosted"
            export IS_SELF_HOSTED="false"
            export RUNNER_TYPE="github-hosted-assumed"
        else
            echo "⚠️ In GitHub Actions, likely self-hosted"
            export IS_SELF_HOSTED="true"
            export RUNNER_TYPE="self-hosted-assumed"
        fi
    else
        echo "ℹ️ Not in GitHub Actions (local development)"
        export IS_SELF_HOSTED="true"
        export RUNNER_TYPE="local"
    fi
    
    # Additional checks for self-hosted runners
    if [ "$IS_SELF_HOSTED" = "true" ]; then
        echo "🏠 Self-hosted runner environment detected"
        
        # Check if this is a macOS self-hosted runner
        if [ "$(uname)" = "Darwin" ]; then
            echo "🍎 macOS self-hosted runner"
            
            # Check for typical self-hosted runner indicators
            if [ -d "/usr/local/Homebrew" ] || [ -d "/opt/homebrew" ]; then
                echo "   🍺 Homebrew detected"
            fi
            
            if [ -d "/Applications/Xcode.app" ]; then
                echo "   🔨 Xcode detected"
            fi
            
            # Check current user
            local current_user="$(whoami)"
            if [ "$current_user" != "runner" ]; then
                echo "   👤 Non-standard user: $current_user"
            fi
        fi
    else
        echo "☁️ GitHub-hosted runner environment detected"
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
            
            # Check Xcode version
            if [ -f "/Applications/Xcode.app/Contents/version.plist" ]; then
                local xcode_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" /Applications/Xcode.app/Contents/version.plist 2>/dev/null || echo "Unknown")
                echo "   Xcode version: $xcode_version"
            fi
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
        
        # Check productbuild/pkgbuild
        if command -v pkgbuild &>/dev/null; then
            echo "✅ pkgbuild available"
        else
            echo "❌ pkgbuild not found"
        fi
        
        if command -v productsign &>/dev/null; then
            echo "✅ productsign available"
        else
            echo "❌ productsign not found"
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
        
        # Check security command
        if command -v security &>/dev/null; then
            echo "✅ security command available"
            
            # Check for existing keychains that might interfere
            local keychain_count=$(security list-keychains -d user | grep -c "r2midi-" || echo "0")
            if [ "$keychain_count" -gt 0 ]; then
                echo "⚠️ Found $keychain_count existing r2midi keychains (will be cleaned up)"
            fi
        else
            echo "❌ security command not found"
        fi
    elif [ "$IS_SELF_HOSTED" = "false" ]; then
        echo "☁️ GitHub-hosted runner - dependencies managed by GitHub"
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
            echo "   🍺 Added Apple Silicon Homebrew to PATH"
        fi
        if [ -d "/usr/local/bin" ] && [ -f "/usr/local/bin/brew" ]; then
            export PATH="/usr/local/bin:$PATH"
            echo "   🍺 Added Intel Homebrew to PATH"
        fi
        
        # Add common Python paths
        if [ -d "/usr/local/opt/python@3.11/bin" ]; then
            export PATH="/usr/local/opt/python@3.11/bin:$PATH"
        fi
        if [ -d "/opt/homebrew/opt/python@3.11/bin" ]; then
            export PATH="/opt/homebrew/opt/python@3.11/bin:$PATH"
        fi
    fi
    
    # Set Python UTF-8 encoding
    export PYTHONIOENCODING=utf-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    # Disable Python bytecode generation
    export PYTHONDONTWRITEBYTECODE=1
    
    # Prevent macOS from creating extended attributes
    export COPYFILE_DISABLE=1
    export COPY_EXTENDED_ATTRIBUTES_DISABLE=1
    
    # Set build flags for universal binaries on Apple Silicon
    if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
        echo "🏗️ Detected Apple Silicon, configuring for universal binary support..."
        export ARCHFLAGS="-arch arm64 -arch x86_64"
    fi
    
    # Configure runner-specific settings
    if [ "$IS_SELF_HOSTED" = "true" ]; then
        echo "🏠 Configuring for self-hosted runner"
        # Allow longer timeouts for self-hosted runners
        export NOTARIZATION_TIMEOUT="60m"
        # Use more aggressive cleanup
        export AGGRESSIVE_CLEANUP="true"
    else
        echo "☁️ Configuring for GitHub-hosted runner"
        # Standard timeouts for GitHub-hosted runners
        export NOTARIZATION_TIMEOUT="30m"
        export AGGRESSIVE_CLEANUP="false"
    fi
}

# Function to detect specific capabilities
detect_capabilities() {
    echo "🔍 Detecting build capabilities..."
    
    local capabilities=()
    
    # Check code signing capability
    if command -v codesign &>/dev/null && command -v security &>/dev/null; then
        capabilities+=("codesign")
    fi
    
    # Check package building capability
    if command -v pkgbuild &>/dev/null && command -v productsign &>/dev/null; then
        capabilities+=("package")
    fi
    
    # Check notarization capability
    if xcrun --find notarytool &>/dev/null 2>&1; then
        capabilities+=("notarize")
    fi
    
    # Check Python app building capability
    if python3 -c "import py2app" 2>/dev/null; then
        capabilities+=("py2app")
    fi
    
    # Export capabilities
    local capabilities_str=$(IFS=','; echo "${capabilities[*]}")
    export BUILD_CAPABILITIES="$capabilities_str"
    
    if [ ${#capabilities[@]} -gt 0 ]; then
        echo "✅ Available capabilities: $capabilities_str"
    else
        echo "⚠️ No build capabilities detected"
    fi
}

# Main execution
detect_runner_type
check_dependencies
setup_environment
detect_capabilities

# Export all environment variables for use in other scripts
cat > .runner_environment << EOF
# Runner Environment Configuration
# Generated by detect-runner-environment.sh on $(date)

export IS_SELF_HOSTED='$IS_SELF_HOSTED'
export RUNNER_TYPE='$RUNNER_TYPE'
export BUILD_CAPABILITIES='$BUILD_CAPABILITIES'
export NOTARIZATION_TIMEOUT='${NOTARIZATION_TIMEOUT:-30m}'
export AGGRESSIVE_CLEANUP='${AGGRESSIVE_CLEANUP:-false}'

# Path configuration
export PATH='$PATH'

# Python configuration
export PYTHONIOENCODING='utf-8'
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'
export PYTHONDONTWRITEBYTECODE='1'

# macOS specific
export COPYFILE_DISABLE='1'
export COPY_EXTENDED_ATTRIBUTES_DISABLE='1'

# Architecture flags
$([ -n "${ARCHFLAGS:-}" ] && echo "export ARCHFLAGS='$ARCHFLAGS'" || echo "# No ARCHFLAGS set")
EOF

echo "✅ Runner environment detection complete"
echo "📋 Environment type: $RUNNER_TYPE"
echo "📋 Self-hosted: $IS_SELF_HOSTED"
echo "📋 Capabilities: ${BUILD_CAPABILITIES:-none}"
echo "📋 Configuration saved to .runner_environment"
