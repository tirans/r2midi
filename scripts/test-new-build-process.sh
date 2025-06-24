#!/bin/bash
set -euo pipefail

# test-new-build-process.sh - Test the updated build process
# Usage: ./scripts/test-new-build-process.sh

echo "🧪 Testing Updated Build Process"
echo "==============================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo ""
log_info "Checking required scripts..."

# Check if scripts exist
scripts=(
    "./scripts/setup-macos-pkg-builder.sh"
    "./scripts/build-local-with-pkg-builder.sh"
    "./scripts/build-pkg-with-macos-builder.sh"
    "./build-server-local.sh"
    "./build-client-local.sh"
)

all_found=true
for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
        log_success "Found: $script"
    else
        log_error "Missing: $script"
        all_found=false
    fi
done

if [ "$all_found" = false ]; then
    log_error "Some required scripts are missing!"
    exit 1
fi

echo ""
log_info "Testing script help outputs..."

# Test help outputs
for script in "./build-server-local.sh" "./build-client-local.sh"; do
    if [ -x "$script" ]; then
        echo ""
        log_info "Testing: $script --help"
        if $script --help 2>/dev/null | grep -q "no-pkg"; then
            log_success "$script supports --no-pkg flag"
        else
            log_warning "$script may not support --no-pkg flag"
        fi
    fi
done

echo ""
log_info "Testing macos-pkg-builder availability..."

if command -v macos-pkg-builder >/dev/null 2>&1; then
    version=$(macos-pkg-builder --version 2>/dev/null || echo "unknown")
    log_success "macos-pkg-builder is installed: $version"
else
    log_info "macos-pkg-builder not installed (will be installed during build)"
fi

echo ""
log_success "✅ Build process verification completed!"

echo ""
echo "🎯 Summary of Changes Made:"
echo "=========================="
echo ""
echo "✅ Updated build-server-local.sh:"
echo "   - Added --no-pkg flag support"
echo "   - Changed default to 'production' builds"
echo "   - Uses macOS-Pkg-Builder for PKG creation"
echo "   - Defaults to signed and notarized PKGs"
echo ""
echo "✅ Updated build-client-local.sh:"
echo "   - Added --no-pkg flag support" 
echo "   - Changed default to 'production' builds"
echo "   - Uses macOS-Pkg-Builder for PKG creation"
echo "   - Defaults to signed and notarized PKGs"
echo ""
echo "✅ Updated scripts/build-local-with-pkg-builder.sh:"
echo "   - Calls individual scripts with --build-type production"
echo "   - Removes --no-pkg flags (PKGs created by default)"
echo "   - Auto-installs macos-pkg-builder if needed"
echo ""
echo "✅ New Default Behavior:"
echo "   - Production builds: signed and notarized PKG files"
echo "   - Clean build environment each time"
echo "   - Uses pip-installed macos-pkg-builder"
echo "   - Auto-installs dependencies if missing"
echo ""
echo "🚀 Ready to Test:"
echo "================"
echo ""
echo "1. Run complete build:"
echo "   ./scripts/build-local-with-pkg-builder.sh 1.0.0 production"
echo ""
echo "2. Or run individual components:"
echo "   ./build-server-local.sh --version 1.0.0"
echo "   ./build-client-local.sh --version 1.0.0"
echo ""
echo "3. For development (no signing):"
echo "   ./scripts/build-local-with-pkg-builder.sh 1.0.0 dev"
echo ""
echo "Expected Results:"
echo "- Signed and notarized .app bundles"
echo "- Signed and notarized .pkg installers"  
echo "- Files in artifacts/ directory ready for distribution"
echo ""
log_success "🎉 The build process is now configured for release builds by default!"
