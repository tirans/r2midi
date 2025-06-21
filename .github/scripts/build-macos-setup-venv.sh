#!/bin/bash

# build-macos-setup-venv.sh - Setup virtual environments for GitHub Actions
# Usage: ./build-macos-setup-venv.sh BUILD_TARGET

set -euo pipefail

BUILD_TARGET="$1"

echo "🚀 Setting up virtual environments for GitHub Actions..."
echo "Build target: $BUILD_TARGET"

# Use the main setup script if available
if [ -f "./setup-virtual-environments.sh" ]; then
    echo "📋 Using main setup-virtual-environments.sh script..."
    
    # Determine arguments based on build target
    case "$BUILD_TARGET" in
        "client")
            SETUP_ARGS="--client-only"
            ;;
        "server")
            SETUP_ARGS="--server-only"
            ;;
        "both")
            SETUP_ARGS=""
            ;;
        *)
            echo "❌ Invalid build target: $BUILD_TARGET"
            exit 1
            ;;
    esac
    
    # Add UV flag if available
    if [ "${UV_AVAILABLE:-false}" = "true" ]; then
        SETUP_ARGS="$SETUP_ARGS --use-uv"
    fi
    
    # Run the setup script
    ./setup-virtual-environments.sh $SETUP_ARGS
    
else
    echo "⚠️ setup-virtual-environments.sh not found, creating environments manually..."
    
    # Manual setup if main script is missing
    PYTHON_EXE="${PYTHON_EXE:-python3}"
    
    # Function to create virtual environment
    create_venv() {
        local env_name="$1"
        local packages="$2"
        
        echo "  🐍 Creating $env_name environment..."
        
        if [ -d "venv_$env_name" ]; then
            rm -rf "venv_$env_name"
        fi
        
        $PYTHON_EXE -m venv "venv_$env_name"
        source "venv_$env_name/bin/activate"
        
        python -m pip install --upgrade pip setuptools wheel py2app
        
        # Install packages
        if [ -n "$packages" ]; then
            python -m pip install $packages
        fi
        
        # Install from requirements if available
        local req_file=""
        case "$env_name" in
            "client")
                req_file="r2midi_client/requirements.txt"
                ;;
            "server")
                req_file="server/requirements.txt"
                ;;
        esac
        
        if [ -f "$req_file" ]; then
            echo "    📋 Installing from $req_file..."
            python -m pip install -r "$req_file"
        fi
        
        deactivate
        echo "  ✅ $env_name environment created"
    }
    
    # Create environments based on build target
    case "$BUILD_TARGET" in
        "client")
            create_venv "client" "PyQt6 PyQt6-Qt6 httpx pydantic python-dotenv psutil"
            ;;
        "server")
            create_venv "server" "fastapi uvicorn rtmidi mido python-multipart aiofiles"
            ;;
        "both")
            create_venv "client" "PyQt6 PyQt6-Qt6 httpx pydantic python-dotenv psutil"
            create_venv "server" "fastapi uvicorn rtmidi mido python-multipart aiofiles"
            ;;
    esac
fi

# Verify environments were created
echo "🔍 Verifying virtual environments..."

if [ "$BUILD_TARGET" = "client" ] || [ "$BUILD_TARGET" = "both" ]; then
    if [ -d "venv_client" ]; then
        echo "  ✅ Client environment: venv_client/"
    else
        echo "  ❌ Client environment not found"
        exit 1
    fi
fi

if [ "$BUILD_TARGET" = "server" ] || [ "$BUILD_TARGET" = "both" ]; then
    if [ -d "venv_server" ]; then
        echo "  ✅ Server environment: venv_server/"
    else
        echo "  ❌ Server environment not found"
        exit 1
    fi
fi

echo "✅ Virtual environments setup completed"
