#!/bin/bash
set -euo pipefail
# Install system dependencies for different platforms
# Usage: install-system-dependencies.sh <platform>

PLATFORM="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
echo "📦 Installing system dependencies for $PLATFORM..."

# Function to install Linux dependencies
install_linux_dependencies() {
    echo "🐧 Installing Linux system dependencies..."

    # Update package list
    sudo apt-get update

    # Install core development tools
    sudo apt-get install -y \
        build-essential \
        pkg-config \
        libffi-dev \
        libssl-dev

    # Install MIDI and audio libraries
    sudo apt-get install -y \
        libasound2-dev \
        portaudio19-dev \
        libjack-dev \
        librtmidi-dev

    # Install Qt6 and X11 libraries for GUI applications
    sudo apt-get install -y \
        libegl1 \
        libxkbcommon-x11-0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-xinerama0 \
        libxcb-xfixes0 \
        libfontconfig1-dev \
        libfreetype6-dev \
        libx11-dev \
        libx11-xcb-dev \
        libxext-dev \
        libxfixes-dev \
        libxi-dev \
        libxrender-dev \
        libxcb1-dev \
        libxcb-glx0-dev \
        libxcb-keysyms1-dev \
        libxcb-image0-dev \
        libxcb-shm0-dev \
        libxcb-util0-dev \
        libxcb-util-dev \
        libxkbcommon-dev \
        libxkbcommon-x11-dev \
        libxcb-cursor0 \
        libxcb-shape0

    # Install additional libraries for testing and runtime
    sudo apt-get install -y \
        libgl1-mesa-dri \
        libglib2.0-0 \
        xvfb

    echo "✅ Linux system dependencies installed successfully"
}

# Function to install macOS dependencies
install_macos_dependencies() {
    echo "🍎 Installing macOS system dependencies..."

    # Check if Homebrew is available
    if command -v brew >/dev/null 2>&1; then
        echo "🍺 Using Homebrew to install dependencies..."

        # Install create-dmg for better DMG creation
        if ! command -v create-dmg >/dev/null 2>&1; then
            brew install create-dmg
            echo "✅ Installed create-dmg"
        else
            echo "ℹ️ create-dmg already installed"
        fi

        # Install any other useful tools
        # Most macOS dependencies are already available with Xcode Command Line Tools
    else
        echo "ℹ️ Homebrew not found, skipping optional dependencies"
        echo "ℹ️ Most macOS dependencies are included with Xcode Command Line Tools"
    fi

    echo "✅ macOS system dependencies ready"
}

# Function to install Windows dependencies
install_windows_dependencies() {
    echo "🪟 Installing Windows system dependencies..."

    # Windows typically doesn't need additional system dependencies for Python/Qt
    # Most dependencies are handled by Python packages or are included with Windows

    echo "ℹ️ Windows doesn't require additional system dependencies"
    echo "ℹ️ All dependencies are handled by Python packages"

    echo "✅ Windows system dependencies ready"
}

# Platform detection and installation
case "$PLATFORM" in
    linux|ubuntu|debian)
        install_linux_dependencies
        ;;
    darwin|macos|osx)
        install_macos_dependencies
        ;;
    windows|win32|cygwin|mingw|msys)
        install_windows_dependencies
        ;;
    *)
        echo "⚠️ Warning: Unknown platform '$PLATFORM'"
        echo "Supported platforms: linux, macos, windows"
        echo "Skipping system dependency installation"
        ;;
esac

echo "✅ System dependencies installation complete for $PLATFORM"