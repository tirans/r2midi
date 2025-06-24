#!/bin/bash
set -euo pipefail
# Setup build environment for R2MIDI project
# Usage: setup-environment.sh

echo "🔧 Setting up R2MIDI build environment..."

# Function to detect operating system
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        CYGWIN*)    echo "windows";;
        MINGW*)     echo "windows";;
        MSYS*)      echo "windows";;
        *)          echo "unknown";;
    esac
}

# Function to detect if running in CI
detect_ci() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "github-actions"
    elif [ -n "${CI:-}" ]; then
        echo "ci"
    else
        echo "local"
    fi
}

# Function to setup environment variables
setup_environment_variables() {
    echo "📋 Setting up environment variables..."
    
    # Detect environment
    local os=$(detect_os)
    local ci_env=$(detect_ci)
    
    # Set basic environment variables
    export R2MIDI_OS="$os"
    export R2MIDI_CI_ENV="$ci_env"
    export R2MIDI_BUILD_ROOT="$(pwd)"
    
    # Set Python-related variables
    export PYTHONUNBUFFERED=1
    export PYTHONDONTWRITEBYTECODE=1
    
    # Set platform-specific variables
    case "$os" in
        "linux")
            export R2MIDI_PLATFORM="linux"
            export DISPLAY="${DISPLAY:-:99}"
            ;;
        "macos")
            export R2MIDI_PLATFORM="macos"
            ;;
        "windows")
            export R2MIDI_PLATFORM="windows"
            ;;
    esac
    
    # Set CI-specific variables
    if [ "$ci_env" != "local" ]; then
        export R2MIDI_CI_BUILD=true
        export R2MIDI_HEADLESS=true
    else
        export R2MIDI_CI_BUILD=false
        export R2MIDI_HEADLESS=false
    fi
    
    # Create environment file for other scripts
    cat > .build_env << EOF
# R2MIDI Build Environment
export R2MIDI_OS="$os"
export R2MIDI_CI_ENV="$ci_env"
export R2MIDI_PLATFORM="$R2MIDI_PLATFORM"
export R2MIDI_BUILD_ROOT="$R2MIDI_BUILD_ROOT"
export R2MIDI_CI_BUILD="$R2MIDI_CI_BUILD"
export R2MIDI_HEADLESS="$R2MIDI_HEADLESS"
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1
EOF
    
    if [ "$os" = "linux" ]; then
        echo "export DISPLAY=\"$DISPLAY\"" >> .build_env
    fi
    
    echo "✅ Environment variables set"
    echo "   OS: $os"
    echo "   CI Environment: $ci_env"
    echo "   Platform: $R2MIDI_PLATFORM"
    echo "   Build Root: $R2MIDI_BUILD_ROOT"
}

# Function to setup directories
setup_directories() {
    echo "📁 Setting up build directories..."
    
    # Create standard directories
    mkdir -p artifacts
    mkdir -p logs
    mkdir -p temp
    mkdir -p cache
    
    # Create platform-specific directories
    case "$R2MIDI_OS" in
        "linux")
            mkdir -p build/linux
            ;;
        "macos")
            mkdir -p build/macos
            ;;
        "windows")
            mkdir -p build/windows
            ;;
    esac
    
    echo "✅ Build directories created"
}

# Function to setup Python environment
setup_python_environment() {
    echo "🐍 Setting up Python environment..."
    
    # Check Python version
    if ! command -v python3 >/dev/null 2>&1; then
        echo "❌ Error: Python 3 is not installed"
        return 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2)
    echo "   Python version: $python_version"
    
    # Check pip
    if ! command -v pip3 >/dev/null 2>&1; then
        echo "❌ Error: pip3 is not installed"
        return 1
    fi
    
    local pip_version=$(pip3 --version | cut -d' ' -f2)
    echo "   Pip version: $pip_version"
    
    # Upgrade pip if in CI
    if [ "$R2MIDI_CI_BUILD" = true ]; then
        echo "   Upgrading pip..."
        python3 -m pip install --upgrade pip
    fi
    
    # Set Python path
    export PYTHONPATH="${PYTHONPATH:-}:$(pwd)"
    echo "export PYTHONPATH=\"$PYTHONPATH\"" >> .build_env
    
    echo "✅ Python environment ready"
}

# Function to setup Git environment
setup_git_environment() {
    echo "📝 Setting up Git environment..."
    
    if command -v git >/dev/null 2>&1; then
        # Get Git information
        local git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        local git_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        local git_dirty=$(git diff --quiet 2>/dev/null && echo "false" || echo "true")
        
        # Set Git environment variables
        export R2MIDI_GIT_COMMIT="$git_commit"
        export R2MIDI_GIT_BRANCH="$git_branch"
        export R2MIDI_GIT_DIRTY="$git_dirty"
        
        # Add to environment file
        cat >> .build_env << EOF
export R2MIDI_GIT_COMMIT="$git_commit"
export R2MIDI_GIT_BRANCH="$git_branch"
export R2MIDI_GIT_DIRTY="$git_dirty"
EOF
        
        echo "✅ Git environment set"
        echo "   Commit: ${git_commit:0:8}"
        echo "   Branch: $git_branch"
        echo "   Dirty: $git_dirty"
    else
        echo "⚠️ Git not available"
    fi
}

# Function to setup platform-specific environment
setup_platform_specific() {
    echo "🖥️ Setting up platform-specific environment..."
    
    case "$R2MIDI_OS" in
        "linux")
            setup_linux_environment
            ;;
        "macos")
            setup_macos_environment
            ;;
        "windows")
            setup_windows_environment
            ;;
        *)
            echo "⚠️ Unknown platform: $R2MIDI_OS"
            ;;
    esac
}

