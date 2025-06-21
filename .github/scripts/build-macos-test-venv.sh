#!/bin/bash

# build-macos-test-venv.sh - Test virtual environments for GitHub Actions
# Usage: ./build-macos-test-venv.sh

set -euo pipefail

echo "🧪 Testing virtual environments..."

# Use the main test script if available
if [ -f "./test_environments.sh" ]; then
    echo "📋 Using main test_environments.sh script..."
    ./test_environments.sh
else
    echo "⚠️ test_environments.sh not found, running manual tests..."
    
    # Manual testing if main script is missing
    test_failed=false
    
    # Test client environment
    if [ -d "venv_client" ]; then
        echo ""
        echo "🎨 Testing client environment..."
        
        if source venv_client/bin/activate; then
            echo "  ✅ Client environment activated"
            
            # Test Python version
            python_version=$(python --version)
            echo "  📍 Python version: $python_version"
            
            # Test critical imports
            if python -c "
import sys
print(f'  📦 Python path entries: {len(sys.path)}')

# Test PyQt6
try:
    import PyQt6
    import PyQt6.QtCore
    import PyQt6.QtGui
    import PyQt6.QtWidgets
    print('  ✅ PyQt6: Available')
except ImportError as e:
    print(f'  ❌ PyQt6: {e}')
    exit(1)

# Test HTTP client
try:
    import httpx
    print('  ✅ httpx: Available')
except ImportError as e:
    print(f'  ❌ httpx: {e}')
    exit(1)

# Test data validation
try:
    import pydantic
    print('  ✅ pydantic: Available')
except ImportError as e:
    print(f'  ❌ pydantic: {e}')
    exit(1)

# Test build tools
try:
    import py2app
    print('  ✅ py2app: Available')
except ImportError as e:
    print(f'  ❌ py2app: {e}')
    exit(1)

print('  🎉 All client dependencies verified')
"; then
                echo "  ✅ Client environment test passed"
            else
                echo "  ❌ Client environment test failed"
                test_failed=true
            fi
            
            deactivate
        else
            echo "  ❌ Failed to activate client environment"
            test_failed=true
        fi
    else
        echo "  ⏭️ Client environment not found (skipping)"
    fi
    
    # Test server environment
    if [ -d "venv_server" ]; then
        echo ""
        echo "🖥️ Testing server environment..."
        
        if source venv_server/bin/activate; then
            echo "  ✅ Server environment activated"
            
            # Test Python version
            python_version=$(python --version)
            echo "  📍 Python version: $python_version"
            
            # Test critical imports
            if python -c "
import sys
print(f'  📦 Python path entries: {len(sys.path)}')

# Test FastAPI
try:
    import fastapi
    print('  ✅ FastAPI: Available')
except ImportError as e:
    print(f'  ❌ FastAPI: {e}')
    exit(1)

# Test ASGI server
try:
    import uvicorn
    print('  ✅ uvicorn: Available')
except ImportError as e:
    print(f'  ❌ uvicorn: {e}')
    exit(1)

# Test MIDI processing
try:
    import rtmidi
    print('  ✅ rtmidi: Available')
except ImportError as e:
    print(f'  ❌ rtmidi: {e}')
    exit(1)

try:
    import mido
    print('  ✅ mido: Available')
except ImportError as e:
    print(f'  ❌ mido: {e}')
    exit(1)

# Test build tools
try:
    import py2app
    print('  ✅ py2app: Available')
except ImportError as e:
    print(f'  ❌ py2app: {e}')
    exit(1)

print('  🎉 All server dependencies verified')
"; then
                echo "  ✅ Server environment test passed"
            else
                echo "  ❌ Server environment test failed"
                test_failed=true
            fi
            
            deactivate
        else
            echo "  ❌ Failed to activate server environment"
            test_failed=true
        fi
    else
        echo "  ⏭️ Server environment not found (skipping)"
    fi
    
    # Overall result
    if [ "$test_failed" = "true" ]; then
        echo ""
        echo "❌ Virtual environment tests failed"
        exit 1
    fi
fi

echo ""
echo "✅ All virtual environment tests passed!"

# Export environment status for later steps
if [ -d "venv_client" ]; then
    echo "CLIENT_ENV_READY=true" >> "$GITHUB_ENV"
else
    echo "CLIENT_ENV_READY=false" >> "$GITHUB_ENV"
fi

if [ -d "venv_server" ]; then
    echo "SERVER_ENV_READY=true" >> "$GITHUB_ENV"
else
    echo "SERVER_ENV_READY=false" >> "$GITHUB_ENV"
fi
