#!/bin/bash
set -euo pipefail

# keychain-free-build.sh - Build script that avoids keychain prompts
# Usage: ./scripts/keychain-free-build.sh [--app-path PATH] [--pkg-name NAME] [--version VER] [--build-type TYPE]

# Colors
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

# Default values
APP_PATH=""
PKG_NAME=""
VERSION="1.0.0"
BUILD_TYPE="production"
OUTPUT_DIR="artifacts"

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
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help)
            cat << EOF
Keychain-Free PKG Builder

Usage: $0 --app-path <path> --pkg-name <name> [options]

Required:
  --app-path PATH      Path to the .app bundle to package
  --pkg-name NAME      Name for the output PKG file (without .pkg extension)

Options:
  --version VERSION    Version to embed in PKG (default: 1.0.0)
  --build-type TYPE    Build type: dev, staging, production (default: production)
  --output-dir DIR     Output directory for PKG (default: artifacts)
  --help               Show this help

Examples:
  $0 --app-path "build_server/dist/R2MIDI Server.app" --pkg-name "R2MIDI-Server-1.0.0"
  $0 --app-path "build_client/dist/R2MIDI Client.app" --pkg-name "R2MIDI-Client-1.0.0"
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
    log_error "PKG name is required. Use --pkg-name <name>"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    log_error "App bundle does not exist: $APP_PATH"
    exit 1
fi

log_step "Keychain-Free PKG Builder"
log_info "App Path: $APP_PATH"
log_info "PKG Name: $PKG_NAME"
log_info "Version: $VERSION"
log_info "Build Type: $BUILD_TYPE"
log_info "Output Directory: $OUTPUT_DIR"

# Function to create unsigned PKG (no keychain needed)
create_unsigned_pkg() {
    local app_path="$1"
    local pkg_name="$2"
    local version="$3"
    local output_dir="$4"
    
    log_step "Creating Unsigned PKG (No Keychain Required)"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    local output_pkg="$output_dir/${pkg_name}.pkg"
    local app_name=$(basename "$app_path")
    
    log_info "Building unsigned PKG..."
    log_info "  Source: $app_path"
    log_info "  Output: $output_pkg"
    
    # Use pkgbuild to create unsigned package
    if pkgbuild \
        --identifier "com.r2midi.${pkg_name,,}" \
        --version "$version" \
        --install-location "/Applications" \
        --component "$app_path" \
        "$output_pkg"; then
        
        log_success "Unsigned PKG created successfully"
        
        # Show package info
        local pkg_size=$(du -sh "$output_pkg" | cut -f1)
        log_success "PKG file: $output_pkg ($pkg_size)"
        
        return 0
    else
        log_error "Failed to create unsigned PKG"
        return 1
    fi
}

# Function to create signed PKG without keychain prompts
create_signed_pkg() {
    local app_path="$1"
    local pkg_name="$2"
    local version="$3"
    local output_dir="$4"
    
    log_step "Creating Signed PKG (Certificate File Method)"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    local output_pkg="$output_dir/${pkg_name}.pkg"
    local unsigned_pkg="$output_dir/${pkg_name}-unsigned.pkg"
    
    # First create unsigned package
    log_info "Creating unsigned package first..."
    if ! pkgbuild \
        --identifier "com.r2midi.${pkg_name,,}" \
        --version "$version" \
        --install-location "/Applications" \
        --component "$app_path" \
        "$unsigned_pkg"; then
        
        log_error "Failed to create unsigned PKG"
        return 1
    fi
    
    # Try to find signing identity without keychain
    log_info "Looking for signing identity..."
    
    # Try to sign using certificates from environment or files
    if [ -n "${APPLE_DEVELOPER_ID_INSTALLER_CERT:-}" ] && [ -n "${APPLE_CERT_PASSWORD:-}" ]; then
        log_info "Using certificate from environment variables"
        
        # Decode certificate to temporary file
        local temp_cert=$(mktemp -t installer_cert.XXXXXX.p12)
        echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > "$temp_cert"
        
        # Extract signing identity from certificate
        local identity=$(security find-certificate -a -p "$temp_cert" 2>/dev/null | \
                        openssl x509 -subject -noout 2>/dev/null | \
                        sed 's/.*CN=\([^,]*\).*/\1/' || echo "")
        
        if [ -n "$identity" ]; then
            log_info "Found identity: $identity"
            
            # Try to sign without keychain import
            if productsign --sign "$identity" "$unsigned_pkg" "$output_pkg" 2>/dev/null; then
                log_success "PKG signed successfully"
                rm -f "$unsigned_pkg" "$temp_cert"
                return 0
            else
                log_warning "Signing failed, keeping unsigned version"
                mv "$unsigned_pkg" "$output_pkg"
                rm -f "$temp_cert"
                return 0
            fi
        else
            log_warning "Could not extract identity from certificate"
            mv "$unsigned_pkg" "$output_pkg"
            rm -f "$temp_cert"
            return 0
        fi
    else
        log_info "No certificate environment variables found"
        
        # Check for local certificate files
        if [ -f "apple_credentials/certificates/installer_cert.p12" ]; then
            log_info "Found local installer certificate"
            
            # Try to find identity in system keychain (no password prompt)
            local identity=$(security find-identity -v | grep "Developer ID Installer" | head -1 | sed 's/.*) //' | sed 's/"//g' || echo "")
            
            if [ -n "$identity" ]; then
                log_info "Found identity in keychain: $identity"
                
                # Try to sign (may prompt for keychain password)
                if productsign --sign "$identity" "$unsigned_pkg" "$output_pkg" 2>/dev/null; then
                    log_success "PKG signed successfully"
                    rm -f "$unsigned_pkg"
                    return 0
                else
                    log_warning "Signing failed or was cancelled, keeping unsigned version"
                    mv "$unsigned_pkg" "$output_pkg"
                    return 0
                fi
            else
                log_warning "No installer identity found in keychain"
                mv "$unsigned_pkg" "$output_pkg"
                return 0
            fi
        else
            log_warning "No certificate files found, creating unsigned PKG"
            mv "$unsigned_pkg" "$output_pkg"
            return 0
        fi
    fi
}

