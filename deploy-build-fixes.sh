#!/bin/bash
# deploy-build-fixes.sh - Deploy resilient build fixes for r2midi project
set -euo pipefail

# Configuration
PROJECT_ROOT="/Users/tirane/Desktop/r2midi"
BACKUP_DIR="${PROJECT_ROOT}/.github/backups/$(date +%Y%m%d-%H%M%S)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to create backup
create_backup() {
    print_status $BLUE "📁 Creating backup of current build files..."

    mkdir -p "$BACKUP_DIR"

    # Backup existing files
    local files_to_backup=(
        ".github/scripts/build-macos.sh"
        ".github/scripts/build-briefcase.sh"
        ".github/actions/build-apps/action.yml"
    )

    for file in "${files_to_backup[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            local backup_path="$BACKUP_DIR/$file"
            mkdir -p "$(dirname "$backup_path")"
            cp "$PROJECT_ROOT/$file" "$backup_path"
            print_status $GREEN "✅ Backed up: $file"
        else
            print_status $YELLOW "⚠️ File not found for backup: $file"
        fi
    done

    print_status $GREEN "✅ Backup created at: $BACKUP_DIR"
}

# Function to validate project structure
validate_project() {
    print_status $BLUE "🔍 Validating project structure..."

    if [ ! -d "$PROJECT_ROOT" ]; then
        print_status $RED "❌ Project root not found: $PROJECT_ROOT"
        exit 1
    fi

    local required_dirs=(
        ".github/scripts"
        ".github/actions/build-apps"
        "server"
        "r2midi_client"
    )

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            print_status $RED "❌ Required directory not found: $dir"
            exit 1
        fi
    done

    local required_files=(
        "pyproject.toml"
        "requirements.txt"
        "server/main.py"
        "r2midi_client/main.py"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            print_status $RED "❌ Required file not found: $file"
            exit 1
        fi
    done

    print_status $GREEN "✅ Project structure validation passed"
}

# Function to deploy the enhanced macOS build script
deploy_macos_script() {
    print_status $BLUE "🍎 Deploying enhanced macOS build script..."

    cat > "$PROJECT_ROOT/.github/scripts/build-macos.sh" << 'EOF'
#!/bin/bash
# build-macos.sh - Resilient Native macOS build script using py2app
set -euo pipefail

# Function to handle errors with detailed logging
handle_error() {
    local exit_code=$?
    local line_number=$1
    echo "❌ Error occurred in build-macos.sh at line $line_number"
    echo "Exit code: $exit_code"

    # Log system information for debugging
    echo "🔍 Debug Information:"
    echo "Working directory: $(pwd)"
    echo "Python version: $(python --version 2>/dev/null || echo 'Python not found')"
    echo "Available disk space: $(df -h . | tail -1 | awk '{print $4}' || echo 'Unknown')"
    echo "Memory usage: $(top -l 1 | grep PhysMem | awk '{print $2, $4, $6}' || echo 'Unknown')"

    # Log recent build artifacts if they exist
    if [ -d "build" ]; then
        echo "📁 Build directory structure:"
        find build -type f -name "*.log" -exec echo "Log file: {}" \; -exec tail -10 {} \; 2>/dev/null || echo "No log files found"
    fi

    return $exit_code
}

trap 'handle_error $LINENO' ERR

# Function to retry commands with exponential backoff
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local base_delay="${3:-5}"

    for attempt in $(seq 1 $max_attempts); do
        local delay=$((base_delay * attempt))
        echo "🔄 Attempt $attempt/$max_attempts: $cmd"

        if timeout 300 bash -c "$cmd"; then
            echo "✅ Command succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            echo "⚠️ Command failed with exit code $exit_code"

            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ Waiting ${delay}s before retry (exponential backoff)..."
                sleep $delay

                # Clean up any partial state that might cause issues
                echo "🧹 Cleaning up partial build state..."
                rm -rf build/*/build/bdist.* 2>/dev/null || true
                rm -rf build/*/dist/temp* 2>/dev/null || true

                # Force Python garbage collection
                python -c "import gc; gc.collect()" 2>/dev/null || true
            fi
        fi
    done

    echo "❌ Command failed after $max_attempts attempts: $cmd"
    return 1
}

# Function to clean build environment thoroughly
clean_build_environment() {
    echo "🧹 Thoroughly cleaning build environment..."

    # Remove any existing build artifacts that could cause conflicts
    local dirs_to_clean=(
        "build/*/build"
        "build/*/dist"
        "dist/*/temp*"
        "*.egg-info"
        "__pycache__"
        "*.pyc"
        "*.pyo"
    )

    for pattern in "${dirs_to_clean[@]}"; do
        find . -path "./$pattern" -exec rm -rf {} + 2>/dev/null || true
    done

    # Clean pip cache to prevent conflicts
    pip cache purge 2>/dev/null || true

    echo "✅ Build environment cleaned"
}

# Function to setup Python environment with proper isolation
setup_python_environment() {
    echo "🐍 Setting up isolated Python environment..."

    # Verify Python installation
    if ! python --version >/dev/null 2>&1; then
        echo "❌ Python not found or not working"
        return 1
    fi

    # Upgrade pip and core tools
    retry_command "python -m pip install --upgrade pip setuptools wheel" 3 5

    # Install py2app with specific options for better compatibility
    echo "📦 Installing py2app with compatibility options..."
    retry_command "pip install py2app==0.28.8 --no-deps" 3 10
    retry_command "pip install setuptools>=65.0.0 modulegraph2 altgraph2" 3 10

    # Install project dependencies with isolation
    echo "📦 Installing project dependencies..."
    if [ -f "requirements.txt" ]; then
        retry_command "pip install -r requirements.txt --no-cache-dir" 3 15
    fi

    if [ -f "r2midi_client/requirements.txt" ]; then
        retry_command "pip install -r r2midi_client/requirements.txt --no-cache-dir" 3 15
    fi

    echo "✅ Python environment ready"
}

# Function to create optimized setup.py for py2app
create_setup_py() {
    local app_type="$1"
    local app_dir="$2"

    echo "📝 Creating optimized setup.py for $app_type..."

    local app_name bundle_id main_script includes packages data_files

    if [ "$app_type" = "server" ]; then
        app_name="R2MIDI Server"
        bundle_id="com.r2midi.server"
        main_script="main.py"
        includes="server.main,server.api,server.midi,server.presets,server.version,server.config"
        packages="fastapi,uvicorn,pydantic,python-rtmidi,mido,httpx,dotenv,psutil"
        data_files=""
    else
        app_name="R2MIDI Client"
        bundle_id="com.r2midi.client"
        main_script="main.py"
        includes="r2midi_client.main,r2midi_client.ui,r2midi_client.api,r2midi_client.config"
        packages="PyQt6,httpx,dotenv,pydantic,psutil"
        data_files=""
    fi

    # Find resources safely
    if [ -d "resources" ]; then
        data_files="DATA_FILES = [('resources', glob.glob('resources/*'))]"
    else
        data_files="DATA_FILES = []"
    fi

    cat > "$app_dir/setup.py" << SETUP_EOF
#!/usr/bin/env python3
"""
Optimized setup script for $app_name with conflict resolution
"""
import sys
import os
import glob
import shutil
from setuptools import setup

# Ensure clean build environment
def clean_build_dirs():
    dirs_to_clean = ['build', 'dist']
    for dir_name in dirs_to_clean:
        if os.path.exists(dir_name):
            shutil.rmtree(dir_name, ignore_errors=True)

# Clean before building
clean_build_dirs()

APP = ['$main_script']
$data_files

# Icon file handling
ICON_FILE = None
icon_paths = ['../resources/r2midi.icns', 'r2midi.icns', '../r2midi.icns']
for icon_path in icon_paths:
    if os.path.exists(icon_path):
        ICON_FILE = icon_path
        break

# Optimized py2app options with conflict prevention
OPTIONS = {
    'argv_emulation': False,
    'site_packages': False,  # Prevent site-packages conflicts
    'use_pythonpath': False,  # Use only specified packages
    'no_chdir': True,  # Prevent working directory changes
    'plist': {
        'CFBundleName': '$app_name',
        'CFBundleDisplayName': '$app_name',
        'CFBundleIdentifier': '$bundle_id',
        'CFBundleVersion': os.environ.get('APP_VERSION', '1.0.0'),
        'CFBundleShortVersionString': os.environ.get('APP_VERSION', '1.0.0'),
        'LSMinimumSystemVersion': '10.15.0',
        'LSBackgroundOnly': False,
        'NSHighResolutionCapable': True,
        'NSRequiresAquaSystemAppearance': False,
        'LSApplicationCategoryType': 'public.app-category.utilities',
        'NSHumanReadableCopyright': 'Copyright © 2024 R2MIDI Team',
    },
    'packages': [pkg.strip() for pkg in '$packages'.split(',') if pkg.strip()],
    'includes': [inc.strip() for inc in '$includes'.split(',') if inc.strip()],
    'excludes': [
        'tkinter', 'test', 'tests', 'unittest', 'doctest',
        'pdb', 'pydoc', 'email.test', 'xml.sax.xmlreader',
    ],
    'resources': [],
    'iconfile': ICON_FILE,
    'strip': True,
    'optimize': 2,
    'compressed': True,
    'dist_dir': '../../dist/$app_type',
    # Conflict resolution options
    'prefer_ppc': False,
    'semi_standalone': False,
    'alias': False,
    'debug_modulegraph': False,
    'debug_skip_macholib': True,
}

if __name__ == '__main__':
    try:
        setup(
            app=APP,
            data_files=DATA_FILES,
            options={'py2app': OPTIONS},
            setup_requires=['py2app'],
        )
    except Exception as e:
        print(f"Setup failed: {e}")
        # Clean up on failure
        clean_build_dirs()
        raise
SETUP_EOF

    echo "✅ Optimized setup script created for $app_type"
}

# Function to build applications with enhanced error handling
build_applications() {
    echo "🔨 Building macOS applications with enhanced resilience..."

    # Clean and setup environment
    clean_build_environment
    setup_python_environment

    # Prepare build directories with proper permissions
    echo "🔧 Preparing build directories..."
    mkdir -p build/{server,client,resources}
    mkdir -p dist/{server,client}
    chmod -R 755 build dist

    # Copy source files with exclusions
    echo "📁 Copying source files..."
    if [ -d "server" ]; then
        mkdir -p build/server/

        # Use rsync for reliable copying with exclusions
        rsync -av \
            --exclude="midi-presets/" \
            --exclude="logs/" \
            --exclude="__pycache__/" \
            --exclude="*.pyc" \
            --exclude="*.pyo" \
            --exclude=".DS_Store" \
            server/ build/server/

        echo "✅ Server files copied"
    fi

    if [ -d "r2midi_client" ]; then
        rsync -av \
            --exclude="__pycache__/" \
            --exclude="*.pyc" \
            --exclude="*.pyo" \
            --exclude=".DS_Store" \
            r2midi_client/ build/client/

        echo "✅ Client files copied"
    fi

    # Copy resources safely
    if [ -d "resources" ]; then
        rsync -av resources/ build/resources/ 2>/dev/null || true
    fi

    # Ensure icon exists
    for icon_file in "r2midi.icns" "resources/r2midi.icns"; do
        if [ -f "$icon_file" ] && [ ! -f "build/resources/r2midi.icns" ]; then
            mkdir -p build/resources
            cp "$icon_file" build/resources/r2midi.icns
            break
        fi
    done

    # Create optimized setup scripts
    create_setup_py "server" "build/server"
    create_setup_py "client" "build/client"

    # Build server application with isolation
    echo "🏗️ Building server application..."
    cd build/server

    # Pre-clean any conflicting directories
    find . -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    rm -rf build dist 2>/dev/null || true

    # Build with timeout and monitoring
    if retry_command "python setup.py py2app" 3 30; then
        echo "✅ Server build successful"
    else
        echo "❌ Server build failed"

        # Enhanced logging for debugging
        echo "📋 Detailed build information:"
        ls -la . 2>/dev/null || true
        find . -name "*.log" -exec echo "=== {} ===" \; -exec cat {} \; 2>/dev/null || echo "No log files found"

        cd ../..
        return 1
    fi
    cd ../..

    # Build client application with isolation
    echo "🏗️ Building client application..."
    cd build/client

    # Pre-clean any conflicting directories
    find . -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    rm -rf build dist 2>/dev/null || true

    # Build with timeout and monitoring
    if retry_command "python setup.py py2app" 3 30; then
        echo "✅ Client build successful"
    else
        echo "❌ Client build failed"

        # Enhanced logging for debugging
        echo "📋 Detailed build information:"
        ls -la . 2>/dev/null || true
        find . -name "*.log" -exec echo "=== {} ===" \; -exec cat {} \; 2>/dev/null || echo "No log files found"

        cd ../..
        return 1
    fi
    cd ../..

    # Locate and validate built applications
    echo "🔍 Locating and validating built applications..."

    # Find server app with proper error handling
    SERVER_APP_PATH=""
    if [ -d "dist/server" ]; then
        while IFS= read -r -d '' app_path; do
            if [ -d "$app_path" ] && [[ "$app_path" == *.app ]]; then
                SERVER_APP_PATH="$(realpath "$app_path")"
                echo "✅ Server app found: $SERVER_APP_PATH"
                break
            fi
        done < <(find dist/server -name "*.app" -type d -print0 2>/dev/null)
    fi

    # Find client app with proper error handling
    CLIENT_APP_PATH=""
    if [ -d "dist/client" ]; then
        while IFS= read -r -d '' app_path; do
            if [ -d "$app_path" ] && [[ "$app_path" == *.app ]]; then
                CLIENT_APP_PATH="$(realpath "$app_path")"
                echo "✅ Client app found: $CLIENT_APP_PATH"
                break
            fi
        done < <(find dist/client -name "*.app" -type d -print0 2>/dev/null)
    fi

    # Validate executables
    if [ -n "$SERVER_APP_PATH" ]; then
        if ls "$SERVER_APP_PATH/Contents/MacOS/"* >/dev/null 2>&1; then
            echo "✅ Server executable validated"
        else
            echo "⚠️ Server executable not found"
        fi
    fi

    if [ -n "$CLIENT_APP_PATH" ]; then
        if ls "$CLIENT_APP_PATH/Contents/MacOS/"* >/dev/null 2>&1; then
            echo "✅ Client executable validated"
        else
            echo "⚠️ Client executable not found"
        fi
    fi

    # Create artifacts directory and build info
    mkdir -p build/artifacts

    # Generate comprehensive build info
    cat > build/artifacts/build-info.txt << BUILD_INFO_EOF
R2MIDI Native macOS Build Information
=====================================

Platform: macOS
Build Type: ${BUILD_TYPE:-development}
Version: ${APP_VERSION:-1.0.0}
Method: py2app (native, optimized)
Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Host: $(uname -a)
Xcode: $(xcode-select --print-path 2>/dev/null || echo "Not available")
Python: $(python --version 2>/dev/null || echo "Unknown")
py2app: $(python -c "import py2app; print(py2app.__version__)" 2>/dev/null || echo "Unknown")

Build Results:
Server App: ${SERVER_APP_PATH:-Not found}
Client App: ${CLIENT_APP_PATH:-Not found}

Build Quality Checks:
- Source copying: ✅ Completed with rsync
- Environment isolation: ✅ Site-packages conflicts prevented
- Build optimization: ✅ Strip and compression enabled
- Error handling: ✅ Retry mechanism with exponential backoff
- Resource management: ✅ Proper cleanup and validation
BUILD_INFO_EOF

    echo "✅ Native macOS build complete with enhanced resilience"

    # Final validation
    local build_success=true
    if [ -z "$SERVER_APP_PATH" ]; then
        echo "⚠️ Server application not built successfully"
        build_success=false
    fi
    if [ -z "$CLIENT_APP_PATH" ]; then
        echo "⚠️ Client application not built successfully"
        build_success=false
    fi

    if [ "$build_success" = "false" ]; then
        echo "❌ Build completed with warnings - some applications may not be available"
        return 1
    fi
}

# Export variables for GitHub Actions
export SERVER_APP_PATH
export CLIENT_APP_PATH

echo "🔧 Enhanced macOS native build script loaded"
EOF

    chmod +x "$PROJECT_ROOT/.github/scripts/build-macos.sh"
    print_status $GREEN "✅ Enhanced macOS build script deployed"
}

