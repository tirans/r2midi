#!/bin/bash

# deploy-enhanced-build-system.sh - Complete deployment of enhanced R2MIDI build system
# Usage: ./deploy-enhanced-build-system.sh [--quick] [--full] [--test] [--production]

set -euo pipefail

QUICK_DEPLOY=false
FULL_DEPLOY=false
TEST_MODE=false
PRODUCTION_MODE=false
FORCE_OVERWRITE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            QUICK_DEPLOY=true
            shift
            ;;
        --full)
            FULL_DEPLOY=true
            shift
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --production)
            PRODUCTION_MODE=true
            shift
            ;;
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        *)
            echo "Usage: $0 [--quick] [--full] [--test] [--production] [--force]"
            echo ""
            echo "Deployment modes:"
            echo "  --quick       Quick deployment (essential scripts only)"
            echo "  --full        Full deployment (all scripts and documentation)"
            echo "  --test        Test deployment (includes validation and testing)"
            echo "  --production  Production deployment (optimized for CI/CD)"
            echo ""
            echo "Options:"
            echo "  --force       Overwrite existing files without prompting"
            echo ""
            echo "Examples:"
            echo "  $0 --quick --force     # Quick deployment, overwrite existing"
            echo "  $0 --full --test       # Full deployment with testing"
            echo "  $0 --production        # Production-ready deployment"
            exit 1
            ;;
    esac
done

# Set default mode if none specified
if [ "$QUICK_DEPLOY" = "false" ] && [ "$FULL_DEPLOY" = "false" ] && [ "$TEST_MODE" = "false" ] && [ "$PRODUCTION_MODE" = "false" ]; then
    FULL_DEPLOY=true
    echo "ℹ️ No mode specified, using --full deployment"
fi

echo "🚀 Deploying Enhanced R2MIDI Build System"
echo "=========================================="
echo ""
echo "Deployment configuration:"
echo "  Quick deploy: $QUICK_DEPLOY"
echo "  Full deploy: $FULL_DEPLOY"
echo "  Test mode: $TEST_MODE"
echo "  Production mode: $PRODUCTION_MODE"
echo "  Force overwrite: $FORCE_OVERWRITE"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        "INFO")
            echo -e "${BLUE}ℹ️ $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "STEP")
            echo -e "${BLUE}📋 $message${NC}"
            ;;
    esac
}

# Function to check if file should be overwritten
should_overwrite() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 0  # File doesn't exist, safe to create
    fi

    if [ "$FORCE_OVERWRITE" = "true" ]; then
        return 0  # Force overwrite enabled
    fi

    # Ask user
    echo -n "File exists: $file. Overwrite? (y/N): "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to backup existing files
backup_existing_files() {
    print_status "STEP" "Creating backup of existing files..."

    BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Files to backup
    backup_files=(
        ".github/workflows/build-macos.yml"
        "setup.py"
        "README.md"
        "clean-environment.sh"
        "setup-virtual-environments.sh"
    )

    backup_count=0
    for file in "${backup_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$BACKUP_DIR/" 2>/dev/null && backup_count=$((backup_count + 1))
        fi
    done

    if [ $backup_count -gt 0 ]; then
        print_status "SUCCESS" "Backed up $backup_count files to $BACKUP_DIR/"
    else
        print_status "INFO" "No existing files to backup"
        rmdir "$BACKUP_DIR" 2>/dev/null || true
    fi
}

# Function to create core build scripts
deploy_core_scripts() {
    print_status "STEP" "Deploying core build scripts..."

    # Create clean-environment.sh
    if should_overwrite "clean-environment.sh"; then
        cat > clean-environment.sh << 'EOF'
#!/bin/bash
# clean-environment.sh - Complete environment cleanup script
set -euo pipefail

DEEP_CLEAN=false
KEEP_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deep) DEEP_CLEAN=true; shift ;;
        --keep-cache) KEEP_CACHE=true; shift ;;
        *) echo "Usage: $0 [--deep] [--keep-cache]"; exit 1 ;;
    esac
done

echo "🧹 Starting comprehensive environment cleanup..."

safe_remove() {
    local path="$1"
    local description="$2"
    if [ -e "$path" ]; then
        echo "  🗑️ Removing $description: $path"
        rm -rf "$path" 2>/dev/null || echo "    ⚠️ Failed to remove $path"
    fi
}