# Function to handle notarization (optional)
handle_notarization() {
    local pkg_path="$1"
    local build_type="$2"
    
    if [ "$build_type" = "dev" ]; then
        log_info "Skipping notarization for development build"
        return 0
    fi
    
    log_step "Notarization (Optional)"
    
    # Check if we have notarization credentials
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        log_warning "Notarization credentials not available, skipping"
        return 0
    fi
    
    log_info "Submitting PKG for notarization..."
    
    # Submit for notarization
    local submit_output
    if submit_output=$(xcrun notarytool submit "$pkg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait 2>&1); then
        
        if echo "$submit_output" | grep -q "status: Accepted"; then
            log_success "PKG notarization completed successfully"
            
            # Staple the notarization
            if xcrun stapler staple "$pkg_path" 2>/dev/null; then
                log_success "Notarization stapled successfully"
            else
                log_warning "Failed to staple (PKG is still notarized)"
            fi
            
            return 0
        else
            log_warning "PKG notarization failed or was rejected"
            log_info "Output: $submit_output"
            return 0  # Don't fail the build
        fi
    else
        log_warning "Notarization submission failed"
        log_info "Error: $submit_output"
        return 0  # Don't fail the build
    fi
}

# Main execution
main() {
    # Create PKG based on build type
    if [ "$BUILD_TYPE" = "dev" ]; then
        log_info "Development build - creating unsigned PKG"
        if create_unsigned_pkg "$APP_PATH" "$PKG_NAME" "$VERSION" "$OUTPUT_DIR"; then
            log_success "Development PKG created successfully"
        else
            log_error "Failed to create development PKG"
            exit 1
        fi
    else
        log_info "Production build - attempting signed PKG"
        if create_signed_pkg "$APP_PATH" "$PKG_NAME" "$VERSION" "$OUTPUT_DIR"; then
            log_success "PKG created successfully"
            
            # Handle notarization
            local pkg_file="$OUTPUT_DIR/${PKG_NAME}.pkg"
            handle_notarization "$pkg_file" "$BUILD_TYPE"
        else
            log_error "Failed to create PKG"
            exit 1
        fi
    fi
    
    # Show final results
    local pkg_file="$OUTPUT_DIR/${PKG_NAME}.pkg"
    if [ -f "$pkg_file" ]; then
        local pkg_size=$(du -sh "$pkg_file" | cut -f1)
        log_success "Final PKG: $pkg_file ($pkg_size)"
        
        # Check if signed
        if pkgutil --check-signature "$pkg_file" >/dev/null 2>&1; then
            log_success "PKG is signed"
        else
            log_info "PKG is unsigned (suitable for development)"
        fi
        
        log_success "PKG build completed!"
    else
        log_error "PKG file not found after build"
        exit 1
    fi
}

# Run main function
main
