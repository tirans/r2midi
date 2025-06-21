#!/bin/bash

# build-client-app-isolated.sh - Build R2MIDI Client with dependency isolation
# Usage: ./build-client-app-isolated.sh [version]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}
IS_M3_MAX=${IS_M3_MAX:-false}
CPU_CORES=${CPU_CORES:-4}
RUNNER_TYPE=${RUNNER_TYPE:-"unknown"}

echo "🔨 Building R2MIDI Client with dependency isolation..."
echo "🚫 IMPORTANT: Using isolated environment to avoid dependency conflicts"
echo "Runner optimization: $RUNNER_TYPE"
echo "Version: $VERSION"

# Create build directory for client
mkdir -p build_native/client
cd build_native/client

# Clean any existing build artifacts completely
echo "🧹 Thoroughly cleaning build environment..."
rm -rf build dist *.app setup*.py temp_packages requirements_client_only.txt 2>/dev/null || true
echo "✅ Build environment cleaned"

# M3 Max optimization: Enable parallel compilation
if [ "$IS_M3_MAX" = "true" ]; then
    export MAKEFLAGS="-j$CPU_CORES"
    echo "🚀 M3 Max: Using $CPU_CORES cores for compilation"
fi

# Set up isolated environment for client dependencies
echo "🔒 Setting up client dependency isolation..."

# Save original Python path
ORIGINAL_PYTHONPATH=${PYTHONPATH:-""}

# Create isolated requirements for client
cat > requirements_client_only.txt << EOF
PyQt6>=6.9.0
httpx>=0.28.1
python-dotenv>=1.1.0
pydantic>=2.11.5
psutil>=7.0.0
py2app
setuptools
wheel
EOF

# Install client dependencies in isolation
echo "🔧 Installing client dependencies in isolation..."
python3 -m pip install --target temp_packages -r requirements_client_only.txt

# Set clean Python path with isolated packages
export PYTHONPATH="$(pwd)/temp_packages:$(pwd)/../../r2midi_client:../../:$ORIGINAL_PYTHONPATH"

# Set environment variables for Qt
export QT_QPA_PLATFORM_PLUGIN_PATH=""
export DYLD_LIBRARY_PATH=""

# Check if client directory exists
if [ ! -d "../../r2midi_client" ]; then
    echo "❌ Client directory not found at ../../r2midi_client"
    echo "📁 Available directories:"
    ls -la ../../
    exit 1
fi

echo "📁 Client directory found"

# Verify isolated environment
echo "🔍 Verifying isolated environment..."
python3 -c "
import sys
print('✅ Python path configured')
try:
    import PyQt6
    print('✅ PyQt6 available in isolated environment')
except ImportError as e:
    print(f'❌ PyQt6 not available: {e}')
    exit(1)

try:
    import httpx, pydantic, psutil
    print('✅ Client dependencies available')
except ImportError as e:
    print(f'❌ Missing client dependency: {e}')
    exit(1)
"

# Create isolated setup.py for client
echo "📝 Creating isolated setup.py for client..."
cat > setup.py << EOF
from setuptools import setup
import py2app
import sys
import os

# Ensure client is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'r2midi_client'))

APP = [os.path.join('..', '..', 'r2midi_client', 'main.py')]

# Include any resource files
DATA_FILES = []
resources_dir = os.path.join('..', '..', 'resources')
if os.path.exists(resources_dir):
    for f in os.listdir(resources_dir):
        if os.path.isfile(os.path.join(resources_dir, f)):
            DATA_FILES.append(os.path.join(resources_dir, f))

OPTIONS = {
    'argv_emulation': False,
    'iconfile': os.path.join('..', '..', 'resources', 'r2midi.icns') if os.path.exists(os.path.join('..', '..', 'resources', 'r2midi.icns')) else None,
    'plist': {
        'CFBundleName': 'R2MIDI Client',
        'CFBundleDisplayName': 'R2MIDI Client',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.client',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '11.0',
        'LSApplicationCategoryType': 'public.app-category.utilities',
    },
    # Include client dependencies and modules
    'includes': [
        'PyQt6', 'PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets',
        'httpx', 'pydantic', 'dotenv', 'psutil', 'json', 'os', 'sys',
        'r2midi_client', 'r2midi_client.main', 'r2midi_client.ui',
        'r2midi_client.models', 'r2midi_client.utils'
    ],
    # Exclude server and unnecessary packages
    'excludes': [
        'fastapi', 'uvicorn', 'rtmidi', 'mido',
        'tkinter', 'matplotlib', 'numpy', 'scipy', 'test', 'tests'
    ],
    'optimize': 0,
    'strip': False,
    'use_pythonpath': True,
}