# Function to deploy the enhanced briefcase script
deploy_briefcase_script() {
    print_status $BLUE "📦 Deploying enhanced Briefcase build script..."

    cat > "$PROJECT_ROOT/.github/scripts/build-briefcase.sh" << 'EOF'
#!/bin/bash
# build-briefcase.sh - Resilient Briefcase build script for Windows/Linux platforms
set -euo pipefail

# Function to handle errors with comprehensive logging
handle_error() {
    local exit_code=$?
    local line_number=$1
    echo "❌ Error occurred in build-briefcase.sh at line $line_number"
    echo "Exit code: $exit_code"

    # Log comprehensive debug information
    echo "🔍 Debug Information:"
    echo "Working directory: $(pwd)"
    echo "Platform: ${PLATFORM:-unknown}"
    echo "Build method: ${BUILD_METHOD:-unknown}"
    echo "Python version: $(python --version 2>/dev/null || echo 'Python not found')"
    echo "Briefcase version: $(briefcase --version 2>/dev/null || echo 'Briefcase not found')"

    return $exit_code
}

trap 'handle_error $LINENO' ERR

# Function to retry commands with intelligent backoff
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local base_delay="${3:-5}"
    local timeout_duration="${4:-300}"

    for attempt in $(seq 1 $max_attempts); do
        local delay=$((base_delay * attempt))
        echo "🔄 Attempt $attempt/$max_attempts: $cmd"

        if timeout "$timeout_duration" bash -c "$cmd" 2>&1; then
            echo "✅ Command succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            echo "⚠️ Command failed with exit code $exit_code"

            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ Waiting ${delay}s before retry..."
                sleep $delay

                # Platform-specific cleanup
                echo "🧹 Cleaning up partial build state..."
                case "${PLATFORM:-}" in
                    linux)
                        pkill -f briefcase 2>/dev/null || true
                        rm -rf /tmp/briefcase-* 2>/dev/null || true
                        ;;
                    windows)
                        rm -rf /tmp/briefcase-* 2>/dev/null || true
                        rm -rf build/*/windows/app/src/app_packages 2>/dev/null || true
                        ;;
                esac

                rm -rf build/*/build 2>/dev/null || true
                rm -rf dist/temp* 2>/dev/null || true
            fi
        fi
    done

    echo "❌ Command failed after $max_attempts attempts: $cmd"
    return 1
}

