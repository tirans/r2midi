#!/bin/bash
set -euo pipefail

# build-local-with-pkg-builder.sh - Local build with macOS-Pkg-Builder
# Usage: ./scripts/build-local-with-pkg-builder.sh [version] [build_type]

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"  # Changed default from production to production

echo "🏗️  R2MIDI Local Build with macOS-Pkg-Builder"
echo "============================================="
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script must be run on macOS"
        exit 1
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
    
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is required but not installed"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Clean environment
clean_environment() {
    log_info "Cleaning build environment..."
    
    rm -rf build_client build_server artifacts
    rm -rf build dist
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    
    log_success "Environment cleaned"
}

# Setup virtual environments
setup_venvs() {
    log_info "Setting up virtual environments..."
    
    if [ -f "./setup-virtual-environments.sh" ]; then
        ./setup-virtual-environments.sh --use-uv
        log_success "Virtual environments setup completed"
    else
        log_warning "setup-virtual-environments.sh not found, manual setup required"
    fi
}

# Build applications
build_apps() {
    log_info "Building applications..."
    
    # Build server
    log_info "Building server application..."
    if ./build-server-local.sh --version "$VERSION" --build-type "$BUILD_TYPE"; then
        log_success "Server application built"
    else
        log_error "Server application build failed"
        return 1
    fi
    
    # Build client
    log_info "Building client application..."
    if ./build-client-local.sh --version "$VERSION" --build-type "$BUILD_TYPE"; then
        log_success "Client application built"
    else
        log_error "Client application build failed"
        return 1
    fi
}

# Install macOS-Pkg-Builder
install_pkg_builder() {
    log_info "Installing macOS-Pkg-Builder..."
    
    # Check if already installed
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macOS-Pkg-Builder is already installed"
        local version=$(macos-pkg-builder --version 2>/dev/null || echo "unknown")
        log_info "Version: $version"
    else
        log_info "Installing via pip..."
        if pip3 install macos-pkg-builder; then
            log_success "macOS-Pkg-Builder installed successfully"
        else
            log_warning "Global install failed, trying user install..."
            if pip3 install --user macos-pkg-builder; then
                log_success "macOS-Pkg-Builder installed (user install)"
                # Add user bin to PATH if needed
                export PATH="$HOME/.local/bin:$PATH"
            else
                log_error "Failed to install macOS-Pkg-Builder"
                return 1
            fi
        fi
    fi
}

# Show results
show_results() {
    log_info "Build Results:"
    echo ""
    
    if [ -d "artifacts" ]; then
        find artifacts -name "*.pkg" | while read pkg; do
            if [ -f "$pkg" ]; then
                local size=$(du -sh "$pkg" | cut -f1)
                log_success "📦 $(basename "$pkg") ($size)"
                
                # Check if signed
                if pkgutil --check-signature "$pkg" >/dev/null 2>&1; then
                    echo "   ✅ Signed"
                else
                    echo "   ℹ️  Unsigned (dev build)"
                fi
            fi
        done
    else
        log_warning "No artifacts directory found"
    fi
}

# Main execution
main() {
    check_prerequisites
    clean_environment
    setup_venvs
    install_pkg_builder
    
    if build_apps; then
        show_results
        echo ""
        log_success "🎉 Build completed successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Test server: open 'build_server/dist/R2MIDI Server.app'"
        echo "  2. Test client: open 'build_client/dist/R2MIDI Client.app'"
        echo "  3. Install PKGs: sudo installer -pkg artifacts/R2MIDI-*-$VERSION.pkg -target /"
        echo "  4. Launch from /Applications/"
    else
        log_error "Build failed"
        exit 1
    fi
}

# Run with all arguments
main "$@"