# Clean build artifacts
safe_remove "build" "main build directory"
safe_remove "dist" "main dist directory"
safe_remove "build_native" "native build directory"
safe_remove "build_client" "client build directory"
safe_remove "build_server" "server build directory"
safe_remove "artifacts" "artifacts directory"

# Clean virtual environments
safe_remove "venv" "main virtual environment"
safe_remove "venv_client" "client virtual environment"
safe_remove "venv_server" "server virtual environment"
safe_remove ".venv" "hidden virtual environment"

if [ "$DEEP_CLEAN" = "true" ]; then
    for venv_name in venv-* .venv-* env-* .env-*; do
        safe_remove "$venv_name" "virtual environment ($venv_name)"
    done
fi

# Clean Python cache
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Clean security artifacts
safe_remove "*.p12" "certificate files"
safe_remove "entitlements.plist" "entitlements file"

# Clean package caches if requested
if [ "$KEEP_CACHE" = "false" ]; then
    python3 -m pip cache purge 2>/dev/null || true
    command -v brew >/dev/null && brew cleanup 2>/dev/null || true
fi

echo "✅ Environment cleanup completed!"
EOF
        chmod +x clean-environment.sh
        print_status "SUCCESS" "Created clean-environment.sh"
    else
        print_status "WARNING" "Skipped clean-environment.sh (user choice)"
    fi

    # Create setup-virtual-environments.sh
    if should_overwrite "setup-virtual-environments.sh"; then
        cat > setup-virtual-environments.sh << 'EOF'
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

    python -m pip install --upgrade pip setuptools wheel py2app

    if [ "$USE_UV" = "true" ] && ! command -v uv >/dev/null; then
        pip install uv
    fi

    INSTALLER="pip install"
    [ "$USE_UV" = "true" ] && command -v uv >/dev/null && INSTALLER="uv pip install"

    [ -f "$requirements_file" ] && $INSTALLER -r "$requirements_file"
    [ -n "$extra_packages" ] && $INSTALLER $extra_packages

    deactivate
    echo "✅ $name environment completed"
}

if [ "$SETUP_CLIENT" = "true" ]; then
    setup_venv "client" "r2midi_client/requirements.txt" "PyQt6 PyQt6-Qt6 httpx pydantic python-dotenv psutil"
fi

if [ "$SETUP_SERVER" = "true" ]; then
    setup_venv "server" "server/requirements.txt" "fastapi uvicorn rtmidi mido python-multipart aiofiles"
fi

echo "✅ Virtual environment setup completed!"
EOF
        chmod +x setup-virtual-environments.sh
        print_status "SUCCESS" "Created setup-virtual-environments.sh"
    else
        print_status "WARNING" "Skipped setup-virtual-environments.sh (user choice)"
    fi
}

# Function to create setup files
deploy_setup_files() {
    print_status "STEP" "Deploying enhanced py2app setup files..."

    # Create setup_client.py
    if should_overwrite "setup_client.py"; then
        cat > setup_client.py << 'EOF'
#!/usr/bin/env python3
"""Enhanced setup script for R2MIDI Client (macOS) with py2app"""

import os
import sys
from pathlib import Path
from setuptools import setup

# Get version
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "server"))
try:
    from version import __version__
except ImportError:
    __version__ = "1.0.0"

PROJECT_ROOT = Path(__file__).parent
CLIENT_DIR = PROJECT_ROOT / "r2midi_client"
RESOURCES_DIR = PROJECT_ROOT / "resources"

APP = [str(CLIENT_DIR / "main.py")]
DATA_FILES = []

if RESOURCES_DIR.exists():
    for resource_file in RESOURCES_DIR.glob("*"):
        if resource_file.is_file():
            DATA_FILES.append(str(resource_file))

OPTIONS = {
    'excludes': [
        'setuptools._vendor', 'pkg_resources._vendor', 'distutils._vendor',
        'tkinter', 'fastapi', 'uvicorn', 'rtmidi', 'mido', 'matplotlib', 'numpy'
    ],
    'includes': ['PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets', 'httpx', 'pydantic'],
    'packages': ['r2midi_client'],
    'argv_emulation': False,
    'site_packages': True,
    'optimize': 2,
    'iconfile': str(RESOURCES_DIR / 'r2midi.icns') if (RESOURCES_DIR / 'r2midi.icns').exists() else None,
    'plist': {
        'CFBundleName': 'R2MIDI Client',
        'CFBundleIdentifier': 'com.r2midi.client',
        'CFBundleVersion': __version__,
        'LSMinimumSystemVersion': '11.0',
        'NSHighResolutionCapable': True,
    },
}

