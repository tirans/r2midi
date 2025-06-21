#!/bin/bash

# install-dependencies.sh - Install Python dependencies for native macOS build
# Usage: ./install-dependencies.sh

set -euo pipefail

echo "📦 Installing Python dependencies for native macOS build..."
echo "🔧 Using py2app instead of Briefcase"

# Get performance info from environment
IS_M3_MAX=${IS_M3_MAX:-false}
CPU_CORES=${CPU_CORES:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo "4")}
RUNNER_TYPE=${RUNNER_TYPE:-"unknown"}

echo "Runner: $RUNNER_TYPE"

if [ "$IS_M3_MAX" = "true" ]; then
    echo "🚀 M3 Max optimized dependency installation using $CPU_CORES cores..."
fi

# Function to install package with retry logic
install_package() {
    local package=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "📦 Installing $package (attempt $attempt/$max_attempts)..."
        
        if python3 -m pip install "$package"; then
            echo "✅ Successfully installed $package"
            return 0
        else
            echo "⚠️ Failed to install $package (attempt $attempt/$max_attempts)"
            if [ $attempt -eq $max_attempts ]; then
                echo "❌ Failed to install $package after $max_attempts attempts"
                return 1
            fi
            attempt=$((attempt + 1))
            sleep 2
        fi
    done
}

# Upgrade pip first
echo "🔧 Upgrading pip..."
python3 -m pip install --upgrade pip

# Install py2app - the native macOS app builder
echo "📦 Installing py2app (native macOS app builder)..."
install_package "py2app"

# Check if requirements files exist and install them
if [ -f "requirements.txt" ]; then
    echo "📦 Installing project requirements from requirements.txt..."
    python3 -m pip install -r requirements.txt
else
    echo "⚠️ requirements.txt not found, skipping"
fi

if [ -f "r2midi_client/requirements.txt" ]; then
    echo "📦 Installing client requirements from r2midi_client/requirements.txt..."
    python3 -m pip install -r r2midi_client/requirements.txt
else
    echo "⚠️ r2midi_client/requirements.txt not found, skipping"
fi

# Install additional packages that might not be in requirements
echo "📦 Installing additional packages for native build..."
ADDITIONAL_PACKAGES=(
    "setuptools"
    "wheel"
    "toml"  # For version extraction fallback
)

for package in "${ADDITIONAL_PACKAGES[@]}"; do
    install_package "$package"
done

# Verify key packages for native build
echo ""
echo "🔍 Verifying installed packages for native build..."

verify_package() {
    local package=$1
    local import_name=${2:-$package}
    
    if python3 -c "import $import_name; print(f'✅ $package: OK')" 2>/dev/null; then
        return 0
    else
        echo "❌ $package: Failed to import"
        return 1
    fi
}

# Critical packages check
VERIFICATION_OK=true

echo "📋 Checking critical packages..."

# Check py2app
if python3 -c "import py2app; print(f'✅ py2app: {py2app.__version__}')" 2>/dev/null; then
    true
else
    echo "❌ py2app: Not available"
    VERIFICATION_OK=false
fi

# Check server dependencies
echo "📋 Checking server dependencies..."
if verify_package "fastapi"; then true; else VERIFICATION_OK=false; fi
if verify_package "uvicorn"; then true; else VERIFICATION_OK=false; fi

# Check client dependencies  
echo "📋 Checking client dependencies..."
if verify_package "PyQt6"; then true; else VERIFICATION_OK=false; fi

# Check MIDI dependencies
echo "📋 Checking MIDI dependencies..."
if verify_package "python-rtmidi"; then true; else VERIFICATION_OK=false; fi

# Check common dependencies
echo "📋 Checking common dependencies..."
verify_package "pydantic" || VERIFICATION_OK=false
verify_package "httpx" || VERIFICATION_OK=false

if [ "$VERIFICATION_OK" = "false" ]; then
    echo ""
    echo "❌ Some critical packages failed verification"
    echo "📋 Installed packages list:"
    python3 -m pip list
    exit 1
fi

echo ""
echo "✅ All dependencies installed and verified for native macOS build"

# Show installed packages summary
echo ""
echo "📋 Key packages summary:"
python3 -c "
import sys
packages = ['py2app', 'fastapi', 'PyQt6', 'rtmidi', 'pydantic', 'httpx']
for pkg in packages:
    try:
        mod = __import__(pkg)
        version = getattr(mod, '__version__', 'unknown')
        print(f'  ✅ {pkg}: {version}')
    except ImportError:
        print(f'  ❌ {pkg}: Not available')
"

if [ "$IS_M3_MAX" = "true" ]; then
    echo ""
    echo "🚀 M3 Max: Dependencies installed with optimal performance"
fi