setup(
    name='R2MIDI Client',
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

echo "✅ Isolated setup.py created"

# Build with isolated environment
echo "📦 Starting isolated py2app build for client..."
echo "🔧 Build command: python3 setup.py py2app"

if python3 setup.py py2app; then
    echo "✅ Isolated py2app build completed successfully"
else
    echo "⚠️ Isolated build failed, trying simplified approach..."
    
    # Clean and try simplified build
    rm -rf build dist 2>/dev/null || true
    
    cat > setup_simple.py << EOF
from setuptools import setup
import py2app
import sys
import os

APP = [os.path.join('..', '..', 'r2midi_client', 'main.py')]

OPTIONS = {
    'argv_emulation': False,
    'includes': ['PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets'],
    'plist': {
        'CFBundleName': 'R2MIDI Client',
        'CFBundleDisplayName': 'R2MIDI Client',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.client',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
    },
    'optimize': 0,
}

setup(
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF
    
    echo "🔧 Trying simplified isolated build..."
    if python3 setup_simple.py py2app; then
        echo "✅ Simplified isolated build completed successfully"
    else
        echo "❌ Isolated client build failed"
        echo "📋 Build environment debug:"
        echo "🔍 Python path:"
        python3 -c "import sys; [print(f'  {p}') for p in sys.path[:10]]"
        
        echo "🔍 Available packages in isolated environment:"
        if [ -d "temp_packages" ]; then
            packages=$(ls temp_packages | wc -l)
            echo "Found $packages packages in temp_packages:"
            ls temp_packages | head -10 | while read pkg; do
                echo "  📦 $pkg"
            done
        fi
        
        echo "📋 Build output directory contents:"
        ls -la . || true
        
        # Cleanup and exit
        rm -rf temp_packages requirements_client_only.txt
        exit 1
    fi
fi

# Check build results - handle both naming patterns
echo "🔍 Checking build results..."

APP_CREATED=""
if [ -d "dist/R2MIDI Client.app" ]; then
    APP_CREATED="dist/R2MIDI Client.app"
    echo "✅ Client app already has correct name: $APP_CREATED"
elif [ -d "dist/main.app" ]; then
    # Rename the app to proper display name
    mv "dist/main.app" "dist/R2MIDI Client.app"
    APP_CREATED="dist/R2MIDI Client.app"
    echo "✅ Client app renamed from main.app: $APP_CREATED"
else
    echo "❌ Client app build failed - no app bundle found"
    echo "📁 dist/ directory contents:"
    ls -la dist/ || echo "dist/ directory not found"
    
    # Cleanup and exit
    rm -rf temp_packages requirements_client_only.txt
    exit 1
fi

echo "📊 App bundle size: $(du -sh "$APP_CREATED" | cut -f1)"

# Verify app structure
echo "🔍 Verifying app bundle structure..."
APP_PATH="dist/R2MIDI Client.app"

if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "✅ Info.plist found"
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    bundle_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    echo "📋 Bundle ID: $bundle_id"
    echo "📋 Bundle Version: $bundle_version"
else
    echo "⚠️ Info.plist not found"
fi

# Check for PyQt6 integration
echo "🔍 Checking PyQt6 integration..."
if find "$APP_PATH" -name "*Qt*" -type d 2>/dev/null | head -3 | grep -q .; then
    echo "✅ PyQt6 components found in app bundle"
    qt_count=$(find "$APP_PATH" -name "*Qt*" -type d 2>/dev/null | wc -l)
    echo "📦 Qt components: $qt_count directories"
else
    echo "⚠️ PyQt6 components not found - checking for alternative Qt structure..."
    if find "$APP_PATH" -name "*qt*" -type f 2>/dev/null | head -3 | grep -q .; then
        echo "✅ Qt files found in alternative structure"
    else
        echo "⚠️ No Qt components detected - app may need additional dependencies"
    fi
fi

# Cleanup isolated environment
echo "🧹 Cleaning up isolated environment..."
rm -rf temp_packages requirements_client_only.txt

# Restore original environment
export PYTHONPATH="$ORIGINAL_PYTHONPATH"

# Return to original directory
cd ../..

echo ""
echo "✅ R2MIDI Client build completed successfully with isolation"
echo "📍 Built app location: build_native/client/dist/R2MIDI Client.app"
echo "🔒 Dependencies were isolated during build"
