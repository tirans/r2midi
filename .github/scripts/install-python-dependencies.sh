#!/bin/bash
set -euo pipefail
# Install Python dependencies for R2MIDI project
# Usage: install-python-dependencies.sh [build_type]

BUILD_TYPE="${1:-production}"
echo "🐍 Installing Python dependencies for $BUILD_TYPE build..."

# Upgrade pip first
echo "📦 Upgrading pip..."
python -m pip install --upgrade pip

# Install core build tools
echo "🔧 Installing core build tools..."
python -m pip install --upgrade \
    setuptools \
    wheel \
    build

# Install Briefcase for app packaging
echo "📱 Installing Briefcase..."
python -m pip install --upgrade briefcase

# Install project dependencies based on build type
case "$BUILD_TYPE" in
    "ci"|"test")
        echo "🧪 Installing CI/test dependencies..."
        
        # Install test dependencies
        python -m pip install --upgrade \
            pytest \
            pytest-cov \
            pytest-xvfb \
            pytest-qt
        
        # Install linting and formatting tools
        python -m pip install --upgrade \
            black \
            flake8 \
            isort \
            mypy
        
        # Install project dependencies
        if [ -f "requirements.txt" ]; then
            echo "📋 Installing from requirements.txt..."
            python -m pip install -r requirements.txt
        fi
        
        # Install client dependencies
        if [ -f "r2midi_client/requirements.txt" ]; then
            echo "📋 Installing client dependencies..."
            python -m pip install -r r2midi_client/requirements.txt
        fi
        ;;
        
    "dev"|"development")
        echo "🛠️ Installing development dependencies..."
        
        # Install development tools
        python -m pip install --upgrade \
            pytest \
            pytest-cov \
            pytest-xvfb \
            pytest-qt \
            black \
            flake8 \
            isort \
            mypy \
            pre-commit
        
        # Install project dependencies
        if [ -f "requirements.txt" ]; then
            echo "📋 Installing from requirements.txt..."
            python -m pip install -r requirements.txt
        fi
        
        # Install client dependencies
        if [ -f "r2midi_client/requirements.txt" ]; then
            echo "📋 Installing client dependencies..."
            python -m pip install -r r2midi_client/requirements.txt
        fi
        
        # Install in editable mode if setup.py exists
        if [ -f "setup.py" ]; then
            echo "📦 Installing project in editable mode..."
            python -m pip install -e .
        fi
        ;;
        
    "production"|*)
        echo "🚀 Installing production dependencies..."
        
        # Install project dependencies
        if [ -f "requirements.txt" ]; then
            echo "📋 Installing from requirements.txt..."
            python -m pip install -r requirements.txt
        fi
        
        # Install client dependencies
        if [ -f "r2midi_client/requirements.txt" ]; then
            echo "📋 Installing client dependencies..."
            python -m pip install -r r2midi_client/requirements.txt
        fi
        ;;
esac

# Install additional dependencies for specific platforms
echo "🌐 Installing platform-specific dependencies..."
case "$(uname -s)" in
    "Linux")
        echo "🐧 Installing Linux-specific Python packages..."
        # Install packages that might be needed for Linux GUI apps
        python -m pip install --upgrade \
            PyQt6 \
            PyQt6-Qt6 \
            PyQt6-sip
        ;;
    "Darwin")
        echo "🍎 Installing macOS-specific Python packages..."
        # Install packages that might be needed for macOS apps
        python -m pip install --upgrade \
            PyQt6 \
            PyQt6-Qt6 \
            PyQt6-sip
        ;;
    "CYGWIN"*|"MINGW"*|"MSYS"*)
        echo "🪟 Installing Windows-specific Python packages..."
        # Install packages that might be needed for Windows apps
        python -m pip install --upgrade \
            PyQt6 \
            PyQt6-Qt6 \
            PyQt6-sip
        ;;
esac

# Verify installation
echo "🔍 Verifying Python environment..."
echo "Python version: $(python --version)"
echo "Pip version: $(pip --version)"

# Check if key packages are installed
echo "📋 Installed packages summary:"
if pip show briefcase >/dev/null 2>&1; then
    briefcase_version=$(pip show briefcase | grep Version | cut -d' ' -f2)
    echo "  - Briefcase: $briefcase_version"
fi

if pip show PyQt6 >/dev/null 2>&1; then
    pyqt6_version=$(pip show PyQt6 | grep Version | cut -d' ' -f2)
    echo "  - PyQt6: $pyqt6_version"
fi

if [ "$BUILD_TYPE" = "ci" ] || [ "$BUILD_TYPE" = "test" ] || [ "$BUILD_TYPE" = "dev" ]; then
    if pip show pytest >/dev/null 2>&1; then
        pytest_version=$(pip show pytest | grep Version | cut -d' ' -f2)
        echo "  - Pytest: $pytest_version"
    fi
    
    if pip show black >/dev/null 2>&1; then
        black_version=$(pip show black | grep Version | cut -d' ' -f2)
        echo "  - Black: $black_version"
    fi
fi

# Check for project-specific packages
if pip show fastapi >/dev/null 2>&1; then
    fastapi_version=$(pip show fastapi | grep Version | cut -d' ' -f2)
    echo "  - FastAPI: $fastapi_version"
fi

if pip show mido >/dev/null 2>&1; then
    mido_version=$(pip show mido | grep Version | cut -d' ' -f2)
    echo "  - Mido: $mido_version"
fi

echo "✅ Python dependencies installation complete for $BUILD_TYPE build!"