setup(
    name='R2MIDI Client',
    version=__version__,
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF
        print_status "SUCCESS" "Created setup_client.py"
    else
        print_status "WARNING" "Skipped setup_client.py (user choice)"
    fi

    # Create setup_server.py
    if should_overwrite "setup_server.py"; then
        cat > setup_server.py << 'EOF'
#!/usr/bin/env python3
"""Enhanced setup script for R2MIDI Server (macOS) with py2app"""

import os
import sys
from pathlib import Path
from setuptools import setup

# Get version
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "server"))
try:
    from version import __version__
except ImportError:
    __version__ = "1.0.0"

PROJECT_ROOT = Path(__file__).parent
SERVER_DIR = PROJECT_ROOT / "server"
RESOURCES_DIR = PROJECT_ROOT / "resources"

APP = [str(SERVER_DIR / "main.py")]
DATA_FILES = []

if RESOURCES_DIR.exists():
    for resource_file in RESOURCES_DIR.glob("*"):
        if resource_file.is_file():
            DATA_FILES.append(str(resource_file))

OPTIONS = {
    'excludes': [
        'setuptools._vendor', 'pkg_resources._vendor', 'distutils._vendor',
        'PyQt6', 'tkinter', 'matplotlib', 'numpy'
    ],
    'includes': ['fastapi', 'uvicorn', 'rtmidi', 'mido', 'starlette', 'pydantic'],
    'packages': ['server', 'uvicorn', 'fastapi'],
    'argv_emulation': False,
    'site_packages': True,
    'optimize': 2,
    'iconfile': str(RESOURCES_DIR / 'r2midi.icns') if (RESOURCES_DIR / 'r2midi.icns').exists() else None,
    'plist': {
        'CFBundleName': 'R2MIDI Server',
        'CFBundleIdentifier': 'com.r2midi.server',
        'CFBundleVersion': __version__,
        'LSMinimumSystemVersion': '11.0',
        'NSHighResolutionCapable': True,
    },
}

setup(
    name='R2MIDI Server',
    version=__version__,
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF
        print_status "SUCCESS" "Created setup_server.py"
    else
        print_status "WARNING" "Skipped setup_server.py (user choice)"
    fi
}

# Function to create build scripts
deploy_build_scripts() {
    print_status "STEP" "Deploying build scripts..."

    # Create a simplified build-all-local.sh for this deployment
    if should_overwrite "build-all-local.sh"; then
        cat > build-all-local.sh << 'EOF'
#!/bin/bash
# build-all-local.sh - Build complete R2MIDI suite
set -euo pipefail

VERSION=""
BUILD_TYPE="local"
SKIP_SIGNING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift 2 ;;
        --dev) BUILD_TYPE="dev"; shift ;;
        --no-sign) SKIP_SIGNING=true; shift ;;
        --no-notarize) shift ;; # Accept but ignore
        *) echo "Usage: $0 [--version VERSION] [--dev] [--no-sign]"; exit 1 ;;
    esac
done

if [ -z "$VERSION" ]; then
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "import sys; sys.path.insert(0, 'server'); from version import __version__; print(__version__)")
    else
        VERSION="1.0.0"
    fi
fi

echo "🚀 Building R2MIDI Complete Suite v$VERSION..."

# Check environments
if [ ! -d "venv_client" ] || [ ! -d "venv_server" ]; then
    echo "❌ Virtual environments not found. Run: ./setup-virtual-environments.sh"
    exit 1
fi

mkdir -p artifacts

# Build client
echo "🎨 Building client..."
rm -rf build_client
mkdir -p build_client
cd build_client
cp ../setup_client.py setup.py
cp -r ../r2midi_client .
cp -r ../resources . 2>/dev/null || true
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py

source ../venv_client/bin/activate
python setup.py py2app
deactivate

[ -d "dist/main.app" ] && mv "dist/main.app" "dist/R2MIDI Client.app"
APP_PATH="dist/R2MIDI Client.app"