# Function to setup Linux-specific environment
setup_linux_environment() {
    echo "🐧 Setting up Linux environment..."
    
    # Setup display for headless environments
    if [ "$R2MIDI_HEADLESS" = true ]; then
        if command -v xvfb-run >/dev/null 2>&1; then
            echo "   Xvfb available for headless display"
            export R2MIDI_XVFB_AVAILABLE=true
        else
            echo "   Xvfb not available"
            export R2MIDI_XVFB_AVAILABLE=false
        fi
        echo "export R2MIDI_XVFB_AVAILABLE=\"$R2MIDI_XVFB_AVAILABLE\"" >> .build_env
    fi
    
    # Check for required libraries
    local missing_libs=()
    
    # Check for audio libraries
    if ! ldconfig -p | grep -q libasound; then
        missing_libs+=("libasound2-dev")
    fi
    
    if [ ${#missing_libs[@]} -gt 0 ]; then
        echo "⚠️ Missing libraries detected: ${missing_libs[*]}"
        echo "   These may be installed by the system dependencies script"
    fi
    
    echo "✅ Linux environment setup complete"
}

# Function to setup macOS-specific environment
setup_macos_environment() {
    echo "🍎 Setting up macOS environment..."
    
    # Check for Xcode Command Line Tools
    if xcode-select -p >/dev/null 2>&1; then
        local xcode_path=$(xcode-select -p)
        echo "   Xcode Command Line Tools: $xcode_path"
        export R2MIDI_XCODE_PATH="$xcode_path"
        echo "export R2MIDI_XCODE_PATH=\"$xcode_path\"" >> .build_env
    else
        echo "⚠️ Xcode Command Line Tools not found"
        export R2MIDI_XCODE_PATH=""
        echo "export R2MIDI_XCODE_PATH=\"\"" >> .build_env
    fi
    
    # Check for Homebrew
    if command -v brew >/dev/null 2>&1; then
        local brew_prefix=$(brew --prefix)
        echo "   Homebrew: $brew_prefix"
        export R2MIDI_BREW_PREFIX="$brew_prefix"
        echo "export R2MIDI_BREW_PREFIX=\"$brew_prefix\"" >> .build_env
    else
        echo "   Homebrew not found"
        export R2MIDI_BREW_PREFIX=""
        echo "export R2MIDI_BREW_PREFIX=\"\"" >> .build_env
    fi
    
    echo "✅ macOS environment setup complete"
}

# Function to setup Windows-specific environment
setup_windows_environment() {
    echo "🪟 Setting up Windows environment..."
    
    # Check for Visual Studio Build Tools
    if command -v cl >/dev/null 2>&1; then
        echo "   MSVC compiler available"
        export R2MIDI_MSVC_AVAILABLE=true
    else
        echo "   MSVC compiler not found"
        export R2MIDI_MSVC_AVAILABLE=false
    fi
    echo "export R2MIDI_MSVC_AVAILABLE=\"$R2MIDI_MSVC_AVAILABLE\"" >> .build_env
    
    # Check for PowerShell
    if command -v powershell >/dev/null 2>&1; then
        echo "   PowerShell available"
        export R2MIDI_POWERSHELL_AVAILABLE=true
    else
        echo "   PowerShell not found"
        export R2MIDI_POWERSHELL_AVAILABLE=false
    fi
    echo "export R2MIDI_POWERSHELL_AVAILABLE=\"$R2MIDI_POWERSHELL_AVAILABLE\"" >> .build_env
    
    echo "✅ Windows environment setup complete"
}

# Function to create environment summary
create_environment_summary() {
    echo "📋 Creating environment summary..."
    
    cat > environment_summary.txt << EOF
# R2MIDI Build Environment Summary
Generated: $(date)

## System Information
OS: $R2MIDI_OS
Platform: $R2MIDI_PLATFORM
CI Environment: $R2MIDI_CI_ENV
Build Root: $R2MIDI_BUILD_ROOT

## Python Information
Python: $(python3 --version 2>&1 || echo "Not available")
Pip: $(pip3 --version 2>&1 || echo "Not available")
Python Path: $PYTHONPATH

## Git Information
Commit: ${R2MIDI_GIT_COMMIT:-unknown}
Branch: ${R2MIDI_GIT_BRANCH:-unknown}
Dirty: ${R2MIDI_GIT_DIRTY:-unknown}

## Platform-Specific Information
EOF

    case "$R2MIDI_OS" in
        "linux")
            cat >> environment_summary.txt << EOF
Display: ${DISPLAY:-not set}
Xvfb Available: ${R2MIDI_XVFB_AVAILABLE:-false}
EOF
            ;;
        "macos")
            cat >> environment_summary.txt << EOF
Xcode Path: ${R2MIDI_XCODE_PATH:-not found}
Homebrew Prefix: ${R2MIDI_BREW_PREFIX:-not found}
EOF
            ;;
        "windows")
            cat >> environment_summary.txt << EOF
MSVC Available: ${R2MIDI_MSVC_AVAILABLE:-false}
PowerShell Available: ${R2MIDI_POWERSHELL_AVAILABLE:-false}
EOF
            ;;
    esac
    
    echo "✅ Environment summary created: environment_summary.txt"
}

# Main function
main() {
    echo "🚀 Starting environment setup..."
    
    # Setup different aspects of the environment
    setup_environment_variables
    setup_directories
    setup_python_environment
    setup_git_environment
    setup_platform_specific
    create_environment_summary
    
    echo ""
    echo "🎉 Environment setup completed successfully!"
    echo ""
    echo "📋 Environment files created:"
    echo "   - .build_env (source this in other scripts)"
    echo "   - environment_summary.txt (human-readable summary)"
    echo ""
    echo "To use this environment in other scripts:"
    echo "   source .build_env"
}

# Run main function
main "$@"