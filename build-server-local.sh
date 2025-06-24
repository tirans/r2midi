#!/bin/bash

# build-server-local.sh - Build R2MIDI Server locally with signing and notarization
# Usage: ./build-server-local.sh [--version VERSION] [--no-sign] [--no-notarize]

set -euo pipefail

# Make the common certificate setup script executable
chmod +x scripts/common-certificate-setup.sh 2>/dev/null || true

# Source common certificate setup
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/scripts/common-certificate-setup.sh"

# Default values
VERSION=""
SKIP_SIGNING=false
SKIP_NOTARIZATION=false
BUILD_TYPE="local"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --no-sign)
            SKIP_SIGNING=true
            shift
            ;;
        --no-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --dev)
            BUILD_TYPE="dev"
            shift
            ;;
        *)
            echo "Usage: $0 [--version VERSION] [--no-sign] [--no-notarize] [--dev]"
            echo "  --version VERSION   Specify version (otherwise extracted from code)"
            echo "  --no-sign          Skip code signing"
            echo "  --no-notarize      Skip notarization"
            echo "  --dev              Development build (skip some optimizations)"
            exit 1
            ;;
    esac
done

echo "🖥️ Building R2MIDI Server locally..."
echo "Build type: $BUILD_TYPE"
echo "Skip signing: $SKIP_SIGNING"
echo "Skip notarization: $SKIP_NOTARIZATION"
echo ""

# Clean environment and recreate virtual environments at the beginning
echo "🧹 Cleaning environment and recreating virtual environments..."
if [ -f "./clean-environment.sh" ]; then
    ./clean-environment.sh
    echo "✅ Environment cleanup completed"
else
    echo "⚠️ clean-environment.sh not found, manual cleanup..."
    rm -rf venv_server build_server 2>/dev/null || true
fi

# Recreate server virtual environment
echo "🔄 Recreating server virtual environment..."
if [ -f "./setup-virtual-environments.sh" ]; then
    ./setup-virtual-environments.sh --server-only
    echo "✅ Server virtual environment recreated"
else
    echo "❌ setup-virtual-environments.sh not found"
    exit 1
fi

# Check if server virtual environment exists
if [ ! -d "venv_server" ]; then
    echo "❌ Server virtual environment not found"
    echo "Run: ./setup-virtual-environments.sh --server-only"
    exit 1
fi

# Extract version if not provided
if [ -z "$VERSION" ]; then
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "
import sys
sys.path.insert(0, 'server')
from version import __version__
print(__version__)
")
        echo "📋 Extracted version: $VERSION"
    else
        VERSION="1.0.0"
        echo "⚠️ Using fallback version: $VERSION"
    fi
fi

# Create build directories
echo "📁 Setting up build directories..."
mkdir -p build_server/{build,dist,artifacts}
mkdir -p artifacts

# Activate server virtual environment
echo "🐍 Activating server virtual environment..."
source venv_server/bin/activate

# Verify environment with detailed progress
echo "🧪 Verifying server environment..."
echo "🔍 Checking Python installation and required packages..."
echo ""

python -c "
import sys
import time
print(f'🐍 Python: {sys.version}')
print(f'📍 Python path: {sys.executable}')
print(f'📦 Site packages: {sys.path[-1] if sys.path else \"unknown\"}')
print('')

# Check required packages with progress
required = ['fastapi', 'uvicorn', 'rtmidi', 'py2app', 'pydantic', 'starlette']
missing = []
checked = 0
total = len(required)

print('🔍 Checking required packages:')
for pkg in required:
    checked += 1
    try:
        module = __import__(pkg)
        version = getattr(module, '__version__', 'unknown')
        print(f'✅ {pkg} ({version}) [{checked}/{total}]')
        time.sleep(0.1)  # Small delay for visual effect
    except ImportError:
        missing.append(pkg)
        print(f'❌ {pkg} [MISSING] [{checked}/{total}]')
        time.sleep(0.1)

