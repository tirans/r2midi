#!/bin/bash
# setup-virtual-environments.sh - Create isolated virtual environments
set -euo pipefail

SETUP_CLIENT=true
SETUP_SERVER=true
USE_UV=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --client-only) SETUP_CLIENT=true; SETUP_SERVER=false; shift ;;
        --server-only) SETUP_CLIENT=false; SETUP_SERVER=true; shift ;;
        --use-uv) USE_UV=true; shift ;;
        *) echo "Usage: $0 [--client-only] [--server-only] [--use-uv]"; exit 1 ;;
    esac
done

echo "🚀 Setting up virtual environments..."

# Find Python
PYTHON_EXE=""
for py_cmd in python3.12 python3.11 python3.10 python3; do
    if command -v "$py_cmd" >/dev/null 2>&1; then
        version=$($py_cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        if [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; then
            PYTHON_EXE="$py_cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON_EXE" ]; then
    echo "❌ No suitable Python found (requires 3.10+)"
    exit 1
fi

setup_venv() {
    local name="$1"
    local requirements_file="$2"
    local extra_packages="$3"

    echo "🐍 Setting up $name virtual environment..."

    [ -d "venv_$name" ] && rm -rf "venv_$name"
    $PYTHON_EXE -m venv "venv_$name"
    source "venv_$name/bin/activate"

    # Clear any existing cache before installing
    python -m pip cache purge 2>/dev/null || true
    
    # Install build tools with specific versions to avoid conflicts
    python -m pip install --upgrade pip
    python -m pip install --upgrade "setuptools>=68.0.0" wheel
    python -m pip install --use-pep517 --force-reinstall py2app

    if [ "$USE_UV" = "true" ] && ! command -v uv >/dev/null; then
        pip install uv
    fi

    INSTALLER="pip install --use-pep517"
    [ "$USE_UV" = "true" ] && command -v uv >/dev/null && INSTALLER="uv pip install"

    [ -f "$requirements_file" ] && $INSTALLER -r "$requirements_file"
    [ -n "$extra_packages" ] && $INSTALLER $extra_packages

    deactivate
    echo "✅ $name environment completed"
}

if [ "$SETUP_CLIENT" = "true" ]; then
    setup_venv "client" "r2midi_client/requirements.txt" ""
fi

if [ "$SETUP_SERVER" = "true" ]; then
    setup_venv "server" "server/requirements.txt" ""
fi

echo "✅ Virtual environment setup completed!"
