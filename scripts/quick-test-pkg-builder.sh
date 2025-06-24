#!/bin/bash
set -euo pipefail

# quick-test-pkg-builder.sh - Quick test of the new PKG builder setup
# Usage: ./scripts/quick-test-pkg-builder.sh

echo "🧪 Quick Test: macOS-Pkg-Builder Setup"
echo "====================================="

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

# Test 1: Check if scripts are created and executable
test_scripts() {
    echo ""
    log_info "Testing script creation and permissions..."
    
    local scripts=(
        "scripts/build-pkg-with-macos-builder.sh"
        "scripts/build-local-with-pkg-builder.sh"
        "scripts/cleanup-old-build-scripts.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                log_success "$script exists and is executable"
            else
                log_warning "$script exists but is not executable - fixing..."
                chmod +x "$script"
                log_success "Made $script executable"
            fi
        else
            log_error "$script not found"
            return 1
        fi
    done
}

# Test 2: Check help output
test_help_output() {
    echo ""
    log_info "Testing script help output..."
    
    if ./scripts/build-pkg-with-macos-builder.sh --help | grep -q "PKG Builder using macOS-Pkg-Builder"; then
        log_success "PKG builder help output is correct"
    else
        log_error "PKG builder help output is incorrect"
        return 1
    fi
}

# Test 3: Check for required tools
test_prerequisites() {
    echo ""
    log_info "Checking prerequisites..."
    
    local tools=("python3" "pip3" "security" "codesign" "productbuild")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "$tool found"
        else
            missing_tools+=("$tool")
            log_error "$tool not found"
        fi
    done
    
    # Check if macos-pkg-builder can be installed/is installed
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macos-pkg-builder is installed"
    else
        log_info "macos-pkg-builder not installed (will be installed during setup)"
    fi
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "All required tools are available"
        return 0
    else
        log_error "Missing tools: ${missing_tools[*]}"
        return 1
    fi
}

# Test 4: Validate GitHub Actions workflow
test_workflow() {
    echo ""
    log_info "Checking GitHub Actions workflow..."
    
    local workflow=".github/workflows/build-macos-pkg-builder.yml"
    
    if [ -f "$workflow" ]; then
        if grep -q "macOS-Pkg-Builder" "$workflow"; then
            log_success "GitHub Actions workflow uses macOS-Pkg-Builder"
        else
            log_error "GitHub Actions workflow doesn't reference macOS-Pkg-Builder"
            return 1
        fi
    else
        log_error "GitHub Actions workflow not found: $workflow"
        return 1
    fi
}

# Test 5: Simulate cleanup (dry run)
test_cleanup() {
    echo ""
    log_info "Testing cleanup script (dry run)..."
    
    if ./scripts/cleanup-old-build-scripts.sh --dry-run | grep -q "Would remove:"; then
        log_success "Cleanup script works correctly (dry run)"
    else
        log_warning "Cleanup script didn't find files to remove (this may be normal)"
    fi
}

# Test 6: Check directory structure
test_directory_structure() {
    echo ""
    log_info "Checking project directory structure..."
    
    # Check for essential directories and files
    local essential_paths=(
        "pyproject.toml"
        "r2midi_client"
        "server"
        ".github/workflows"
    )
    
    for path in "${essential_paths[@]}"; do
        if [ -e "$path" ]; then
            log_success "$path exists"
        else
            log_error "$path not found"
            return 1
        fi
    done
}

# Main test execution
main() {
    local tests_passed=0
    local tests_failed=0
    
    echo "Running tests..."
    
    # Run all tests
    local test_functions=(
        "test_scripts"
        "test_help_output" 
        "test_prerequisites"
        "test_workflow"
        "test_cleanup"
        "test_directory_structure"
    )
    
    for test_func in "${test_functions[@]}"; do
        echo ""
        log_info "Running $test_func..."
        if $test_func; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
    done
    
    # Summary
    echo ""
    echo "===================="
    echo "TEST SUMMARY"
    echo "===================="
    log_info "Tests passed: $tests_passed"
    if [ $tests_failed -gt 0 ]; then
        log_error "Tests failed: $tests_failed"
    else
        log_success "Tests failed: $tests_failed"
    fi
    
    if [ $tests_failed -eq 0 ]; then
        echo ""
        log_success "🎉 All tests passed! The macOS-Pkg-Builder setup is ready to use."
        echo ""
        echo "Next steps:"
        echo "  1. Test a local build: ./scripts/build-local-with-pkg-builder.sh 1.0.0 dev"
        echo "  2. Review the cleanup script output: ./scripts/cleanup-old-build-scripts.sh --dry-run"
        echo "  3. When ready, run cleanup: ./scripts/cleanup-old-build-scripts.sh"
        echo "  4. Test the GitHub Actions workflow on a branch"
        return 0
    else
        echo ""
        log_error "❌ Some tests failed. Please fix the issues before proceeding."
        return 1
    fi
}

# Make scripts executable first
chmod +x scripts/*.sh 2>/dev/null || true

# Run main function
main "$@"
