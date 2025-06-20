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

# M3 Max optimization: Enable parallel compilation
if [ "$IS_M3_MAX" = "true" ]; then
    export MAKEFLAGS="-j$CPU_CORES"
    echo "🚀 M3 Max: Using $CPU_CORES cores for compilation"
fi

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
    'includes': ['r2midi_client.main', 'r2midi_client.ui', 'r2midi_client.models', 'r2midi_client.utils'],
    'excludes': ['tkinter', 'fastapi', 'uvicorn', 'rtmidi', 'mido', 'matplotlib', 'numpy', 'scipy'],
    'strip': False,
    'optimize': 0,
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

echo "✅ setup.py created for client"

# Build client with py2app (NOT Briefcase)
echo "📦 Starting py2app build for client (bypassing Briefcase)..."
echo "🔧 Build command: python3 setup.py py2app"

if python3 setup.py py2app; then
    echo "✅ py2app build completed successfully"
else
    echo "❌ py2app build failed for client"
    echo "📋 Build output directory contents:"
    ls -la . || true
    exit 1
fi

# Check build results
echo "🔍 Checking build results..."
if [ -d "dist/main.app" ]; then
    # Rename the app to proper display name
    mv "dist/main.app" "dist/R2MIDI Client.app"
    echo "✅ Client app built successfully with py2app: dist/R2MIDI Client.app"
    echo "📊 App bundle size: $(du -sh "dist/R2MIDI Client.app" | cut -f1)"
    echo "📁 App bundle contents:"
    ls -la "dist/R2MIDI Client.app"
else
    echo "❌ Client app build failed - main.app not found"
    echo "📁 dist/ directory contents:"
    ls -la dist/ || echo "dist/ directory not found"
    exit 1
fi

# Verify app structure
echo "🔍 Verifying app bundle structure..."
APP_PATH="dist/R2MIDI Client.app"

if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "✅ Info.plist found"
    echo "📋 Bundle info:"
    /usr/libexec/PlistBuddy -c "Print CFBundleName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "  Bundle name: unknown"
    /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "  Bundle version: unknown"
else
    echo "⚠️ Info.plist not found"
fi

if [ -d "$APP_PATH/Contents/MacOS" ]; then
    echo "✅ MacOS directory found"
    echo "📁 Executable files:"
    ls -la "$APP_PATH/Contents/MacOS/"
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

# Return to original directory
cd ../..

echo ""
echo "✅ R2MIDI Client build completed successfully"
echo "📍 Built app location: build_native/client/dist/R2MIDI Client.app"