if [ "$SKIP_SIGNING" = "false" ] && security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    codesign --force --options runtime --deep --sign "Developer ID Application" "$APP_PATH"
fi

pkgbuild --root "dist" --identifier "com.r2midi.client" --version "$VERSION" \
         --install-location "/Applications" --component "$APP_PATH" \
         "../artifacts/R2MIDI-Client-${VERSION}.pkg"

cd ..

# Build server
echo "🖥️ Building server..."
rm -rf build_server
mkdir -p build_server
cd build_server
cp ../setup_server.py setup.py
cp -r ../server .
cp -r ../resources . 2>/dev/null || true
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py

source ../venv_server/bin/activate
python setup.py py2app
deactivate

[ -d "dist/main.app" ] && mv "dist/main.app" "dist/R2MIDI Server.app"
APP_PATH="dist/R2MIDI Server.app"

if [ "$SKIP_SIGNING" = "false" ] && security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    codesign --force --options runtime --deep --sign "Developer ID Application" "$APP_PATH"
fi

pkgbuild --root "dist" --identifier "com.r2midi.server" --version "$VERSION" \
         --install-location "/Applications" --component "$APP_PATH" \
         "../artifacts/R2MIDI-Server-${VERSION}.pkg"

cd ..

echo "✅ Build completed! Check artifacts/ directory."
EOF
        chmod +x build-all-local.sh
        print_status "SUCCESS" "Created build-all-local.sh"
    else
        print_status "WARNING" "Skipped build-all-local.sh (user choice)"
    fi

    # Create test_environments.sh
    if should_overwrite "test_environments.sh"; then
        cat > test_environments.sh << 'EOF'
#!/bin/bash
# test_environments.sh - Test virtual environments
set -euo pipefail

echo "🧪 Testing virtual environments..."

test_env() {
    local name="$1"
    local test_imports="$2"

    if [ -d "venv_$name" ]; then
        echo "🔍 Testing $name environment..."
        source "venv_$name/bin/activate"
        if python -c "$test_imports"; then
            echo "✅ $name environment working"
        else
            echo "❌ $name environment failed"
            deactivate
            return 1
        fi
        deactivate
    else
        echo "⚠️ $name environment not found"
        return 1
    fi
}

success=true

test_env "client" "import PyQt6, httpx, pydantic, py2app; print('Client dependencies OK')" || success=false
test_env "server" "import fastapi, uvicorn, rtmidi, mido, py2app; print('Server dependencies OK')" || success=false

if [ "$success" = "true" ]; then
    echo "✅ All environment tests passed!"
    exit 0
else
    echo "❌ Some environment tests failed!"
    exit 1
fi
EOF
        chmod +x test_environments.sh
        print_status "SUCCESS" "Created test_environments.sh"
    else
        print_status "WARNING" "Skipped test_environments.sh (user choice)"
    fi
}

# Function to deploy GitHub Actions
deploy_github_actions() {
    print_status "STEP" "Deploying GitHub Actions workflow and helper scripts..."

    # Create .github directories
    mkdir -p .github/{workflows,scripts}

    # Create clean GitHub Actions workflow
    if should_overwrite ".github/workflows/build-macos.yml"; then
        cat > .github/workflows/build-macos.yml << 'EOF'
name: Build macOS (Enhanced Virtual Environments)

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
    inputs:
      build-type:
        description: 'Build type'
        required: false
        type: choice
        options: [dev, staging, production]
        default: 'production'

jobs:
  build-macos-enhanced:
    name: 🍎 Enhanced macOS Build
    runs-on: self-hosted
    timeout-minutes: 45

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Clean environment
        shell: bash
        run: ./clean-environment.sh --keep-cache

      - name: Setup virtual environments
        shell: bash
        run: ./setup-virtual-environments.sh --use-uv

      - name: Test environments
        shell: bash
        run: ./test_environments.sh

      - name: Build applications
        shell: bash
        run: ./build-all-local.sh --dev --no-sign --version "1.0.0-ci"

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: macos-enhanced-${{ github.run_number }}
          path: artifacts/
          retention-days: 30
EOF
        print_status "SUCCESS" "Created .github/workflows/build-macos.yml"
    else
        print_status "WARNING" "Skipped GitHub Actions workflow (user choice)"
    fi
}

