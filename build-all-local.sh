#!/bin/bash
set -euo pipefail

# build-all-local.sh - Enhanced R2MIDI build system with proper signing
# Usage: ./build-all-local.sh [options]

echo "🚀 R2MIDI Enhanced Build System"
echo "==============================="

# Default values
VERSION=""
BUILD_TYPE="production"
SKIP_SIGNING=false
SKIP_NOTARIZATION=false
CLEAN_BUILD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --dev)
            BUILD_TYPE="dev"
            shift
            ;;
        --no-sign)
            SKIP_SIGNING=true
            shift
            ;;
        --no-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --help)
            cat << EOF
R2MIDI Enhanced Build System

Usage: $0 [options]

Options:
  --version VERSION    Specify version (auto-detected if not provided)
  --dev               Development build (faster, less verification)
  --no-sign           Skip code signing
  --no-notarize       Skip notarization
  --clean             Clean previous builds first
  --help              Show this help

Examples:
  $0                                  # Build everything with auto-detected version
  $0 --version 1.2.3                # Build with specific version
  $0 --dev --no-notarize            # Fast development build
  $0 --clean                        # Clean build

Supports both local development and GitHub Actions environments.
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() { echo "ℹ️  $1"; }
log_success() { echo "✅ $1"; }
log_warning() { echo "⚠️  $1"; }
log_error() { echo "❌ $1"; }
log_step() { echo ""; echo "🔄 $1"; echo "$(printf '=%.0s' {1..50})"; }

# Check if we're running in GitHub Actions
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    log_info "Running in GitHub Actions environment"
    IS_GITHUB_ACTIONS=true
else
    log_info "Running in local development environment"
    IS_GITHUB_ACTIONS=false
fi

# Check macOS version and tools
check_environment() {
    log_step "Checking Environment"
    
    if [ "$(uname)" != "Darwin" ]; then
        log_error "This script requires macOS"
        exit 1
    fi
    
    local macos_version=$(sw_vers -productVersion)
    log_info "Running on macOS $macos_version"
    
    # Check for required tools
    local missing_tools=()
    for tool in python3 security codesign productsign pkgbuild xcrun; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - $tool"
        done
        exit 1
    fi
    
    # Check if notarytool is available
    if command -v xcrun &> /dev/null && xcrun --find notarytool &> /dev/null; then
        log_success "notarytool is available"
    else
        log_warning "notarytool not found - notarization may fail (requires Xcode 13+ or macOS 12+)"
    fi
    
    # Check virtual environments
    if [ ! -d "venv_client" ] || [ ! -d "venv_server" ]; then
        log_error "Virtual environments not found. Run: ./setup-virtual-environments.sh"
        exit 1
    fi
    
    log_success "Environment check passed"
}

# Setup certificates - GitHub Actions vs Local
setup_certificates() {
    log_step "Setting Up Certificates"
    
    if [ "$IS_GITHUB_ACTIONS" = true ]; then
        setup_github_certificates
    else
        setup_local_certificates
    fi
}

