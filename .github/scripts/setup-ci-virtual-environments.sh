#!/bin/bash
# setup-ci-virtual-environments.sh - Create isolated virtual environments for CI
set -euo pipefail

echo "🚀 Setting up CI virtual environments..."

# Create build directories for virtual environments
mkdir -p build_venv_client
mkdir -p build_venv_server

# Find Python
PYTHON_EXE="python"
echo "Using Python: $($PYTHON_EXE --version)"

setup_venv() {
    local name="$1"
    local requirements_file="$2"
    local extra_packages="$3"

    echo "🐍 Setting up $name virtual environment..."

    $PYTHON_EXE -m venv "build_venv_$name"
    source "build_venv_$name/bin/activate"

    # Install build tools
    python -m pip install --upgrade pip
    python -m pip install --upgrade setuptools wheel

    # Install requirements
    [ -f "$requirements_file" ] && python -m pip install -r "$requirements_file"
    [ -n "$extra_packages" ] && python -m pip install $extra_packages

    # Install test dependencies in both environments
    python -m pip install pytest pytest-cov pytest-xvfb pytest-qt

    deactivate
    echo "✅ $name environment completed"
}

# Setup client environment
setup_venv "client" "r2midi_client/requirements.txt" "PyQt6 PyQt6-Qt6 PyQt6-sip"

# Setup server environment
setup_venv "server" "server/requirements.txt" "fastapi uvicorn"

echo "✅ CI virtual environment setup completed!"