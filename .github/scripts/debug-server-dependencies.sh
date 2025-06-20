#!/bin/bash

# debug-server-dependencies.sh - Debug what's causing Qt6 recipe issues
# Usage: ./debug-server-dependencies.sh

set -euo pipefail

echo "🔍 Debugging server dependencies that might trigger Qt6 recipe..."
echo ""

# Check what modules are imported by the server
echo "📦 Checking server main.py imports..."
if [ -f "server/main.py" ]; then
    echo "Direct imports in server/main.py:"
    grep -E "^(import|from)" server/main.py | head -10
    echo ""
else
    echo "❌ server/main.py not found"
fi

# Check what's in the Python environment
echo "🐍 Checking installed packages that might include Qt..."
python3 -c "
import pkg_resources
qt_packages = []
for pkg in pkg_resources.working_set:
    if 'qt' in pkg.project_name.lower() or 'pyqt' in pkg.project_name.lower() or 'pyside' in pkg.project_name.lower():
        qt_packages.append(f'{pkg.project_name}: {pkg.version}')

if qt_packages:
    print('Found Qt-related packages:')
    for pkg in qt_packages:
        print(f'  📦 {pkg}')
else:
    print('✅ No Qt-related packages found')
"

echo ""

# Check if sip is available
echo "🔍 Checking for sip module..."
python3 -c "
try:
    import sip
    print('⚠️ sip module is available - this might trigger Qt6 recipe')
    print(f'   sip version: {sip.SIP_VERSION_STR if hasattr(sip, \"SIP_VERSION_STR\") else \"unknown\"}')
except ImportError:
    print('✅ sip module not found - good for server build')
"

echo ""

# Check modulegraph behavior
echo "🔍 Testing modulegraph detection..."
python3 -c "
import sys
sys.path.insert(0, 'server')

try:
    from modulegraph import modulegraph
    mf = modulegraph.ModuleGraph()
    
    # Try to find what triggers Qt detection
    try:
        mf.run_script('server/main.py')
        
        # Check for Qt-related modules
        qt_modules = []
        for name, module in mf.modules.items():
            if any(qt_name in name.lower() for qt_name in ['qt', 'sip', 'pyqt', 'pyside']):
                qt_modules.append(name)
        
        if qt_modules:
            print('⚠️ Qt-related modules detected by modulegraph:')
            for mod in qt_modules[:10]:  # Show first 10
                print(f'  📦 {mod}')
        else:
            print('✅ No Qt-related modules detected by modulegraph')
            
    except Exception as e:
        print(f'⚠️ Error running modulegraph: {e}')
        
except ImportError:
    print('📦 modulegraph not available for testing')
"

echo ""

# Check py2app recipes
echo "🔍 Checking py2app recipes directory..."
python3 -c "
import py2app
import os

recipes_dir = os.path.join(os.path.dirname(py2app.__file__), 'recipes')
if os.path.exists(recipes_dir):
    recipes = [f for f in os.listdir(recipes_dir) if f.endswith('.py') and 'qt' in f.lower()]
    print(f'Qt-related recipes found: {recipes}')
    
    # Check qt6.py recipe
    qt6_recipe = os.path.join(recipes_dir, 'qt6.py')
    if os.path.exists(qt6_recipe):
        print(f'📄 Qt6 recipe exists at: {qt6_recipe}')
        print('   This recipe will trigger if any Qt6 is detected')
    else:
        print('✅ No qt6.py recipe found')
else:
    print('⚠️ py2app recipes directory not found')
"

echo ""
echo "🎯 Summary: This debug info helps identify what's triggering the Qt6 recipe"
echo "   The goal is to ensure no Qt-related modules are detected for the server build"