# Function to deploy validation and testing
deploy_validation() {
    print_status "STEP" "Deploying validation and testing scripts..."

    # Create simplified validation script
    if should_overwrite "validate-build-system.sh"; then
        cat > validate-build-system.sh << 'EOF'
#!/bin/bash
# validate-build-system.sh - Validate enhanced build system
set -euo pipefail

echo "🔍 Validating Enhanced R2MIDI Build System..."

errors=0

check_file() {
    local file="$1"
    local description="$2"
    if [ -f "$file" ] && [ -x "$file" ]; then
        echo "✅ $description: $file"
    else
        echo "❌ $description missing or not executable: $file"
        errors=$((errors + 1))
    fi
}

echo "📋 Checking core scripts..."
check_file "clean-environment.sh" "Environment cleanup script"
check_file "setup-virtual-environments.sh" "Virtual environment setup"
check_file "build-all-local.sh" "Build script"
check_file "test_environments.sh" "Environment testing"

echo "📋 Checking setup files..."
[ -f "setup_client.py" ] && echo "✅ Client setup: setup_client.py" || { echo "❌ setup_client.py missing"; errors=$((errors + 1)); }
[ -f "setup_server.py" ] && echo "✅ Server setup: setup_server.py" || { echo "❌ setup_server.py missing"; errors=$((errors + 1)); }

echo "📋 Checking GitHub Actions..."
[ -f ".github/workflows/build-macos.yml" ] && echo "✅ GitHub workflow exists" || echo "⚠️ GitHub workflow missing"

echo "📋 Checking Python version..."
if python3 --version | grep -E "3\.(1[0-9]|[2-9][0-9])" >/dev/null; then
    echo "✅ Python version: $(python3 --version)"
else
    echo "❌ Python 3.10+ required, found: $(python3 --version)"
    errors=$((errors + 1))
fi

if [ $errors -eq 0 ]; then
    echo ""
    echo "🎉 Validation successful! Enhanced build system is ready."
    echo "📋 Next steps:"
    echo "  1. ./setup-virtual-environments.sh"
    echo "  2. ./test_environments.sh"
    echo "  3. ./build-all-local.sh --dev"
    exit 0
else
    echo ""
    echo "❌ Validation failed with $errors errors."
    echo "Please fix the issues above before proceeding."
    exit 1
fi
EOF
        chmod +x validate-build-system.sh
        print_status "SUCCESS" "Created validate-build-system.sh"
    else
        print_status "WARNING" "Skipped validation script (user choice)"
    fi
}

# Function to deploy documentation
deploy_documentation() {
    print_status "STEP" "Deploying documentation..."

    # Create quick start guide
    if should_overwrite "QUICK_START.md"; then
        cat > QUICK_START.md << 'EOF'
# R2MIDI Enhanced Build System - Quick Start

## 🚀 Quick Setup

```bash
# 1. Validate system
./validate-build-system.sh

# 2. Setup environments
./clean-environment.sh
./setup-virtual-environments.sh

# 3. Test setup
./test_environments.sh

# 4. Build applications
./build-all-local.sh --dev --no-sign
```

## 📦 Build Outputs

After successful build, check the `artifacts/` directory:
- `R2MIDI-Client-VERSION.pkg` - Client installer
- `R2MIDI-Server-VERSION.pkg` - Server installer

## 🔧 Common Commands

```bash
# Development build (unsigned)
./build-all-local.sh --dev --no-sign

# Production build (requires certificates)
./build-all-local.sh --version 1.0.0

# Clean environment
./clean-environment.sh --deep

# Setup with UV (faster)
./setup-virtual-environments.sh --use-uv
```

## 🆘 Troubleshooting

1. **Python version**: Requires Python 3.10+
2. **Virtual environments**: Run `./setup-virtual-environments.sh`
3. **Build failures**: Check `./test_environments.sh`
4. **Signing issues**: Verify Apple Developer certificates

## 📋 GitHub Actions

Push to `main` or `develop` branch to trigger CI builds.
Artifacts will be available in the Actions tab.

---

For detailed documentation, see the full project README.
EOF
        print_status "SUCCESS" "Created QUICK_START.md"
    else
        print_status "WARNING" "Skipped QUICK_START.md (user choice)"
    fi
}

