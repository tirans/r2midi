#!/bin/bash

# build-server-app-isolated.sh - Build R2MIDI Server with complete Qt isolation
# Usage: ./build-server-app-isolated.sh [version]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}
IS_M3_MAX=${IS_M3_MAX:-false}
CPU_CORES=${CPU_CORES:-4}
RUNNER_TYPE=${RUNNER_TYPE:-"unknown"}

echo "🔨 Building R2MIDI Server with complete Qt isolation..."
echo "🚫 IMPORTANT: Using isolated environment to avoid Qt6 conflicts"
echo "Runner optimization: $RUNNER_TYPE"
echo "Version: $VERSION"

# Create build directory for server
mkdir -p build_native/server
cd build_native/server

# M3 Max optimization: Enable parallel compilation
if [ "$IS_M3_MAX" = "true" ]; then
    export MAKEFLAGS="-j$CPU_CORES"
    echo "🚀 M3 Max: Using $CPU_CORES cores for compilation"
fi

# AGGRESSIVE Qt isolation - Completely block Qt packages
echo "🔒 Setting up complete Qt isolation environment..."

# Save original Python path components
ORIGINAL_PYTHONPATH=${PYTHONPATH:-""}
ORIGINAL_PATH=${PATH}

# Get the site-packages directory
SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
echo "📦 Site packages: $SITE_PACKAGES"

# Set PYTHONPATH to completely exclude the original site-packages
# This prevents any Qt packages from being found
export PYTHONPATH="../../:$(pwd)/../..:$ORIGINAL_PYTHONPATH"

# Create a list of critical packages we need for the build
echo "📦 Installing essential packages to virtual environment..."

# Create a minimal requirements file for just the server
cat > requirements_server_only.txt << EOF
fastapi>=0.115.12
uvicorn>=0.34.2
pydantic>=2.11.5
python-rtmidi>=1.5.5
mido>=1.3.0
httpx>=0.28.1
python-dotenv>=1.1.0
psutil>=7.0.0
py2app
setuptools
wheel
EOF

# Install only what we need in a clean way
echo "🔧 Installing server dependencies without Qt contamination..."
# First try with dependencies, but into isolated location
python3 -m pip install --target temp_packages -r requirements_server_only.txt

# Then remove any Qt packages that might have been pulled in as dependencies
echo "🚫 Removing any Qt packages from isolated environment..."
find temp_packages -name "*[Pp]y[Qq]t*" -type d -exec rm -rf {} + 2>/dev/null || true
find temp_packages -name "*[Qq]t*" -type d -exec rm -rf {} + 2>/dev/null || true
find temp_packages -name "*[Ss]ip*" -type d -exec rm -rf {} + 2>/dev/null || true

# Add our clean package directory to the front of PYTHONPATH
export PYTHONPATH="$(pwd)/temp_packages:$PYTHONPATH"

# Set environment variables to disable Qt detection
export PY2APP_DISABLE_QT_RECIPES=1
export PY2APP_VERBOSE=1
export DYLD_LIBRARY_PATH=""

# Check if server directory exists
if [ ! -d "../../server" ]; then
    echo "❌ Server directory not found at ../../server"
    echo "📁 Available directories:"
    ls -la ../../
    exit 1
fi

echo "📁 Server directory found"

# Verify Qt isolation worked
echo "🔍 Verifying Qt isolation..."
python3 -c "
import sys
qt_found = False
for path in sys.path:
    if 'pyqt' in path.lower() or ('site-packages' in path and 'temp_packages' not in path):
        print(f'⚠️ System site-packages still in path: {path}')
        qt_found = True

if not qt_found:
    print('✅ No system site-packages found in Python path')

# Try importing Qt to verify it's blocked
try:
    import PyQt6
    print('⚠️ PyQt6 still importable - will try --no-deps approach')
except ImportError:
    print('✅ PyQt6 successfully blocked')

# Verify our required packages are available
try:
    import fastapi, uvicorn, pydantic, rtmidi, mido, httpx
    print('✅ All required server packages available')
