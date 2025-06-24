#!/bin/bash
set -euo pipefail

# build-pkg-with-macos-builder.sh - Build PKG using macOS-Pkg-Builder
# Usage: ./scripts/build-pkg-with-macos-builder.sh --app-path <path> --pkg-name <n> [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
APP_PATH=""
PKG_NAME=""
VERSION="1.0.0"
BUILD_TYPE="production"
SKIP_NOTARIZATION=false
OUTPUT_DIR="$PROJECT_ROOT/artifacts"
# macOS-Pkg-Builder will be installed via pip

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo ""; echo -e "${BLUE}🔄 $1${NC}"; echo "$(printf '=%.0s' {1..50})"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --app-path)
            APP_PATH="$2"
            shift 2
            ;;
        --pkg-name)
            PKG_NAME="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help)
            cat << EOF
PKG Builder using macOS-Pkg-Builder

Usage: $0 --app-path <path> --pkg-name <n> [options]

Required:
  --app-path PATH      Path to the .app bundle to package
  --pkg-name NAME      Name for the output PKG file (without .pkg extension)

Options:
  --version VERSION    Version to embed in PKG (default: 1.0.0)
  --build-type TYPE    Build type: dev, staging, production (default: production)
  --skip-notarize      Skip notarization step
  --output-dir DIR     Output directory for PKG (default: artifacts)
  --help               Show this help

Examples:
  $0 --app-path "build/server/macos/app/R2MIDI Server.app" --pkg-name "R2MIDI-Server-1.0.0"
  $0 --app-path "build/client/macos/app/R2MIDI Client.app" --pkg-name "R2MIDI-Client-1.0.0" --skip-notarize
EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$APP_PATH" ]; then
    log_error "App path is required. Use --app-path <path>"
    exit 1
fi

if [ -z "$PKG_NAME" ]; then
    log_error "PKG name is required. Use --pkg-name <n>"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    log_error "App bundle does not exist: $APP_PATH"
    exit 1
fi

log_step "PKG Builder using macOS-Pkg-Builder"
log_info "App Path: $APP_PATH"
log_info "PKG Name: $PKG_NAME"
log_info "Version: $VERSION"
log_info "Build Type: $BUILD_TYPE"
log_info "Output Directory: $OUTPUT_DIR"

# Setup macOS-Pkg-Builder
setup_macos_pkg_builder() {
    log_step "Setting up macOS-Pkg-Builder"

    # Check if macos-pkg-builder is installed
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macOS-Pkg-Builder is already installed"
        local version=$(macos-pkg-builder --version 2>/dev/null || echo "unknown")
        log_info "Version: $version"
    else
        log_info "Installing macOS-Pkg-Builder via pip..."
        
        # Try different installation methods
        local install_success=false
        
        # Method 1: Global install
        if pip3 install macos-pkg-builder >/dev/null 2>&1; then
            log_success "macOS-Pkg-Builder installed successfully (global)"
            install_success=true
        # Method 2: User install
        elif pip3 install --user macos-pkg-builder >/dev/null 2>&1; then
            log_success "macOS-Pkg-Builder installed successfully (user install)"
            # Add user bin to PATH if needed
            export PATH="$HOME/.local/bin:$PATH"
            install_success=true
        # Method 3: With upgrade pip first
        elif python3 -m pip install --upgrade pip >/dev/null 2>&1 && pip3 install macos-pkg-builder >/dev/null 2>&1; then
            log_success "macOS-Pkg-Builder installed successfully (after pip upgrade)"
            install_success=true
        fi
        
        if [ "$install_success" = false ]; then
            log_error "All installation methods failed"
            log_error "Please check:"
            log_error "  1. Network connectivity to PyPI"
            log_error "  2. Python/pip installation"
            log_error "  3. Disk space availability"
            return 1
        fi
    fi

    # Verify installation
    if command -v macos-pkg-builder >/dev/null 2>&1; then
        log_success "macOS-Pkg-Builder is ready to use"
    else
        log_error "macOS-Pkg-Builder installation verification failed"
        return 1
    fi
}