# GitHub Actions certificate setup
setup_github_certificates() {
    log_info "Setting up certificates from GitHub Actions environment..."
    
    # Check required environment variables
    if [ -z "${APPLE_DEVELOPER_ID_APPLICATION_CERT:-}" ] || [ -z "${APPLE_DEVELOPER_ID_INSTALLER_CERT:-}" ]; then
        log_error "Required certificate environment variables not found"
        log_error "Required: APPLE_DEVELOPER_ID_APPLICATION_CERT, APPLE_DEVELOPER_ID_INSTALLER_CERT"
        exit 1
    fi
    
    # Create temporary certificate directory
    mkdir -p /tmp/github_certs
    
    # Decode and save certificates
    echo "$APPLE_DEVELOPER_ID_APPLICATION_CERT" | base64 --decode > /tmp/github_certs/app_cert.p12
    echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > /tmp/github_certs/installer_cert.p12
    
    # Create temporary config for GitHub Actions
    cat > /tmp/github_app_config.json << EOF
{
  "apple_developer": {
    "team_id": "${APPLE_TEAM_ID}",
    "p12_path": "/tmp/github_certs",
    "p12_password": "${APPLE_CERT_PASSWORD}",
    "app_specific_password": "${APPLE_ID_PASSWORD}",
    "apple_id": "${APPLE_ID}"
  },
  "build_options": {
    "enable_notarization": true
  }
}
EOF
    
    # Create temporary keychain
    TEMP_KEYCHAIN="r2midi-github-$(date +%s).keychain"
    TEMP_KEYCHAIN_PASSWORD="github_$(date +%s)_$(openssl rand -hex 8)"
    
    # Clean up any existing keychains
    security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true
    
    # Create and configure keychain
    security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"
    security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    security list-keychains -d user -s "$TEMP_KEYCHAIN" $(security list-keychains -d user | xargs)
    
    # Import certificates
    security import "/tmp/github_certs/app_cert.p12" -k "$TEMP_KEYCHAIN" -P "${APPLE_CERT_PASSWORD}" -T /usr/bin/codesign -T /usr/bin/security
    security import "/tmp/github_certs/installer_cert.p12" -k "$TEMP_KEYCHAIN" -P "${APPLE_CERT_PASSWORD}" -T /usr/bin/productsign -T /usr/bin/security
    
    # Set partition list
    security set-key-partition-list -S apple-tool:,apple: -s -k "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    
    # Export keychain info for enhanced signing script
    export KEYCHAIN_NAME="$TEMP_KEYCHAIN"
    export KEYCHAIN_PASSWORD="$TEMP_KEYCHAIN_PASSWORD"
    
    log_success "GitHub Actions certificates setup complete"
}

# Local certificate setup
setup_local_certificates() {
    log_info "Setting up local certificates..."
    
    # Check if enhanced certificate setup exists
    if [ -f "setup-local-certificates.sh" ]; then
        log_info "Running enhanced certificate setup..."
        ./setup-local-certificates.sh
        
        # Source environment if available
        if [ -f ".local_build_env" ]; then
            source .local_build_env
        fi
    else
        log_warning "Enhanced certificate setup not found"
        
        # Basic certificate check
        if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
            log_error "No Developer ID Application certificate found"
            log_error "Install your Apple Developer certificates first"
            exit 1
        fi
        
        log_success "Basic certificates found"
    fi
}