# Function to build applications with enhanced monitoring
build_applications() {
    echo "🔨 Building applications with Briefcase for ${PLATFORM}..."

    # Verify briefcase installation
    if ! command -v briefcase >/dev/null 2>&1; then
        echo "📦 Installing Briefcase..."
        retry_command "pip install briefcase>=0.3.21" 3 10
    fi

    # Validate project structure
    if [ ! -f "pyproject.toml" ]; then
        echo "❌ pyproject.toml not found"
        exit 1
    fi

    # Clean environment
    rm -rf build/*/logs build/*/temp* dist/temp* .briefcase-* 2>/dev/null || true

    # Determine app format
    case "${PLATFORM}" in
        linux)
            APP_FORMAT="system"
            ;;
        windows)
            APP_FORMAT="app"
            ;;
        *)
            echo "❌ Unsupported platform: ${PLATFORM}"
            return 1
            ;;
    esac

    echo "📋 Building for ${PLATFORM} with format ${APP_FORMAT}"

    # Create and build applications
    retry_command "briefcase create ${PLATFORM} ${APP_FORMAT} -a server --no-input" 3 15
    retry_command "briefcase create ${PLATFORM} ${APP_FORMAT} -a r2midi-client --no-input" 3 15

    retry_command "briefcase build ${PLATFORM} ${APP_FORMAT} -a server --no-input" 3 20 600
    retry_command "briefcase build ${PLATFORM} ${APP_FORMAT} -a r2midi-client --no-input" 3 20 600

    # Find built applications
    case "${PLATFORM}" in
        linux)
            SERVER_PATTERN="build/server/ubuntu/*/server-*/usr/bin/server*"
            CLIENT_PATTERN="build/r2midi-client/ubuntu/*/r2midi-client-*/usr/bin/r2midi-client*"
            ;;
        windows)
            SERVER_PATTERN="build/server/windows/app/src/server.exe"
            CLIENT_PATTERN="build/r2midi-client/windows/app/src/r2midi-client.exe"
            ;;
    esac

    # Locate applications safely
    SERVER_APP_PATH=""
    CLIENT_APP_PATH=""

    while IFS= read -r -d '' app_path; do
        if [ -f "$app_path" ] && [ -x "$app_path" ]; then
            SERVER_APP_PATH="$(realpath "$app_path")"
            echo "✅ Server app found: $SERVER_APP_PATH"
            break
        fi
    done < <(find . -path "$SERVER_PATTERN" -type f -executable -print0 2>/dev/null)

    while IFS= read -r -d '' app_path; do
        if [ -f "$app_path" ] && [ -x "$app_path" ]; then
            CLIENT_APP_PATH="$(realpath "$app_path")"
            echo "✅ Client app found: $CLIENT_APP_PATH"
            break
        fi
    done < <(find . -path "$CLIENT_PATTERN" -type f -executable -print0 2>/dev/null)

    # Create artifacts
    mkdir -p build/artifacts
    [ -n "$SERVER_APP_PATH" ] && [ -f "$SERVER_APP_PATH" ] && cp "$SERVER_APP_PATH" build/artifacts/ 2>/dev/null || true
    [ -n "$CLIENT_APP_PATH" ] && [ -f "$CLIENT_APP_PATH" ] && cp "$CLIENT_APP_PATH" build/artifacts/ 2>/dev/null || true

    # Generate build info
    cat > build/artifacts/build-info.txt << BUILD_INFO_EOF
