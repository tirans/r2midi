#!/bin/bash
set -euo pipefail

# test-runner-compatibility.sh - Test macOS-Pkg-Builder on different runner types
# Usage: ./scripts/test-runner-compatibility.sh

echo "🧪 Testing macOS-Pkg-Builder Runner Compatibility"
echo "=============================================="

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

# Detect current environment
detect_environment() {
    local env_type="unknown"
    local runner_info=""
    
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        env_type="github-actions"
        if [ -n "${RUNNER_NAME:-}" ]; then
            if [[ "$RUNNER_NAME" == *"GitHub Actions"* ]]; then
                runner_info="hosted (macos-latest)"
            else
                runner_info="self-hosted ($RUNNER_NAME)"
            fi
        else
            runner_info="unknown runner"
        fi
    else
        env_type="local"
        runner_info="$(whoami)@$(hostname)"
    fi
    
    echo "$env_type|$runner_info"
}

# Test pip install capability
test_pip_install() {
    log_info "Testing pip install capability..."
    
    # Test if we can install without actually installing
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macos-pkg-builder already installed"
        return 0
    fi
    
    # Try dry run
    if pip3 install --dry-run macos-pkg-builder >/dev/null 2>&1; then
        log_success "Global pip install capability confirmed"
        return 0
    elif pip3 install --user --dry-run macos-pkg-builder >/dev/null 2>&1; then
        log_success "User pip install capability confirmed"
        return 0
    else
        log_error "pip install capability test failed"
        return 1
    fi
}

# Test actual installation
test_actual_install() {
    log_info "Testing actual installation..."
    
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macos-pkg-builder is already installed"
        local version=$(macos-pkg-builder --version 2>/dev/null || echo "unknown")
        log_info "Version: $version"
        return 0
    fi
    
    # Try installing
    if pip3 install macos-pkg-builder >/dev/null 2>&1; then
        log_success "Global installation successful"
    elif pip3 install --user macos-pkg-builder >/dev/null 2>&1; then
        log_success "User installation successful"
        export PATH="$HOME/.local/bin:$PATH"
    else
        log_error "Installation failed"
        return 1
    fi
    
    # Verify
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        local version=$(macos-pkg-builder --version 2>/dev/null || echo "unknown")
        log_success "Installation verified: $version"
        return 0
    else
        log_error "Installation verification failed"
        return 1
    fi
}

# Run compatibility matrix
run_compatibility_test() {
    local env_info=$(detect_environment)
    local env_type=$(echo "$env_info" | cut -d'|' -f1)
    local runner_info=$(echo "$env_info" | cut -d'|' -f2)
    
    echo ""
    log_info "Environment: $env_type"
    log_info "Runner: $runner_info"
    echo ""
    
    # Run environment check first
    if [ -f "scripts/check-runner-environment.sh" ]; then
        log_info "Running environment check..."
        if ./scripts/check-runner-environment.sh; then
            log_success "Environment check passed"
        else
            log_error "Environment check failed"
            return 1
        fi
    fi
    
    echo ""
    
    # Test installation capability
    if test_pip_install; then
        log_success "pip install capability confirmed"
    else
        log_error "pip install capability test failed"
        return 1
    fi
    
    # Test actual installation
    if test_actual_install; then
        log_success "Installation test passed"
    else
        log_error "Installation test failed"
        return 1
    fi
    
    return 0
}

# Generate compatibility report
generate_report() {
    local env_info=$(detect_environment)
    local env_type=$(echo "$env_info" | cut -d'|' -f1)
    local runner_info=$(echo "$env_info" | cut -d'|' -f2)
    
    cat << EOF

======================================
COMPATIBILITY TEST REPORT
======================================
Date: $(date)
Environment: $env_type
Runner: $runner_info
macOS: $(sw_vers -productVersion)
Python: $(python3 --version 2>&1)
Pip: $(pip3 --version 2>&1)

EOF

    if run_compatibility_test; then
        cat << EOF
✅ RESULT: COMPATIBLE

This runner can successfully use macOS-Pkg-Builder.

Next steps:
  1. Run: ./scripts/setup-macos-pkg-builder.sh
  2. Test: ./scripts/build-local-with-pkg-builder.sh 1.0.0 dev

EOF
    else
        cat << EOF
❌ RESULT: NOT COMPATIBLE

This runner needs setup before using macOS-Pkg-Builder.

For self-hosted runners:
  1. Install Xcode Command Line Tools: xcode-select --install
  2. Install Python 3.8+: https://python.org
  3. Ensure network access to PyPI
  4. See: docs/SELF_HOSTED_RUNNER_SETUP.md

For GitHub Actions:
  - Use 'macos-latest' runner
  - Or properly configure self-hosted runner

EOF
    fi
}

# Main execution
main() {
    generate_report
}

# Run main function
main "$@"
