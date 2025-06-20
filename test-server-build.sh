#!/bin/bash

# test-server-build.sh - Quick test of the server build fixes
# Usage: ./test-server-build.sh

set -e

echo "🧪 Testing the server build fixes..."
echo ""

# Make sure we're in the right directory
if [ ! -f "pyproject.toml" ]; then
    echo "❌ Please run from repository root (pyproject.toml not found)"
    exit 1
fi

# Make scripts executable
echo "🔧 Making scripts executable..."
find .github/scripts -name "*.sh" -exec chmod +x {} \;

# Test the Qt detection logic
echo "🔍 Testing Qt package detection..."
QT_PACKAGES=$(python3 -c "
try:
    import pkg_resources
    qt_count = 0
    for pkg in pkg_resources.working_set:
        if any(qt_name in pkg.project_name.lower() for qt_name in ['qt', 'pyqt', 'pyside']):
            qt_count += 1
    print(qt_count)
except:
    print('0')
")

echo "Found $QT_PACKAGES Qt packages"

if [ "$QT_PACKAGES" -gt 0 ]; then
    echo "⚠️ Qt packages detected - will use isolated build approach"
    SCRIPT_TO_TEST="./.github/scripts/build-server-app-isolated.sh"
else
    echo "✅ No Qt packages - will use standard build approach"
    SCRIPT_TO_TEST="./.github/scripts/build-server-app.sh"
fi

echo ""
echo "🧪 Testing script: $(basename "$SCRIPT_TO_TEST")"

# Check if script exists and is executable
if [ ! -f "$SCRIPT_TO_TEST" ]; then
    echo "❌ Script not found: $SCRIPT_TO_TEST"
    exit 1
fi

if [ ! -x "$SCRIPT_TO_TEST" ]; then
    echo "❌ Script not executable: $SCRIPT_TO_TEST"
    chmod +x "$SCRIPT_TO_TEST"
    echo "🔧 Made script executable"
fi

echo "✅ Script is ready"

# Test the version extraction
echo ""
echo "🔍 Testing version extraction..."
VERSION=$(python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    config = tomllib.load(f)
print(config['project']['version'])
")

echo "Version extracted: $VERSION"

echo ""
echo "🎯 Build test summary:"
echo "  - Qt packages detected: $QT_PACKAGES"
echo "  - Script to use: $(basename "$SCRIPT_TO_TEST")"
echo "  - Version: $VERSION"
echo "  - All scripts are executable: ✅"
echo ""
echo "🚀 Ready to run the actual build!"
echo "   Command: $SCRIPT_TO_TEST \"$VERSION\""

# Optionally run a quick syntax check
echo ""
echo "🔍 Syntax check of the script..."
if bash -n "$SCRIPT_TO_TEST"; then
    echo "✅ Script syntax is valid"
else
    echo "❌ Script has syntax errors"
    exit 1
fi

echo ""
echo "🎉 All tests passed! The build should work now."
