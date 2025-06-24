#!/bin/bash
set -euo pipefail

# setup-macos-pkg-builder.sh - Complete setup for macOS-Pkg-Builder integration
# Usage: ./scripts/setup-macos-pkg-builder.sh

echo "🚀 Setting up macOS-Pkg-Builder Integration"
echo "==========================================="

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
log_step() { echo ""; echo -e "${BLUE}🔄 $1${NC}"; echo "$(printf '=%.0s' {1..50})"; }

# Step 1: Make all scripts executable
make_scripts_executable() {
    log_step "Making scripts executable"
    
    local scripts=(
        "scripts/build-pkg-with-macos-builder.sh"
        "scripts/build-local-with-pkg-builder.sh"
        "scripts/cleanup-old-build-scripts.sh"
        "scripts/quick-test-pkg-builder.sh"
        "scripts/setup-macos-pkg-builder.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            chmod +x "$script"
            log_success "Made $script executable"
        else
            log_warning "$script not found"
        fi
    done
}

# Step 2: Test the setup
test_setup() {
    log_step "Testing the setup"
    
    if [ -f "scripts/quick-test-pkg-builder.sh" ]; then
        ./scripts/quick-test-pkg-builder.sh
    else
        log_error "Quick test script not found"
        return 1
    fi
}

# Step 3: Show cleanup preview
show_cleanup_preview() {
    log_step "Showing cleanup preview"
    
    if [ -f "scripts/cleanup-old-build-scripts.sh" ]; then
        echo ""
        log_info "Files that can be removed (dry run):"
        ./scripts/cleanup-old-build-scripts.sh --dry-run
    else
        log_error "Cleanup script not found"
    fi
}

# Step 4: Install macOS-Pkg-Builder
install_macos_pkg_builder() {
    log_step "Installing macOS-Pkg-Builder"
    
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macOS-Pkg-Builder is already installed"
        local version=$(macos-pkg-builder --version 2>/dev/null || echo "unknown")
        log_info "Version: $version"
    else
        log_info "Installing macOS-Pkg-Builder via pip..."
        if pip3 install macos-pkg-builder; then
            log_success "macOS-Pkg-Builder installed successfully"
        else
            log_info "Trying user install..."
            if pip3 install --user macos-pkg-builder; then
                log_success "macOS-Pkg-Builder installed (user install)"
                log_info "You may need to add ~/.local/bin to your PATH"
            else
                log_error "Failed to install macOS-Pkg-Builder"
                return 1
            fi
        fi
    fi
}

# Step 5: Update build scripts to not create PKGs
update_build_scripts() {
    log_step "Checking build scripts for --no-pkg support"
    
    local build_scripts=("build-server-local.sh" "build-client-local.sh")
    
    for script in "${build_scripts[@]}"; do
        if [ -f "$script" ]; then
            if grep -q "\-\-no-pkg" "$script"; then
                log_success "$script already supports --no-pkg flag"
            else
                log_warning "$script may need --no-pkg flag support"
                log_info "You may need to add --no-pkg flag support to $script"
            fi
        else
            log_warning "$script not found"
        fi
    done
}

# Main execution
main() {
    log_info "This script will set up the macOS-Pkg-Builder integration for your R2MIDI project"
    echo ""
    
    make_scripts_executable
    install_macos_pkg_builder
    update_build_scripts
    
    # Run tests
    if test_setup; then
        log_success "Setup completed successfully!"
        
        show_cleanup_preview
        
        echo ""
        log_step "Next Steps"
        echo ""
        echo "1. 📋 Review the cleanup preview above"
        echo "2. 🧪 Test a local build:"
        echo "   ./scripts/build-local-with-pkg-builder.sh 1.0.0 dev"
        echo ""
        echo "3. 🗑️  When ready, cleanup old scripts:"
        echo "   ./scripts/cleanup-old-build-scripts.sh"
        echo ""
        echo "4. 🚀 Test GitHub Actions workflow:"
        echo "   - Push to a test branch"
        echo "   - Trigger workflow manually from GitHub"
        echo ""
        echo "5. 📚 Update your documentation:"
        echo "   - Update README.md with new build instructions"
        echo "   - Update team documentation"
        echo ""
        log_success "macOS-Pkg-Builder integration is ready!"
        
    else
        log_error "Setup failed during testing"
        return 1
    fi
}

# Run main function
main "$@"
