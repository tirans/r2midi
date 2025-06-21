#!/bin/bash

# build-client-app.sh - Build R2MIDI Client with py2app
# Usage: ./build-client-app.sh [version]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}
IS_M3_MAX=${IS_M3_MAX:-false}
CPU_CORES=${CPU_CORES:-4}
RUNNER_TYPE=${RUNNER_TYPE:-"unknown"}

echo "🔨 Building R2MIDI Client with py2app (bypassing Briefcase)..."
echo "🚫 IMPORTANT: Not using Briefcase - using native py2app"
echo "Runner optimization: $RUNNER_TYPE"
echo "Version: $VERSION"

# Create build directory for client
mkdir -p build_native/client
cd build_native/client

# Clean any existing build artifacts to prevent file collisions
echo "🧹 Cleaning existing build artifacts..."
rm -rf build dist *.app setup.py setup_*.py 2>/dev/null || true
echo "✅ Build directory cleaned"

# M3 Max optimization: Enable parallel compilation
if [ "$IS_M3_MAX" = "true" ]; then
    export MAKEFLAGS="-j$CPU_CORES"
    echo "🚀 M3 Max: Using $CPU_CORES cores for compilation"
fi

# Set environment variables to help with PyQt6 builds
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
echo "🔍 Client directory contents:"
ls -la ../../r2midi_client/

# Create setup.py for client using py2app
echo "📝 Creating setup.py for client..."
cat > setup.py << EOF
from setuptools import setup
import py2app
import sys
import os

# Add the client directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'r2midi_client'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

APP = [os.path.join('..', '..', 'r2midi_client', 'main.py')]
DATA_FILES = []

# Include any resource files
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
    'packages': ['PyQt6', 'httpx', 'pydantic', 'dotenv', 'psutil'],
    'includes': [
        'r2midi_client.main', 'r2midi_client.ui', 'r2midi_client.models', 'r2midi_client.utils'
    ],
    'excludes': [
        'tkinter', 'fastapi', 'uvicorn', 'rtmidi', 'mido', 
        'matplotlib', 'numpy', 'scipy', 'test', 'tests'
    ],
    'strip': False,
    'optimize': 0,
    'no_strip': True,
    'use_pythonpath': True,
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

echo "✅ setup.py created for client"

# Build client with py2app with multiple fallback strategies
echo "📦 Starting py2app build for client (bypassing Briefcase)..."
echo "🔧 Build command: python3 setup.py py2app"

if python3 setup.py py2app; then
    echo "✅ py2app build completed successfully"
else
    echo "⚠️ Primary build failed, cleaning and trying minimal approach..."
    
    # Clean build artifacts and try again
    rm -rf build dist 2>/dev/null || true
    
    # Create a minimal setup.py
    cat > setup_minimal.py << EOF
from setuptools import setup
import py2app
import sys
import os

APP = [os.path.join('..', '..', 'r2midi_client', 'main.py')]

OPTIONS = {
    'argv_emulation': False,
    'includes': ['PyQt6', 'PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets', 'httpx', 'pydantic'],
    'excludes': ['tkinter', 'test', 'tests', 'matplotlib', 'numpy'],
    'plist': {
        'CFBundleName': 'R2MIDI Client',
        'CFBundleDisplayName': 'R2MIDI Client',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.client',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
    },
    'optimize': 0,
    'strip': False,
}

setup(
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF
    
    echo "🔧 Trying minimal build..."
    if python3 setup_minimal.py py2app; then
        echo "✅ Minimal py2app build completed successfully"
    else
        echo "⚠️ Minimal build failed, trying ultra-simple approach..."
        
        # Final fallback - ultra simple
        rm -rf build dist 2>/dev/null || true
        
        cat > setup_simple.py << EOF
from setuptools import setup
import py2app

APP = [os.path.join('..', '..', 'r2midi_client', 'main.py')]

OPTIONS = {
    'argv_emulation': False,
    'plist': {
        'CFBundleName': 'R2MIDI Client',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.client',
        'CFBundleVersion': '$VERSION',
    }
}

setup(
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF
        
        echo "🔧 Trying ultra-simple build..."
        if python3 setup_simple.py py2app; then
            echo "✅ Ultra-simple py2app build completed successfully"
        else
            echo "❌ All py2app build approaches failed for client"
            echo "📋 Build output directory contents:"
            ls -la . || true
            echo "🔍 Checking for any partial builds..."
            if [ -d "build" ]; then
                echo "📁 Build directory contents:"
                find build -type f 2>/dev/null | head -10
            fi
            exit 1
        fi
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
    exit 1
fi

echo "📊 App bundle size: $(du -sh "$APP_CREATED" | cut -f1)"

# Verify app structure
echo "🔍 Verifying app bundle structure..."
APP_PATH="dist/R2MIDI Client.app"

if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "✅ Info.plist found"
    bundle_name=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    bundle_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    echo "📋 Bundle Name: $bundle_name"
    echo "📋 Bundle Version: $bundle_version"
else
    echo "⚠️ Info.plist not found"
fi

if [ -d "$APP_PATH/Contents/MacOS" ]; then
    echo "✅ MacOS directory found"
    executable_count=$(ls "$APP_PATH/Contents/MacOS/" | wc -l)
    echo "📁 Executable files: $executable_count"
else
    echo "❌ MacOS directory not found"
fi

if [ -d "$APP_PATH/Contents/Resources" ]; then
    echo "✅ Resources directory found"
    resource_count=$(ls "$APP_PATH/Contents/Resources" | wc -l)
    echo "📦 Resources count: $resource_count"
else
    echo "⚠️ Resources directory not found"
fi

# Check for PyQt6 integration
echo "🔍 Checking PyQt6 integration..."
if find "$APP_PATH" -name "*Qt*" -type d | head -3 | grep -q .; then
    echo "✅ PyQt6 components found in app bundle"
    qt_count=$(find "$APP_PATH" -name "*Qt*" -type d | wc -l)
    echo "📦 Qt components: $qt_count directories"
else
    echo "⚠️ PyQt6 components not found - app may not work properly"
fi

# Return to original directory
cd ../..

echo ""
echo "✅ R2MIDI Client build completed successfully"
echo "📍 Built app location: build_native/client/dist/R2MIDI Client.app"
echo "🎯 Ready for code signing and packaging"