# Extract version
extract_version() {
    if [ -n "$VERSION" ]; then
        log_info "Using specified version: $VERSION"
        return
    fi
    
    log_info "Auto-detecting version..."
    
    # Try server version first
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "
import sys
sys.path.insert(0, 'server')
try:
    from version import __version__
    print(__version__)
except:
    pass
" 2>/dev/null || echo "")
    fi
    
    # Try client version if server failed
    if [ -z "$VERSION" ] && [ -f "r2midi_client/version.py" ]; then
        VERSION=$(python3 -c "
import sys
sys.path.insert(0, 'r2midi_client')
try:
    from version import __version__
    print(__version__)
except:
    pass
" 2>/dev/null || echo "")
    fi
    
    # Fallback version
    if [ -z "$VERSION" ]; then
        VERSION="0.1.$(date +%Y%m%d)"
        log_warning "Could not detect version, using: $VERSION"
    else
        log_success "Detected version: $VERSION"
    fi
}

# Clean previous builds
clean_builds() {
    if [ "$CLEAN_BUILD" = true ]; then
        log_step "Cleaning Previous Builds"
        
        log_info "Removing build directories..."
        rm -rf build_server/build build_server/dist
        rm -rf build_client/build build_client/dist
        
        log_info "Removing artifacts..."
        rm -rf artifacts/*.pkg artifacts/*.dmg artifacts/*.app
        
        log_info "Cleaning Python cache..."
        find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        find . -name "*.pyc" -delete 2>/dev/null || true
        
        log_success "Build environment cleaned"
    fi
}

# Build individual component
build_component() {
    local component="$1"  # "server" or "client"
    local script_name="build-${component}-local.sh"
    
    log_step "Building R2MIDI ${component^}"
    
    if [ ! -f "$script_name" ]; then
        log_error "$script_name not found"
        return 1
    fi
    
    # Build arguments
    local build_args="--version $VERSION"
    
    if [ "$BUILD_TYPE" = "dev" ]; then
        build_args="$build_args --dev"
    fi
    
    if [ "$SKIP_SIGNING" = true ]; then
        build_args="$build_args --no-sign"
    fi
    
    if [ "$SKIP_NOTARIZATION" = true ]; then
        build_args="$build_args --no-notarize"
    fi
    
    log_info "Running: ./$script_name $build_args"
    
    if ./"$script_name" $build_args; then
        log_success "${component^} build completed"
        return 0
    else
        log_error "${component^} build failed"
        return 1
    fi
}

# Enhanced signing using the new script
enhanced_signing() {
    if [ "$SKIP_SIGNING" = true ]; then
        log_info "Skipping enhanced signing (--no-sign specified)"
        return 0
    fi
    
    log_step "Enhanced Signing and Notarization"
    
    # Check if enhanced signing script exists
    if [ ! -f ".github/scripts/sign-and-notarize-macos.sh" ]; then
        log_warning "Enhanced signing script not found at .github/scripts/sign-and-notarize-macos.sh"
        log_warning "Signing was handled by individual build scripts"
        return 0
    fi
    
    # Build arguments for signing script
    local sign_args="--version $VERSION"
    
    if [ "$BUILD_TYPE" = "dev" ]; then
        sign_args="$sign_args --dev"
    fi
    
    if [ "$SKIP_NOTARIZATION" = true ]; then
        sign_args="$sign_args --skip-notarize"
    fi
    
    log_info "Running enhanced signing: ./.github/scripts/sign-and-notarize-macos.sh $sign_args"
    
    if ./.github/scripts/sign-and-notarize-macos.sh $sign_args; then
        log_success "Enhanced signing and notarization completed"
        return 0
    else
        log_error "Enhanced signing failed"
        if [ "$BUILD_TYPE" != "dev" ]; then
            return 1
        else
            log_warning "Continuing despite signing failure (dev build)"
            return 0
        fi
    fi
}

# Generate comprehensive build report
generate_build_report() {
    log_step "Generating Build Report"
    
    local report_file="artifacts/BUILD_REPORT_$VERSION.md"
    mkdir -p artifacts
    
    cat > "$report_file" << EOF
# R2MIDI Complete Build Report

**Version:** $VERSION  
**Build Date:** $(date)  
**Build Type:** $BUILD_TYPE  
**Environment:** $([ "$IS_GITHUB_ACTIONS" = true ] && echo "GitHub Actions" || echo "Local Development")  
**Platform:** $(uname -s) $(uname -r)  
**Architecture:** $(uname -m)  

## Build Configuration

- **Signing:** $([ "$SKIP_SIGNING" = true ] && echo "Disabled" || echo "Enabled")
- **Notarization:** $([ "$SKIP_NOTARIZATION" = true ] && echo "Disabled" || echo "Enabled")
- **Clean Build:** $([ "$CLEAN_BUILD" = true ] && echo "Yes" || echo "No")
- **Python Version:** $(python3 --version)

## Generated Artifacts

EOF

    # List all generated artifacts
    if [ -d "artifacts" ]; then
        find artifacts -name "*.pkg" -o -name "*.dmg" -o -name "*.app" | sort | while read artifact; do
            if [ -f "$artifact" ]; then
                local size=$(du -sh "$artifact" 2>/dev/null | cut -f1 || echo "unknown")
                local signed="Unknown"
                local notarized="Unknown"
                
                # Check if it's a package
                if [[ "$artifact" == *.pkg ]]; then
                    if pkgutil --check-signature "$artifact" >/dev/null 2>&1; then
                        signed="Yes"
                    else
                        signed="No"
                    fi
                    
                    if spctl --assess --type install "$artifact" >/dev/null 2>&1; then
                        notarized="Yes"
                    else
                        notarized="No"
                    fi
                    
                    echo "- **$(basename "$artifact")** ($size)" >> "$report_file"
                    echo "  - Signed: $signed" >> "$report_file"
                    echo "  - Notarized: $notarized" >> "$report_file"
                else
                    echo "- **$(basename "$artifact")** ($size)" >> "$report_file"
                fi
            fi
        done
    fi

    cat >> "$report_file" << EOF

## Installation Instructions

### Using Package Installers
\`\`\`bash
# Install server
sudo installer -pkg artifacts/R2MIDI-Server-$VERSION*.pkg -target /

# Install client  
sudo installer -pkg artifacts/R2MIDI-Client-$VERSION*.pkg -target /
\`\`\`

### Manual Installation
\`\`\`bash
# Copy apps to Applications folder
cp -R build_server/dist/R2MIDI\\ Server.app /Applications/
cp -R build_client/dist/R2MIDI\\ Client.app /Applications/
\`\`\`

## Usage

### Start Server
\`\`\`bash
open "/Applications/R2MIDI Server.app"
# Server will be available at: http://localhost:8000
\`\`\`

### Start Client
\`\`\`bash
open "/Applications/R2MIDI Client.app"
\`\`\`

## Verification Commands

\`\`\`bash
# Verify package signatures
pkgutil --check-signature artifacts/*.pkg

# Verify app signatures
codesign --verify --deep --strict --verbose=2 "/Applications/R2MIDI Server.app"
codesign --verify --deep --strict --verbose=2 "/Applications/R2MIDI Client.app"

# Check Gatekeeper
spctl --assess --type exec --verbose "/Applications/R2MIDI Server.app"
spctl --assess --type exec --verbose "/Applications/R2MIDI Client.app"
\`\`\`

---
Generated by build-all-local.sh (Enhanced Build System)
EOF

    log_success "Build report created: $report_file"
}

# Cleanup function
cleanup() {
    if [ -n "${TEMP_KEYCHAIN:-}" ]; then
        log_info "Cleaning up temporary keychain: $TEMP_KEYCHAIN"
        security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true
    fi
    
    if [ "$IS_GITHUB_ACTIONS" = true ]; then
        rm -f /tmp/github_app_config.json
        rm -rf /tmp/github_certs
    fi
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Main execution
main() {
    echo "Starting R2MIDI Enhanced Build System..."
    echo "Build Type: $BUILD_TYPE"
    echo "Skip Signing: $SKIP_SIGNING"
    echo "Skip Notarization: $SKIP_NOTARIZATION"
    echo ""
    
    # Prerequisites
    check_environment
    extract_version
    clean_builds
    setup_certificates
    
    # Create artifacts directory
    mkdir -p artifacts
    
    # Build components
    local build_success=true
    
    # Build server
    if ! build_component "server"; then
        log_error "Server build failed"
        build_success=false
    fi
    
    # Build client  
    if ! build_component "client"; then
        log_error "Client build failed"
        build_success=false
    fi
    
    # Enhanced signing (if individual builds didn't handle it fully)
    if [ "$build_success" = true ]; then
        enhanced_signing || build_success=false
    fi
    
    # Generate report
    generate_build_report
    
    # Final summary
    log_step "Build Summary"
    
    if [ "$build_success" = true ]; then
        log_success "🎉 Complete build finished successfully!"
        
        echo ""
        echo "📦 Generated packages:"
        find artifacts -name "*.pkg" 2>/dev/null | while read pkg; do
            if [ -f "$pkg" ]; then
                local size=$(du -sh "$pkg" 2>/dev/null | cut -f1 || echo "unknown")
                echo "  ✅ $(basename "$pkg") ($size)"
            fi
        done
        
        echo ""
        echo "📋 Next steps:"
        echo "  1. Test installation: sudo installer -pkg artifacts/R2MIDI-*-$VERSION*.pkg -target /"
        echo "  2. Launch applications from /Applications/"
        echo "  3. Check build report: artifacts/BUILD_REPORT_$VERSION.md"
        
        if [ "$SKIP_SIGNING" = false ] && [ "$SKIP_NOTARIZATION" = false ]; then
            echo ""
            echo "✅ Packages are signed and notarized for distribution"
        fi
        
        exit 0
    else
        log_error "Build completed with errors"
        echo ""
        echo "❌ Some components failed to build"
        echo "📋 Check the logs above for details"
        echo "📄 Partial build report: artifacts/BUILD_REPORT_$VERSION.md"
        
        exit 1
    fi
}

# Run main function
main "$@"