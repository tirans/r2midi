#!/bin/bash
# test-setup.sh - Quick test of setup.py files
set -euo pipefail

echo "🧪 Testing setup.py files..."

# Test client setup.py
echo "📱 Testing client setup.py..."
cd build_client 2>/dev/null || { echo "❌ build_client directory not found"; exit 1; }

if [ -f setup.py ]; then
    echo "✅ Client setup.py exists"
    source ../venv_client/bin/activate
    if python setup.py --help-commands | grep -q py2app; then
        echo "✅ py2app command available"
    else
        echo "❌ py2app command not available"
        deactivate
        exit 1
    fi
    
    # Test that imports work
    if python -c "from setuptools import setup; print('✅ setuptools import OK')"; then
        echo "✅ Setup imports working"
    else
        echo "❌ Setup imports failed"
        deactivate
        exit 1
    fi
    deactivate
else
    echo "❌ Client setup.py not found"
    exit 1
fi

cd ..

echo "✅ Setup.py tests passed!"