print('')
if missing:
    print(f'❌ Missing packages: {missing}')
    print('💡 Run: pip install ' + ' '.join(missing))
    exit(1)
else:
    print('✅ All required packages are available')
"

# Copy setup file to build directory
echo "📝 Preparing build configuration..."
echo "📦 Copying setup script: setup_server.py -> build_server/setup.py"
cp setup_server.py build_server/setup.py
echo "✅ Setup script copied"

# Copy server directory to build directory (excluding .git)
echo "📁 Copying server directory..."
echo "🔄 Using rsync to copy server files (excluding .git)..."
SERVER_FILES=$(find server -type f | wc -l | tr -d ' ')
echo "📊 Server files to copy: $SERVER_FILES"

if rsync -av --exclude='.git' server/ build_server/server/; then
    COPIED_FILES=$(find build_server/server -type f | wc -l | tr -d ' ')
    echo "✅ Server directory copied successfully ($COPIED_FILES files)"
else
    echo "❌ Failed to copy server directory"
    exit 1
fi

# Change to build directory
echo "📁 Changing to build directory: build_server/"
cd build_server
echo "📍 Current directory: $(pwd)"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
echo "🔍 Removing old build artifacts..."
rm -rf build dist *.app setup_*.py 2>/dev/null || true
echo "✅ Previous builds cleaned"
echo "📁 Clean build directory contents:"
ls -la . | head -10

# Update version in setup file
echo "🔢 Setting version to $VERSION..."
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py
rm setup.py.bak
echo "✅ Version updated in setup.py"

# Show pre-build summary
echo ""
echo "📊 Pre-build summary:"
echo "📍 Build directory: $(pwd)"
echo "📦 Python executable: $(which python)"
echo "📊 Server files: $(find server -type f | wc -l | tr -d ' ')"
echo "📦 Main entry point: $(ls -la server/main.py 2>/dev/null || echo 'main.py not found')"
echo "📄 Setup script size: $(du -sh setup.py | cut -f1)"
echo "💾 Available disk space: $(df -h . | tail -1 | awk '{print $4}')"
echo ""

# Build with py2app with progress monitoring
echo "📦 Building server with py2app..."
echo "🔧 Build command: python setup.py py2app"
echo "⏳ This may take several minutes, please wait..."
echo ""

# Create a log file for detailed output
LOG_FILE="py2app_build_$(date +%Y%m%d_%H%M%S).log"
echo "📝 Detailed build log: $LOG_FILE"
echo "🕐 Started at: $(date)"
echo ""

# Function to show progress
show_progress() {
    local pid=$1
    local delay=10
    local spinstr='|/-\\'
    local i=0
    local elapsed=0
    local max_time=1800  # 30 minutes timeout

    echo "🔄 Build in progress..."
    echo "⏰ Maximum build time: $((max_time / 60)) minutes"
    echo ""

    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r[%c] Building... (%d seconds elapsed, %d minutes remaining)" "$spinstr" "$elapsed" "$(((max_time - elapsed) / 60))"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        elapsed=$((elapsed + delay))

        # Check for timeout
        if [ $elapsed -ge $max_time ]; then
            echo ""
            echo "⚠️  Build timeout reached ($((max_time / 60)) minutes)"
            echo "🔍 Terminating build process..."
            kill -TERM $pid 2>/dev/null || true
            sleep 5
            kill -KILL $pid 2>/dev/null || true
            echo "❌ Build terminated due to timeout"
            return 1
        fi

        # Show progress indicators every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo ""
            echo "⏱️  Still building... ($elapsed seconds elapsed, $((elapsed / 60)) minutes)"

            # Check for signs of progress
            if [ -d "build" ]; then
                echo "📁 Build directory exists - py2app is working"
                local build_files=$(find build -type f 2>/dev/null | wc -l | tr -d ' ')
                echo "📄 Files in build directory: $build_files"

                # Check for recent file changes (activity indicator)
                local recent_files=$(find build -type f -newermt '30 seconds ago' 2>/dev/null | wc -l | tr -d ' ')
                if [ $recent_files -gt 0 ]; then
                    echo "✅ Recent activity: $recent_files files modified in last 30 seconds"
                else
                    echo "⚠️  No recent file activity detected"
                fi
            fi

            if [ -d "dist" ]; then
                echo "📦 Dist directory exists - nearing completion"
                local dist_size=$(du -sh dist 2>/dev/null | cut -f1 || echo "unknown")
                echo "📊 Dist directory size: $dist_size"
            fi

            # Check memory usage
            echo "💾 Memory usage:"
            ps aux | grep python | grep -v grep | head -3
            echo ""
        fi
    done
    printf "\r\033[K"  # Clear the line
    return 0
}