R2MIDI Briefcase Build Information
==================================

Platform: ${PLATFORM}
Build Type: ${BUILD_TYPE:-development}
Version: ${APP_VERSION:-1.0.0}
Method: Briefcase
Format: ${APP_FORMAT}
Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Build Results:
Server App: ${SERVER_APP_PATH:-Not found}
Client App: ${CLIENT_APP_PATH:-Not found}
BUILD_INFO_EOF

    echo "✅ Briefcase build process completed"
}

# Export variables for GitHub Actions
export SERVER_APP_PATH
export CLIENT_APP_PATH

echo "🔧 Enhanced Briefcase build script loaded for ${PLATFORM:-unknown}"
EOF

    chmod +x "$PROJECT_ROOT/.github/scripts/build-briefcase.sh"
    print_status $GREEN "✅ Enhanced Briefcase build script deployed"
}

# Main deployment function
main() {
    print_status $BLUE "🚀 Starting resilient build fixes deployment..."

    # Change to project directory
    cd "$PROJECT_ROOT"

    # Execute deployment steps
    validate_project
    create_backup
    deploy_macos_script
    deploy_briefcase_script

    print_status $GREEN "✅ Deployment completed successfully!"
    print_status $BLUE "📋 Summary:"
    echo "  - Enhanced macOS build script with py2app conflict resolution"
    echo "  - Improved Briefcase script with broken pipe fixes"
    echo "  - Created backup at: $BACKUP_DIR"

    print_status $YELLOW "🔄 Next steps:"
    echo "  1. Test the build scripts locally"
    echo "  2. Commit the changes to your repository"
    echo "  3. Monitor GitHub Actions for improved builds"
}

# Run the main function
main "$@"
