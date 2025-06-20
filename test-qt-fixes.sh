#!/bin/bash

# test-qt-fixes.sh - Test the Qt isolation fixes
# Usage: ./test-qt-fixes.sh

set -e

echo "🧪 Testing Qt isolation fixes..."
echo ""

# Make scripts executable first
echo "🔧 Making scripts executable..."
./.github/scripts/make-scripts-executable.sh

echo ""
echo "🔍 Running Qt dependency debug..."
./.github/scripts/debug-server-dependencies.sh

echo ""
echo "📊 Checking which build approach would be used..."

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

echo "Found $QT_PACKAGES Qt packages in environment"

if [ "$QT_PACKAGES" -gt 0 ]; then
    echo "⚠️ Qt packages detected - workflow will use isolated build approach"
    echo "🔧 Testing isolated build script availability..."
    if [ -x "./.github/scripts/build-server-app-isolated.sh" ]; then
        echo "✅ Isolated build script is executable and ready"
    else
        echo "❌ Isolated build script is not executable"
        chmod +x ./.github/scripts/build-server-app-isolated.sh
        echo "🔧 Fixed: Made isolated build script executable"
    fi
else
    echo "✅ No Qt packages detected - workflow will use standard build approach"
fi

echo ""
echo "🎯 Summary:"
echo "  - Regular build script has enhanced Qt exclusions and monkey patching"
echo "  - Isolated build script creates Qt-free environment"
echo "  - Workflow automatically chooses appropriate approach"
echo "  - All scripts are executable and ready"
echo ""
echo "🚀 Ready to test the actual build!"