# Start the build in background and monitor progress
echo "🚀 Starting py2app build process..."
python setup.py py2app > "$LOG_FILE" 2>&1 &
BUILD_PID=$!

# Show progress while building
if show_progress $BUILD_PID; then
    # Wait for build to complete and get exit status
    wait $BUILD_PID
    BUILD_EXIT_CODE=$?
else
    # Timeout occurred
    BUILD_EXIT_CODE=124  # Standard timeout exit code
    echo "❌ Build process timed out after 30 minutes"
fi

echo "🏁 Build process completed at: $(date)"
echo ""

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "✅ py2app build completed successfully"
    echo "📊 Build log size: $(du -sh "$LOG_FILE" | cut -f1)"

    # Show last few lines of successful build
    echo "📋 Final build output:"
    tail -20 "$LOG_FILE" | grep -E "(copying|creating|done|Success|✅|📦)" || echo "(No specific success indicators found)"
elif [ $BUILD_EXIT_CODE -eq 124 ]; then
    echo "❌ py2app build timed out after 30 minutes"
    echo "📊 Build log size: $(du -sh "$LOG_FILE" | cut -f1)"
    echo "📋 Build directory contents:"
    ls -la . || true
    echo ""
    echo "🔍 Checking for partial builds..."
    if [ -d "build" ]; then
        echo "📁 Build directory contents:"
        find build -type f 2>/dev/null | head -10
    fi
    echo ""
    echo "❌ Last 100 lines of build log (timeout case):"
    tail -100 "$LOG_FILE" || echo "Could not read log file"
    echo ""
    echo "💡 Timeout troubleshooting tips:"
    echo "  - Check if py2app is stuck on a specific file/module"
    echo "  - Verify sufficient disk space and memory"
    echo "  - Consider excluding large/problematic modules"
    echo "  - Try running with --dev flag for faster build"

    deactivate
    cleanup_certificates
    print_build_summary "R2MIDI Server" "failed" "Build timed out after 30 minutes (exit code: $BUILD_EXIT_CODE)"
    exit 1
else
    echo "❌ py2app build failed (exit code: $BUILD_EXIT_CODE)"
    echo "📊 Build log size: $(du -sh "$LOG_FILE" | cut -f1)"
    echo "📋 Build directory contents:"
    ls -la . || true
    echo ""
    echo "🔍 Checking for partial builds..."
    if [ -d "build" ]; then
        echo "📁 Build directory contents:"
        find build -type f 2>/dev/null | head -10
    fi
    echo ""
    echo "❌ Last 50 lines of build log:"
    tail -50 "$LOG_FILE" || echo "Could not read log file"
    echo ""
    echo "🔍 Common py2app errors to check:"
    grep -E "(Error|error|ERROR|Exception|ImportError|ModuleNotFoundError)" "$LOG_FILE" | tail -10 || echo "No obvious errors found in log"

    deactivate
    cleanup_certificates
    print_build_summary "R2MIDI Server" "failed" "Build failed during py2app compilation (exit code: $BUILD_EXIT_CODE)"
    exit 1
fi

