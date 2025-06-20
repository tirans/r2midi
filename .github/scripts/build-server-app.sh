#!/bin/bash

# build-server-app.sh - Build R2MIDI Server with py2app
# Usage: ./build-server-app.sh [version]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}
IS_M3_MAX=${IS_M3_MAX:-false}
CPU_CORES=${CPU_CORES:-4}
RUNNER_TYPE=${RUNNER_TYPE:-"unknown"}

echo "🔨 Building R2MIDI Server with py2app (bypassing Briefcase)..."
echo "🚫 IMPORTANT: Not using Briefcase - using native py2app"
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

# Disable Qt-related recipes to prevent conflicts
export PY2APP_DISABLE_QT_RECIPES=1
export DYLD_LIBRARY_PATH=""
# Additional environment variables to prevent Qt detection
export QT_API=""
export PYQT_VERSION=""
# Tell py2app to ignore Qt packages completely
export PY2APP_IGNORE_PACKAGES="PyQt6,PyQt5,PySide6,PySide2,qt6,qt5,sip"

# Check if server directory exists
if [ ! -d "../../server" ]; then
    echo "❌ Server directory not found at ../../server"
    echo "📁 Available directories:"
    ls -la ../../
    exit 1
fi

echo "📁 Server directory found"
echo "🔍 Server directory contents:"
ls -la ../../server/

# Create setup.py for server using py2app
echo "📝 Creating setup.py for server..."
cat > setup.py << EOF
from setuptools import setup
import py2app
import sys
import os

# Add the server directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'server'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# Disable Qt recipes explicitly
os.environ['PY2APP_DISABLE_QT_RECIPES'] = '1'
os.environ['QT_API'] = ''
os.environ['PYQT_VERSION'] = ''

# Import py2app and patch the recipe system to disable Qt recipes
try:
    import py2app.recipes.qt6
    # Monkey patch the qt6 recipe to always return False
    original_check = py2app.recipes.qt6.check
    def disabled_qt6_check(*args, **kwargs):
        return False
    py2app.recipes.qt6.check = disabled_qt6_check
except (ImportError, AttributeError):
    pass  # Qt6 recipe not available or already disabled

try:
    import py2app.recipes.qt5
    # Also disable qt5 recipe
    original_check = py2app.recipes.qt5.check
    def disabled_qt5_check(*args, **kwargs):
        return False
    py2app.recipes.qt5.check = disabled_qt5_check
except (ImportError, AttributeError):
    pass  # Qt5 recipe not available or already disabled

APP = [os.path.join('..', '..', 'server', 'main.py')]
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
        'CFBundleName': 'R2MIDI Server',
        'CFBundleDisplayName': 'R2MIDI Server',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.server',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '11.0',
        'LSApplicationCategoryType': 'public.app-category.utilities',
    },
    # Only include server dependencies, nothing else
    'packages': ['fastapi', 'uvicorn', 'pydantic', 'rtmidi', 'mido', 'httpx', 'dotenv', 'psutil'],
    'includes': [
        'server.main', 'server.api', 'server.models', 'server.utils',
        'server.device_manager', 'server.git_operations', 'server.midi_utils', 'server.version'
    ],
    # Aggressively exclude all GUI and Qt packages
    'excludes': [
        # Qt packages
        'PyQt6', 'PyQt5', 'PySide6', 'PySide2', 'qt6', 'qt5', 'sip',
        'PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets', 'PyQt6.sip',
        'PyQt5.QtCore', 'PyQt5.QtGui', 'PyQt5.QtWidgets', 'PyQt5.sip',
        # Other GUI frameworks
        'tkinter', 'matplotlib', 'numpy', 'scipy', 'pandas', 'jupyter', 'notebook',
        'wx', 'gtk', 'kivy', 'pygame', 'pyglet',
        # Test frameworks
        'test', 'tests', 'unittest', 'pytest', 'doctest',
        # Development tools
        'setuptools', 'pip', 'wheel', 'distutils'
    ],
    'strip': False,
    'optimize': 0,
    'no_strip': True,
    'semi_standalone': False,
    'recipe_path': [],  # Disable recipe path to avoid Qt6 recipe
    'graph': True,
    'debug_modulegraph': False,
    # Prevent automatic dependency scanning that finds Qt
    'site_packages': True,  # Still need to find our dependencies
    'alias': False,
    'use_pythonpath': True,  # Need this to find server modules
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

echo "✅ setup.py created for server"

# Build server with py2app (NOT Briefcase)
echo "📦 Starting py2app build for server (bypassing Briefcase)..."
echo "🔧 Build command: python3 setup.py py2app"