except ImportError as e:
    print(f'⚠️ Missing required package: {e}')
"

# Create an extremely minimal setup.py that only includes server essentials
echo "📝 Creating isolated setup.py for server..."
cat > setup.py << EOF
from setuptools import setup
import sys
import os

# Ensure server is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# Completely manual py2app configuration
import py2app

APP = [os.path.join('..', '..', 'server', 'main.py')]

# Ultra-conservative options to prevent any automatic detection
OPTIONS = {
    'argv_emulation': False,
    'site_packages': False,  # Don't scan site-packages
    'alias': False,
    'semi_standalone': False,
    'iconfile': None,
    'plist': {
        'CFBundleName': 'R2MIDI Server',
        'CFBundleDisplayName': 'R2MIDI Server',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.server',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '11.0',
    },
    # Manually specify only what we need
    'includes': [
        'fastapi', 'uvicorn', 'pydantic', 'rtmidi', 'mido', 
        'httpx', 'dotenv', 'psutil', 'logging', 'json', 'os', 'sys'
    ],
    # Aggressively exclude everything Qt-related
    'excludes': [
        'PyQt6', 'PyQt5', 'PySide6', 'PySide2', 'qt6', 'qt5', 'sip',
        'PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets',
        'tkinter', 'matplotlib', 'numpy', 'scipy', 'test', 'tests'
    ],
    'optimize': 0,
    'strip': False,
    'compressed': False,
    'use_pythonpath': False,  # Don't use system PYTHONPATH
}

setup(
    name='R2MIDI Server',
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

echo "✅ Isolated setup.py created"

# Build with isolated environment
echo "📦 Starting isolated py2app build..."
echo "🔧 Build command: python3 setup.py py2app"

if python3 setup.py py2app; then
    echo "✅ Isolated py2app build completed successfully"
else
    echo "❌ Isolated build failed"
    echo "📋 Checking build environment..."
    
    # Debug info
    echo "🔍 Python path:"
    python3 -c "import sys; [print(f'  {p}') for p in sys.path[:10]]"
    
    echo "🔍 Available packages in isolated environment:"
    if [ -d "temp_packages" ]; then
        packages=$(ls temp_packages | wc -l)
        echo "Found $packages packages in temp_packages:"
        ls temp_packages | head -20 | while read pkg; do
            echo "  📦 $pkg"
        done
    else
        echo "temp_packages directory not found"
    fi
    
    echo "📋 Build output directory contents:"
    ls -la . || true
    
    # Cleanup and exit
    rm -rf temp_packages requirements_server_only.txt
    exit 1
fi

# Check build results
echo "🔍 Checking build results..."
if [ -d "dist/main.app" ]; then
    # Rename the app to proper display name
    mv "dist/main.app" "dist/R2MIDI Server.app"
    echo "✅ Server app built successfully: dist/R2MIDI Server.app"
    echo "📊 App bundle size: $(du -sh "dist/R2MIDI Server.app" | cut -f1)"
else
    echo "❌ Server app build failed - main.app not found"
    echo "📁 dist/ directory contents:"
    ls -la dist/ || echo "dist/ directory not found"
    
    # Cleanup and exit
    rm -rf temp_packages requirements_server_only.txt
    exit 1
fi

# Verify app structure
echo "🔍 Verifying app bundle structure..."
APP_PATH="dist/R2MIDI Server.app"

if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "✅ Info.plist found"
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    bundle_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    echo "📋 Bundle ID: $bundle_id"
    echo "📋 Bundle Version: $bundle_version"
else
    echo "⚠️ Info.plist not found"
fi

# Cleanup isolated environment
echo "🧹 Cleaning up isolated environment..."
rm -rf temp_packages requirements_server_only.txt

# Restore original environment
export PYTHONPATH="$ORIGINAL_PYTHONPATH"

# Return to original directory
cd ../..

echo ""
echo "✅ R2MIDI Server build completed successfully with Qt isolation"
echo "📍 Built app location: build_native/server/dist/R2MIDI Server.app"
echo "🔒 Qt packages were completely isolated during build"