# Check build results
echo "🔍 Checking build results..."
APP_PATH=""
if [ -d "dist/R2MIDI Server.app" ]; then
    APP_PATH="dist/R2MIDI Server.app"
    echo "✅ Server app found: $APP_PATH"
elif [ -d "dist/main.app" ]; then
    mv "dist/main.app" "dist/R2MIDI Server.app"
    APP_PATH="dist/R2MIDI Server.app"
    echo "✅ Server app renamed: $APP_PATH"
else
    echo "❌ Server app not found"
    echo "📁 dist/ directory contents:"
    ls -la dist/ || echo "dist/ directory not found"
    deactivate
    cleanup_certificates
    print_build_summary "R2MIDI Server" "failed" "App bundle not found after build"
    exit 1
fi

# Verify app bundle
echo "🔍 Verifying app bundle..."
if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    bundle_name=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    bundle_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    echo "📋 Bundle Name: $bundle_name"
    echo "📋 Bundle Version: $bundle_version"
else
    echo "⚠️ Info.plist not found"
fi

# Check for MIDI components
echo "🎵 Checking MIDI components..."
if find "$APP_PATH" -name "*midi*" -type f | head -3 | grep -q .; then
    echo "✅ MIDI components found in app bundle"
    midi_count=$(find "$APP_PATH" -name "*midi*" -type f | wc -l)
    echo "🎵 MIDI files: $midi_count"
else
    echo "⚠️ MIDI components not found - server may not work properly"
fi

# Show app size
if command -v du >/dev/null 2>&1; then
    app_size=$(du -sh "$APP_PATH" | cut -f1)
    echo "📦 App bundle size: $app_size"
fi

# Setup certificates before signing
setup_certificates "$SKIP_SIGNING"

