#!/bin/bash
set -euo pipefail

# Install Python dependencies for native macOS build
# Usage: install-native-dependencies.sh

echo "📦 Installing Python dependencies for native macOS build..."
echo "🔧 Using py2app instead of Briefcase"
echo "Runner: ${RUNNER_TYPE:-unknown}"

if [ "${IS_M3_MAX:-false}" = "true" ]; then
    echo "🚀 M3 Max optimized dependency installation using ${CPU_CORES:-8} cores..."
fi

# Upgrade pip first
python3 -m pip install --upgrade pip

# Install py2app - the native macOS app builder
echo "📦 Installing py2app (native macOS app builder)..."
python3 -m pip install py2app

# Install project dependencies
echo "📦 Installing project requirements..."
if [ -f "requirements.txt" ]; then
    python3 -m pip install -r requirements.txt
else
    echo "⚠️ Warning: requirements.txt not found"
fi

if [ -f "r2midi_client/requirements.txt" ]; then
    python3 -m pip install -r r2midi_client/requirements.txt
else
    echo "⚠️ Warning: r2midi_client/requirements.txt not found"
fi

# Verify key packages for native build
echo "🔍 Verifying installed packages for native build..."
python3 -c "import py2app; print(f'✅ py2app: {py2app.__version__}')" || echo "❌ py2app not available"
python3 -c "import fastapi; print(f'✅ fastapi: {fastapi.__version__}')" || echo "⚠️ fastapi not available"
python3 -c "import PyQt6; print('✅ PyQt6: OK')" || echo "⚠️ PyQt6 not available"
python3 -c "import rtmidi; print('✅ python-rtmidi: OK')" || echo "⚠️ python-rtmidi not available"

echo "✅ All dependencies installed for native macOS build"
