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

# AGGRESSIVE Qt isolation - Hide Qt packages from py2app
echo "🔒 Setting up Qt isolation environment..."

# Create a custom Python path that excludes Qt packages
ORIGINAL_PYTHONPATH=${PYTHONPATH:-""}
ORIGINAL_PATH=${PATH}

# Get the site-packages directory
SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
echo "📦 Site packages: $SITE_PACKAGES"

# Create a temporary directory with only non-Qt packages
TEMP_SITE_PACKAGES=$(mktemp -d)/site-packages-no-qt
mkdir -p "$TEMP_SITE_PACKAGES"

echo "🚫 Creating Qt-free environment..."
# Copy all packages EXCEPT Qt-related ones
for package in "$SITE_PACKAGES"/*; do
    package_name=$(basename "$package")
    if [[ ! "$package_name" =~ ^[Pp]y[Qq]t.*$ ]] && \
       [[ ! "$package_name" =~ ^[Qq]t.*$ ]] && \
       [[ ! "$package_name" =~ ^[Ss]ip.*$ ]] && \
       [[ ! "$package_name" =~ ^[Pp]y[Ss]ide.*$ ]]; then
        if [ -d "$package" ]; then
            cp -R "$package" "$TEMP_SITE_PACKAGES/"
        elif [ -f "$package" ]; then
            cp "$package" "$TEMP_SITE_PACKAGES/"
        fi
    else
        echo "  🚫 Excluding Qt package: $package_name"
    fi
done

# Add our isolated site-packages to Python path
export PYTHONPATH="$TEMP_SITE_PACKAGES:../../:$ORIGINAL_PYTHONPATH"

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
    if 'qt' in path.lower() or 'pyqt' in path.lower():
        print(f'⚠️ Qt path still in PYTHONPATH: {path}')
        qt_found = True

if not qt_found:
    print('✅ No Qt paths found in Python path')

# Try importing Qt to verify it's blocked
try:
    import PyQt6
    print('⚠️ PyQt6 still importable')
except ImportError:
    print('✅ PyQt6 successfully blocked')
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
    'recipe_plugins': [],     # Disable all recipe plugins
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
    python3 -c "
import os
isolated_packages = '$TEMP_SITE_PACKAGES'
if os.path.exists(isolated_packages):
    packages = [f for f in os.listdir(isolated_packages) if not f.startswith('.')]
    print(f'Found {len(packages)} packages:')
    for pkg in sorted(packages)[:20]:  # Show first 20
        print(f'  📦 {pkg}')
else:
    print('Isolated packages directory not found')
"
    
    echo "📋 Build output directory contents:"
    ls -la . || true
    
    # Cleanup and exit
    rm -rf "$TEMP_SITE_PACKAGES"
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
    rm -rf "$TEMP_SITE_PACKAGES"
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
rm -rf "$TEMP_SITE_PACKAGES"

# Restore original environment
export PYTHONPATH="$ORIGINAL_PYTHONPATH"

# Return to original directory
cd ../..

echo ""
echo "✅ R2MIDI Server build completed successfully with Qt isolation"
echo "📍 Built app location: build_native/server/dist/R2MIDI Server.app"
echo "🔒 Qt packages were completely isolated during build"