if python3 setup.py py2app; then
    echo "✅ py2app build completed successfully"
else
    echo "⚠️ py2app build failed, trying minimal build approach..."
    
    # Create a minimal setup.py without automatic dependency detection
    cat > setup_minimal.py << EOF
from setuptools import setup
import py2app
import sys
import os

# Disable all automatic recipes
os.environ['PY2APP_DISABLE_QT_RECIPES'] = '1'
os.environ['PY2APP_VERBOSE'] = '1'

APP = [os.path.join('..', '..', 'server', 'main.py')]

OPTIONS = {
    'argv_emulation': False,
    'includes': [
        'fastapi', 'uvicorn', 'pydantic', 'rtmidi', 'mido', 'httpx', 'dotenv', 'psutil',
        'server.main', 'server.device_manager', 'server.git_operations', 'server.midi_utils', 
        'server.models', 'server.version'
    ],
    'excludes': [
        'PyQt6', 'PyQt5', 'PySide6', 'PySide2', 'qt6', 'qt5', 'sip',
        'tkinter', 'matplotlib', 'numpy', 'scipy', 'wx', 'gtk'
    ],
    'plist': {
        'CFBundleName': 'R2MIDI Server',
        'CFBundleDisplayName': 'R2MIDI Server',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.server',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
    },
    'optimize': 0,
    'compressed': False,
    'use_pythonpath': True,
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
        echo "⚠️ Minimal build also failed, trying manual inclusion approach..."
        
        # Create a completely manual setup that only includes what we explicitly want
        cat > setup_manual.py << 'MANUAL_EOF'
from setuptools import setup
import py2app
import sys
import os

# Disable automatic recipes
os.environ['PY2APP_DISABLE_QT_RECIPES'] = '1'

APP = [os.path.join('..', '..', 'server', 'main.py')]

# Simple, reliable py2app options 
OPTIONS = {
    'argv_emulation': False,
    'includes': [
        'fastapi', 'uvicorn', 'pydantic', 'rtmidi', 'mido', 
        'httpx', 'dotenv', 'psutil', 'json', 'os', 'sys', 'logging',
        'server.main', 'server.device_manager', 'server.git_operations', 
        'server.midi_utils', 'server.models', 'server.version'
    ],
    'excludes': [
        'PyQt6', 'PyQt5', 'PySide6', 'PySide2', 'qt6', 'qt5', 'sip',
        'tkinter', 'matplotlib', 'numpy', 'scipy', 'wx', 'gtk', 'test'
    ],
    'plist': {
        'CFBundleName': 'R2MIDI Server',
        'CFBundleDisplayName': 'R2MIDI Server',
        'CFBundleIdentifier': 'com.tirans.m2midi.r2midi.server',
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
MANUAL_EOF
        
        echo "🔧 Trying manual inclusion build..."
        if python3 setup_manual.py py2app; then
            echo "✅ Manual inclusion build completed successfully"
        else
            echo "❌ All py2app build approaches failed for server"
            echo "📋 Build output directory contents:"
            ls -la . || true
            echo "🔍 Python path and server module check:"
            python3 -c "import sys; print('Python path:'); [print(f'  {p}') for p in sys.path[:5]]; print('\nServer module check:'); import os; print(f'Server dir exists: {os.path.exists(\"../../server\")}')"
            exit 1
        fi
    fi
fi

# Check build results
echo "🔍 Checking build results..."

# py2app might create the app with the correct name directly or as main.app
APP_CREATED=""
if [ -d "dist/R2MIDI Server.app" ]; then
    APP_CREATED="dist/R2MIDI Server.app"
    echo "✅ Server app already has correct name: $APP_CREATED"
elif [ -d "dist/main.app" ]; then
    # Rename the app to proper display name
    mv "dist/main.app" "dist/R2MIDI Server.app"
    APP_CREATED="dist/R2MIDI Server.app"
    echo "✅ Server app renamed from main.app: $APP_CREATED"
else
    echo "❌ Server app build failed - no app bundle found"
    echo "📁 dist/ directory contents:"
    ls -la dist/ || echo "dist/ directory not found"
    exit 1
fi

echo "📊 App bundle size: $(du -sh "$APP_CREATED" | cut -f1)"

# Verify app structure
echo "🔍 Verifying app bundle structure..."
APP_PATH="dist/R2MIDI Server.app"

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
echo "✅ R2MIDI Server build completed successfully"
echo "📍 Built app location: build_native/server/dist/R2MIDI Server.app"
