#!/bin/bash
set -euo pipefail

# Build R2MIDI Client App with py2app (NOT Briefcase)
# Usage: build-native-client-app.sh [version]

VERSION="${1:-${APP_VERSION:-1.0.0}}"

echo "🔨 Building R2MIDI Client with py2app (bypassing Briefcase)..."
echo "🚫 IMPORTANT: Not using Briefcase - using native py2app"
echo "Runner optimization: ${RUNNER_TYPE:-unknown}"

# Create build directory for client
mkdir -p build_native/client
cd build_native/client

# M3 Max optimization: Enable parallel compilation
if [ "${IS_M3_MAX:-false}" = "true" ]; then
    export MAKEFLAGS="-j${CPU_CORES:-8}"
    echo "🚀 M3 Max: Using ${CPU_CORES:-8} cores for compilation"
fi

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

# Build client with py2app (NOT Briefcase)
echo "📦 Starting py2app build for client (bypassing Briefcase)..."
python3 setup.py py2app

if [ $? -ne 0 ]; then
    echo "❌ py2app build failed for client"
    exit 1
fi

# Rename the app to proper display name
if [ -d "dist/main.app" ]; then
    mv "dist/main.app" "dist/R2MIDI Client.app"
    echo "✅ Client app built successfully with py2app: dist/R2MIDI Client.app"
    ls -la "dist/R2MIDI Client.app"
else
    echo "❌ Client app build failed - main.app not found"
    ls -la dist/ || echo "dist/ directory not found"
    exit 1
fi

cd ../..

echo "✅ R2MIDI Client build complete"