# Load signing credentials
load_signing_credentials() {
    log_step "Loading Signing Credentials"

    # Check if we're in GitHub Actions
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        log_info "Running in GitHub Actions - using environment variables"
        
        # Check required environment variables
        local required_vars=("APPLE_DEVELOPER_ID_INSTALLER_CERT" "APPLE_CERT_PASSWORD" "APPLE_ID" "APPLE_ID_PASSWORD" "APPLE_TEAM_ID")
        local missing_vars=()

        for var in "${required_vars[@]}"; do
            if [ -z "${!var:-}" ]; then
                missing_vars+=("$var")
            fi
        done

        if [ ${#missing_vars[@]} -gt 0 ]; then
            log_error "Missing required environment variables:"
            for var in "${missing_vars[@]}"; do
                log_error "  - $var"
            done
            exit 1
        fi

        log_success "All required environment variables are set"
    else
        log_info "Running locally - checking for app_config.json"
        
        local config_file="$PROJECT_ROOT/apple_credentials/config/app_config.json"
        if [ ! -f "$config_file" ]; then
            log_error "Configuration file not found: $config_file"
            log_error "Please create the configuration file or run in GitHub Actions"
            exit 1
        fi

        # Load configuration
        if command -v python3 >/dev/null 2>&1; then
            export APPLE_ID=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['apple_id'])" 2>/dev/null || echo "")
            export APPLE_ID_PASSWORD=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['app_specific_password'])" 2>/dev/null || echo "")
            export APPLE_TEAM_ID=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['team_id'])" 2>/dev/null || echo "")
            
            log_success "Configuration loaded from app_config.json"
        else
            log_error "Python3 not found - cannot load configuration"
            exit 1
        fi
    fi
}

# Build PKG using macOS-Pkg-Builder
build_pkg() {
    log_step "Building PKG with macOS-Pkg-Builder"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    local output_pkg="$OUTPUT_DIR/${PKG_NAME}.pkg"
    local app_name=$(basename "$APP_PATH")

    log_info "Building PKG..."
    log_info "  Source: $APP_PATH"
    log_info "  Output: $output_pkg"

    # Prepare arguments for macOS-Pkg-Builder
    local builder_args=(
        --app-path "$APP_PATH"
        --pkg-output "$output_pkg"
        --app-name "$app_name"
        --app-version "$VERSION"
        --install-location "/Applications"
    )

    # Add signing arguments if not skipped
    if [ "$BUILD_TYPE" != "dev" ] && [ -n "${APPLE_ID:-}" ]; then
        builder_args+=(
            --sign
            --apple-id "$APPLE_ID"
            --team-id "$APPLE_TEAM_ID"
        )

        # Add notarization if not skipped
        if [ "$SKIP_NOTARIZATION" != "true" ]; then
            builder_args+=(
                --notarize
                --apple-password "$APPLE_ID_PASSWORD"
            )
        fi
    else
        log_warning "Skipping signing and notarization (dev build or missing credentials)"
    fi

    # Execute macOS-Pkg-Builder
    log_info "Executing: macos-pkg-builder ${builder_args[*]}"
    
    if macos-pkg-builder "${builder_args[@]}"; then
        log_success "PKG built successfully: $output_pkg"
        
        # Verify the package
        if [ -f "$output_pkg" ]; then
            local pkg_size=$(du -sh "$output_pkg" | cut -f1)
            log_success "PKG file created: $output_pkg ($pkg_size)"
            
            # Check signature
            if pkgutil --check-signature "$output_pkg" >/dev/null 2>&1; then
                log_success "PKG is signed"
            else
                log_info "PKG is not signed (expected for dev builds)"
            fi
            
            return 0
        else
            log_error "PKG file was not created"
            return 1
        fi
    else
        log_error "PKG build failed"
        return 1
    fi
}

# Main execution
main() {
    setup_macos_pkg_builder
    load_signing_credentials
    build_pkg
    
    log_success "PKG build process completed!"
}

# Run main function
main