# Function to run post-deployment validation
run_validation() {
    print_status "STEP" "Running post-deployment validation..."

    if [ -f "validate-build-system.sh" ]; then
        echo ""
        if ./validate-build-system.sh; then
            print_status "SUCCESS" "Post-deployment validation passed!"
        else
            print_status "ERROR" "Post-deployment validation failed!"
            return 1
        fi
    else
        print_status "WARNING" "Validation script not found, skipping validation"
    fi
}

# Function to run test build
run_test_build() {
    print_status "STEP" "Running test build to verify functionality..."

    echo ""
    print_status "INFO" "This will take a few minutes..."

    # Clean and setup
    ./clean-environment.sh >/dev/null 2>&1 || true

    if ./setup-virtual-environments.sh >/dev/null 2>&1; then
        print_status "SUCCESS" "Virtual environments created successfully"
    else
        print_status "ERROR" "Virtual environment setup failed"
        return 1
    fi

    if ./test_environments.sh >/dev/null 2>&1; then
        print_status "SUCCESS" "Environment testing passed"
    else
        print_status "ERROR" "Environment testing failed"
        return 1
    fi

    if ./build-all-local.sh --dev --no-sign --version "1.0.0.dev0" >/dev/null 2>&1; then
        print_status "SUCCESS" "Test build completed successfully"

        # Check artifacts
        if ls artifacts/*.pkg >/dev/null 2>&1; then
            pkg_count=$(ls artifacts/*.pkg | wc -l)
            print_status "SUCCESS" "Created $pkg_count PKG installer(s)"
        else
            print_status "WARNING" "Build completed but no PKG files found"
        fi
    else
        print_status "ERROR" "Test build failed"
        return 1
    fi
}

# Main deployment flow
main() {
    print_status "INFO" "Starting enhanced build system deployment..."

    # Backup existing files
    if [ "$FORCE_OVERWRITE" = "false" ]; then
        backup_existing_files
    fi

    # Deploy core components
    deploy_core_scripts
    deploy_setup_files
    deploy_build_scripts

    # Deploy additional components based on mode
    if [ "$FULL_DEPLOY" = "true" ] || [ "$PRODUCTION_MODE" = "true" ]; then
        deploy_github_actions
        deploy_documentation
    fi

    if [ "$TEST_MODE" = "true" ] || [ "$FULL_DEPLOY" = "true" ]; then
        deploy_validation
    fi

    # Run validation
    if run_validation; then
        print_status "SUCCESS" "Deployment completed successfully!"
    else
        print_status "ERROR" "Deployment completed with validation errors"
        exit 1
    fi

    # Run test build if requested
    if [ "$TEST_MODE" = "true" ]; then
        if run_test_build; then
            print_status "SUCCESS" "Test build completed successfully!"
        else
            print_status "WARNING" "Test build failed - check configuration"
        fi
    fi

    # Final summary
    echo ""
    print_status "SUCCESS" "🎉 Enhanced R2MIDI Build System Deployed!"
    echo ""
    echo "📋 What was deployed:"
    [ -f "clean-environment.sh" ] && echo "  ✅ Environment cleanup script"
    [ -f "setup-virtual-environments.sh" ] && echo "  ✅ Virtual environment setup"
    [ -f "build-all-local.sh" ] && echo "  ✅ Build scripts"
    [ -f "setup_client.py" ] && echo "  ✅ Enhanced py2app configurations"
    [ -f ".github/workflows/build-macos.yml" ] && echo "  ✅ GitHub Actions workflow"
    [ -f "validate-build-system.sh" ] && echo "  ✅ Validation script"
    [ -f "QUICK_START.md" ] && echo "  ✅ Documentation"

    echo ""
    echo "📋 Next steps:"
    echo "  1. Read QUICK_START.md for usage instructions"
    echo "  2. Run: ./setup-virtual-environments.sh"
    echo "  3. Test: ./build-all-local.sh --dev --no-sign"
    echo "  4. Configure Apple Developer certificates for production builds"
    echo ""
    echo "🚀 Your enhanced build system is ready!"
    echo "🚫 No more Briefcase exit code 200 failures!"
}

# Run main deployment
main

exit 0
EOF
chmod +x deploy-enhanced-build-system.sh
print_status "SUCCESS" "Created comprehensive deployment script"
