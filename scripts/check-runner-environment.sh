#!/bin/bash
set -euo pipefail

# check-runner-environment.sh - Check if environment supports macOS-Pkg-Builder
# Usage: ./scripts/check-runner-environment.sh

echo "🔍 Checking Runner Environment for macOS-Pkg-Builder"
echo "=================================================="

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

# Detect runner type
detect_runner_type() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        if [ -n "${RUNNER_NAME:-}" ]; then
            if [[ "$RUNNER_NAME" == *"GitHub Actions"* ]]; then
                echo "GitHub Actions (hosted)"
            else
                echo "Self-hosted"
            fi
        else
            echo "GitHub Actions (unknown type)"
        fi
    else
        echo "Local development"
    fi
}

# Check macOS version
check_macos_version() {
    local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    local major_version=$(echo "$macos_version" | cut -d. -f1)
    
    log_info "macOS Version: $macos_version"
    
    if [ "$major_version" -ge 12 ]; then
        log_success "macOS version is compatible (12.0+)"
        return 0
    elif [ "$major_version" -ge 10 ]; then
        local minor_version=$(echo "$macos_version" | cut -d. -f2)
        if [ "$major_version" -eq 10 ] && [ "$minor_version" -ge 15 ]; then
            log_success "macOS version is compatible (10.15+)"
            return 0
        else
            log_warning "macOS version may have limited compatibility"
            return 1
        fi
    else
        log_error "macOS version is too old"
        return 1
    fi
}

# Check Python and pip
check_python() {
    log_info "Checking Python environment..."
    
    if command -v python3 >/dev/null 2>&1; then
        local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        log_success "Python 3 found: $python_version"
        
        # Check if version is 3.8+
        local major=$(echo "$python_version" | cut -d. -f1)
        local minor=$(echo "$python_version" | cut -d. -f2)
        
        if [ "$major" -eq 3 ] && [ "$minor" -ge 8 ]; then
            log_success "Python version is compatible (3.8+)"
        else
            log_warning "Python version may be too old (need 3.8+)"
        fi
    else
        log_error "Python 3 not found"
        return 1
    fi
    
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version=$(pip3 --version 2>&1 | cut -d' ' -f2)
        log_success "pip3 found: $pip_version"
    else
        log_error "pip3 not found"
        return 1
    fi
}

# Check development tools
check_dev_tools() {
    log_info "Checking development tools..."
    
    local tools=("security" "codesign" "productbuild" "pkgutil" "xcrun")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "$tool found"
        else
            missing_tools+=("$tool")
            log_error "$tool not found"
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "All required development tools are available"
        return 0
    else
        log_error "Missing tools: ${missing_tools[*]}"
        log_info "Install Xcode Command Line Tools: xcode-select --install"
        return 1
    fi
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity to PyPI..."
    
    if curl -s --max-time 10 https://pypi.org/simple/ >/dev/null 2>&1; then
        log_success "PyPI is accessible"
        return 0
    else
        log_error "Cannot reach PyPI"
        log_info "Check network connectivity and firewall settings"
        return 1
    fi
}

# Test pip install (dry run)
test_pip_install() {
    log_info "Testing pip install capabilities..."
    
    # Try to get package info without installing
    if pip3 show macos-pkg-builder >/dev/null 2>&1; then
        local version=$(pip3 show macos-pkg-builder | grep Version | cut -d' ' -f2)
        log_success "macos-pkg-builder is already installed: $version"
    else
        log_info "Testing if we can install macos-pkg-builder..."
        if pip3 install --dry-run macos-pkg-builder >/dev/null 2>&1; then
            log_success "pip install test successful"
        else
            log_warning "pip install test failed - trying user install"
            if pip3 install --user --dry-run macos-pkg-builder >/dev/null 2>&1; then
                log_success "pip install --user test successful"
            else
                log_error "Both global and user pip install tests failed"
                return 1
            fi
        fi
    fi
}

# Check disk space
check_disk_space() {
    log_info "Checking available disk space..."
    
    local available_gb=$(df -g . 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    
    if [ "$available_gb" -gt 5 ]; then
        log_success "Sufficient disk space: ${available_gb}GB available"
    elif [ "$available_gb" -gt 2 ]; then
        log_warning "Low disk space: ${available_gb}GB available (recommend 5GB+)"
    else
        log_error "Insufficient disk space: ${available_gb}GB available"
        return 1
    fi
}

# Main execution
main() {
    local runner_type=$(detect_runner_type)
    log_info "Runner Type: $runner_type"
    echo ""
    
    local checks_passed=0
    local checks_failed=0
    
    # Run all checks
    local check_functions=(
        "check_macos_version"
        "check_python"
        "check_dev_tools"
        "check_network"
        "test_pip_install"
        "check_disk_space"
    )
    
    for check_func in "${check_functions[@]}"; do
        echo ""
        if $check_func; then
            checks_passed=$((checks_passed + 1))
        else
            checks_failed=$((checks_failed + 1))
        fi
    done
    
    # Summary
    echo ""
    echo "=============================="
    echo "ENVIRONMENT CHECK SUMMARY"
    echo "=============================="
    log_info "Runner: $runner_type"
    log_info "Checks passed: $checks_passed"
    if [ $checks_failed -gt 0 ]; then
        log_error "Checks failed: $checks_failed"
    else
        log_success "Checks failed: $checks_failed"
    fi
    
    if [ $checks_failed -eq 0 ]; then
        echo ""
        log_success "🎉 Environment is ready for macOS-Pkg-Builder!"
        echo ""
        echo "✅ You can proceed with:"
        echo "   ./scripts/setup-macos-pkg-builder.sh"
        return 0
    else
        echo ""
        log_error "❌ Environment needs setup before using macOS-Pkg-Builder"
        echo ""
        echo "🔧 For self-hosted runners, ensure:"
        echo "   1. Install Xcode Command Line Tools: xcode-select --install"
        echo "   2. Install Python 3.8+: https://python.org"
        echo "   3. Ensure network access to PyPI"
        echo "   4. Have sufficient disk space (5GB+)"
        echo ""
        echo "🔧 For GitHub Actions, use 'macos-latest' or newer runner"
        return 1
    fi
}

# Run main function
main "$@"