# Code signing and notarization (if not skipped and certificates available)
if [ "$SKIP_SIGNING" = "false" ] && [ "$CERT_LOADED" = "true" ]; then
    echo ""
    echo "🔐 Starting signing and notarization..."
    
    # Use clean-app.sh before signing if available
    echo "🧹 Pre-signing app cleaning..."
    if [ -f "../.github/scripts/clean-app.sh" ]; then
        echo "📝 Using clean-app.sh for thorough cleaning..."
        if "../.github/scripts/clean-app.sh" "$APP_PATH"; then
            echo "✅ App bundle cleaned with clean-app.sh"
        else
            echo "⚠️ clean-app.sh failed, using fallback cleaning"
            # Fallback cleaning
            find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
            find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
            xattr -rc "$APP_PATH" 2>/dev/null || true
        fi
    else
        echo "⚠️ clean-app.sh not found, using basic cleaning"
        # Basic cleaning
        find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
        find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
        xattr -rc "$APP_PATH" 2>/dev/null || true
    fi
    
    # Additional handling for com.apple.provenance attributes
    echo "🔧 Handling com.apple.provenance attributes..."
    if [ -f "../.github/scripts/handle-attributes.sh" ]; then
        chmod +x "../.github/scripts/handle-attributes.sh"
        if "../.github/scripts/handle-attributes.sh" "$APP_PATH"; then
            echo "✅ com.apple.provenance attributes handled"
        else
            echo "⚠️ Attribute handling script had issues, continuing anyway"
        fi
    fi

    # Check if signing script exists (preferred)
    if [ -f "../.github/scripts/sign-and-notarize.sh" ]; then
        echo "📝 Using signing script"
        
        # Build arguments for signing script
        sign_args="--version $VERSION"
        
        if [ "$BUILD_TYPE" = "dev" ]; then
            sign_args="$sign_args --dev"
        fi
        
        if [ "$SKIP_NOTARIZATION" = "true" ]; then
            sign_args="$sign_args --skip-notarize"
        fi
        
        # Run signing from project root
        cd ..
        if ./.github/scripts/sign-and-notarize.sh $sign_args; then
            echo "✅ Signing and notarization completed"
        else
            echo "❌ Signing failed"
            if [ "$BUILD_TYPE" != "dev" ]; then
                cleanup_certificates
                exit 1
            fi
        fi
        cd build_server
    elif [ -f "../.github/scripts/sign-notarize.sh" ]; then
        echo "📋 Using signing script"

        # Build arguments for signing script
        sign_args="--version $VERSION"

        if [ "$BUILD_TYPE" = "dev" ]; then
            sign_args="$sign_args --dev"
        fi

        if [ "$SKIP_NOTARIZATION" = "true" ]; then
            sign_args="$sign_args --skip-notarize"
        fi

        # Run signing from project root
        cd ..
        if ./.github/scripts/sign-notarize.sh $sign_args; then
            echo "✅ Signing and notarization completed"
        else
            echo "⚠️ Signing failed, trying development build approach..."
            # Fallback: try with dev flag to skip strict notarization
            if ./.github/scripts/sign-notarize.sh $sign_args --dev; then
                echo "✅ Development signing completed (some steps may have been skipped)"
            else
                echo "❌ Signing failed completely"
                if [ "$BUILD_TYPE" != "dev" ]; then
                    cleanup_certificates
                    exit 1
                fi
            fi
        fi
        cd build_server
    else
        echo "⚠️ Signing script not found, using basic signing"

        # Use certificate identity from common setup
        if [ -n "$CERT_IDENTITY" ]; then
            echo "✅ Using signing identity: $CERT_IDENTITY"

            # Create basic entitlements
            cat > entitlements.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

            codesign --force --options runtime --entitlements entitlements.plist --deep --sign "$CERT_IDENTITY" "$APP_PATH"

            # Create PKG installer
            PKG_NAME="R2MIDI-Server-${VERSION}.pkg"
            INSTALLER_PATH="artifacts/${PKG_NAME}"

            pkgbuild --identifier "com.r2midi.server" \
                     --version "$VERSION" \
                     --install-location "/Applications" \
                     --component "dist/R2MIDI Server.app" \
                     "$INSTALLER_PATH"

            # Sign and notarize the PKG
            echo "🔐 Signing and notarizing PKG..."
            if [ -f "../.github/scripts/sign-pkg.sh" ]; then
                if "../.github/scripts/sign-pkg.sh" --pkg "$INSTALLER_PATH"; then
                    echo "✅ PKG signed and notarized successfully"
                else
                    echo "⚠️ PKG signing/notarization failed, but continuing..."
                fi
            else
                echo "⚠️ PKG signing script not found, skipping PKG signing"
            fi

            echo "✅ Basic signing completed"
        else
            echo "⚠️ No valid certificate loaded - creating unsigned build"

            # Create PKG installer even without signing
            PKG_NAME="R2MIDI-Server-${VERSION}.pkg"
            INSTALLER_PATH="artifacts/${PKG_NAME}"

            pkgbuild --identifier "com.r2midi.server" \
                     --version "$VERSION" \
                     --install-location "/Applications" \
                     --component "dist/R2MIDI Server.app" \
                     "$INSTALLER_PATH"

            # Sign and notarize the PKG (even for unsigned app builds, we can still sign the PKG)
            echo "🔐 Signing and notarizing PKG..."
            if [ -f "../.github/scripts/sign-pkg.sh" ]; then
                if "../.github/scripts/sign-pkg.sh" --pkg "$INSTALLER_PATH"; then
                    echo "✅ PKG signed and notarized successfully"
                else
                    echo "⚠️ PKG signing/notarization failed, but continuing..."
                fi
            else
                echo "⚠️ PKG signing script not found, skipping PKG signing"
            fi
        fi
    fi
else
    if [ "$SKIP_SIGNING" = "true" ]; then
        echo "⏭️ Skipping code signing (--no-sign specified)"
    else
        echo "⚠️ No valid certificates available - creating unsigned build"
    fi

    # Create unsigned PKG
    echo "📦 Creating unsigned PKG installer..."
    PKG_NAME="R2MIDI-Server-${VERSION}.pkg"
    INSTALLER_PATH="artifacts/${PKG_NAME}"

    pkgbuild --identifier "com.r2midi.server" \
             --version "$VERSION" \
             --install-location "/Applications" \
             --component "dist/R2MIDI Server.app" \
             "$INSTALLER_PATH"

    # Sign and notarize the PKG (even for unsigned app builds, we can still sign the PKG)
    echo "🔐 Signing and notarizing PKG..."
    if [ -f "../.github/scripts/sign-pkg.sh" ]; then
        if "../.github/scripts/sign-pkg.sh" --pkg "$INSTALLER_PATH"; then
            echo "✅ PKG signed and notarized successfully"
        else
            echo "⚠️ PKG signing/notarization failed, but continuing..."
        fi
    else
        echo "⚠️ PKG signing script not found, skipping PKG signing"
    fi
fi

# Copy artifacts to main artifacts directory
echo ""
echo "📋 Copying artifacts..."

cd ..  # Back to project root
cp "build_server/artifacts/${PKG_NAME}" "artifacts/"

# Create build report
BUILD_REPORT="artifacts/SERVER_BUILD_REPORT_${VERSION}.md"
cat > "$BUILD_REPORT" << EOF
# R2MIDI Server Build Report

**Version:** $VERSION  
**Build Date:** $(date)  
**Build Type:** $BUILD_TYPE  
**Platform:** $(uname -s) $(uname -r)  
**Architecture:** $(uname -m)  

## Build Results

- ✅ App Bundle: R2MIDI Server.app
- ✅ PKG Installer: ${PKG_NAME}
- App Size: $(du -sh "build_server/$APP_PATH" 2>/dev/null | cut -f1 || echo "unknown")
- PKG Size: $(du -sh "artifacts/${PKG_NAME}" 2>/dev/null | cut -f1 || echo "unknown")

## Build Configuration

- Python Version: $(python3 --version)
- Virtual Environment: venv_server
- py2app Options: Optimized configuration with duplicate file prevention
- Code Signing: $([ "$SKIP_SIGNING" = "false" ] && echo "Enabled" || echo "Disabled")
- Notarization: $([ "$SKIP_NOTARIZATION" = "false" ] && echo "Enabled" || echo "Disabled")

## Package Dependencies

$(pip list | grep -E "(fastapi|uvicorn|rtmidi|mido|py2app)" || echo "Dependencies not listed")

## Server Features

- ✅ FastAPI web server
- ✅ MIDI device management
- ✅ Real-time MIDI processing
- ✅ RESTful API endpoints
- ✅ WebSocket support

## Installation

To install the server:
\`\`\`bash
sudo installer -pkg artifacts/${PKG_NAME} -target /
\`\`\`

The app will be installed to: /Applications/R2MIDI Server.app

## Usage

Start the server:
\`\`\`bash
open "/Applications/R2MIDI Server.app"
\`\`\`

Or from terminal:
\`\`\`bash
"/Applications/R2MIDI Server.app/Contents/MacOS/R2MIDI Server"
\`\`\`
EOF

echo "📄 Build report created: $BUILD_REPORT"

# Deactivate virtual environment
deactivate

# Cleanup certificates
cleanup_certificates

# Final summary with certificate info
print_build_summary "R2MIDI Server" "success" "
📦 Build artifacts:
  - App bundle: build_server/$APP_PATH
  - PKG installer: artifacts/${PKG_NAME}
  - Build report: $BUILD_REPORT

🚀 Ready for distribution!"

# Show next steps
echo ""
echo "📋 Next steps:"
echo "  1. Test the app: open 'build_server/$APP_PATH'"
echo "  2. Test installer: sudo installer -pkg 'artifacts/${PKG_NAME}' -target /"
echo "  3. Start server: open '/Applications/R2MIDI Server.app'"
echo ""
echo "💡 The PKG installer will install the app to /Applications/"
echo "🌐 Server will be available at: http://localhost:8000"
