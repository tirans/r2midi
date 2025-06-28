#!/bin/bash
set -euo pipefail

# sign-notarize.sh - Simplified signing and notarization using macos-pkg-builder
# This script uses the macos-pkg-builder Python module for proper signing

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Enhanced logging functions
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1"; }
log_warning() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1"; }
log_step() { echo ""; echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔄 $1"; echo "$(printf '=%.0s' {1..60})"; }

# Default values
VERSION=""
BUILD_TYPE="production"
SKIP_NOTARIZATION=false
TARGET_PATH=""

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
        --skip-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --target)
            TARGET_PATH="$2"
            shift 2
            ;;
        --help)
            cat << 'EOF'
Simplified Signing and Notarization using macOS-Pkg-Builder

Usage: $0 [options]

Options:
  --version VERSION     Specify version (required)
  --dev                Development build (skip signing and notarization)
  --skip-notarize      Skip notarization process
  --target PATH        Specific target to sign (optional)
  --help               Show this help

Examples:
  $0 --version 1.0.0
  $0 --version 1.0.0 --dev
  $0 --version 1.0.0 --skip-notarize
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
if [ -z "$VERSION" ]; then
    log_error "Version is required. Use --version VERSION"
    exit 1
fi

# Setup logging
mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/signing_${VERSION}_$(date '+%Y%m%d_%H%M%S').log"

log_step "Simplified Signing and Notarization using macOS-Pkg-Builder"
log_info "Version: $VERSION"
log_info "Build Type: $BUILD_TYPE"
log_info "Skip Notarization: $SKIP_NOTARIZATION"
log_info "Log file: $LOG_FILE"

# Log to both console and file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Function to install macos-pkg-builder if needed
setup_macos_pkg_builder() {
    log_step "Setting up macOS-Pkg-Builder"
    
    # Check if already installed
    if python3 -c "import macos_pkg_builder" 2>/dev/null; then
        log_success "macOS-Pkg-Builder is already available"
        return 0
    fi
    
    log_info "Installing macOS-Pkg-Builder..."
    
    # Try different installation methods
    local install_commands=(
        "python3 -m pip install macos-pkg-builder"
        "python3 -m pip install --user macos-pkg-builder"
        "pip3 install macos-pkg-builder"
        "pip3 install --user macos-pkg-builder"
    )
    
    for cmd in "${install_commands[@]}"; do
        log_info "Trying: $cmd"
        if eval "$cmd" >/dev/null 2>&1; then
            log_success "macOS-Pkg-Builder installed successfully"
            
            # Verify installation
            if python3 -c "import macos_pkg_builder" 2>/dev/null; then
                log_success "macOS-Pkg-Builder is ready to use"
                return 0
            fi
        fi
    done
    
    log_error "Failed to install macOS-Pkg-Builder"
    return 1
}

# Function to get signing identity from environment
get_signing_identity() {
    log_step "Getting Signing Identity"
    
    # Check if we're in GitHub Actions
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        log_info "GitHub Actions environment detected"
        
        # Check for required environment variables
        local required_vars=("APPLE_DEVELOPER_ID_APPLICATION_CERT" "APPLE_DEVELOPER_ID_INSTALLER_CERT" "APPLE_CERT_PASSWORD")
        for var in "${required_vars[@]}"; do
            if [ -z "${!var:-}" ]; then
                log_error "Missing required environment variable: $var"
                return 1
            fi
        done
        
        # Setup temporary keychain and import certificates
        log_info "Setting up temporary keychain for GitHub Actions..."
        
        local keychain_name="r2midi-signing-$(date +%s).keychain"
        local keychain_password="temp-$(date +%s)-$(openssl rand -hex 8)"
        
        # Create certificate directory
        local cert_dir="/tmp/github_certs"
        mkdir -p "$cert_dir"
        
        # Decode certificates
        echo "$APPLE_DEVELOPER_ID_APPLICATION_CERT" | base64 --decode > "$cert_dir/app.p12"
        echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > "$cert_dir/installer.p12"
        
        # Create and configure keychain
        security create-keychain -p "$keychain_password" "$keychain_name"
        security set-keychain-settings -lut 21600 "$keychain_name"
        security unlock-keychain -p "$keychain_password" "$keychain_name"
        security list-keychains -d user -s "$keychain_name" $(security list-keychains -d user | xargs)
        
        # Import certificates
        security import "$cert_dir/app.p12" -k "$keychain_name" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
        security import "$cert_dir/installer.p12" -k "$keychain_name" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/productsign -T /usr/bin/security
        
        # Set partition list
        security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_name"
        
        # Export keychain info for cleanup
        export TEMP_KEYCHAIN_NAME="$keychain_name"
        export TEMP_KEYCHAIN_PASSWORD="$keychain_password"
        
        log_success "Temporary keychain setup completed"
    else
        log_info "Local environment detected"
    fi
    
    # Find signing identities
    local app_identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
    local installer_identity=$(security find-identity -v -p codesigning | grep "Developer ID Installer" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
    
    if [ -n "$app_identity" ]; then
        log_success "Found Developer ID Application certificate: $app_identity"
        export SIGNING_IDENTITY="$app_identity"
    else
        log_warning "No Developer ID Application certificate found"
        export SIGNING_IDENTITY=""
    fi
    
    if [ -n "$installer_identity" ]; then
        log_success "Found Developer ID Installer certificate: $installer_identity"
        export INSTALLER_IDENTITY="$installer_identity"
    else
        log_warning "No Developer ID Installer certificate found"
        export INSTALLER_IDENTITY=""
    fi
    
    return 0
}

# Function to process targets using macos-pkg-builder
process_targets() {
    log_step "Processing Targets with macOS-Pkg-Builder"
    
    # Find targets to process
    local targets=()
    
    if [ -n "$TARGET_PATH" ]; then
        if [ -e "$TARGET_PATH" ]; then
            targets+=("$TARGET_PATH")
        else
            log_error "Specified target not found: $TARGET_PATH"
            return 1
        fi
    else
        # Find .app bundles
        while IFS= read -r -d '' app_path; do
            if [ -d "$app_path" ]; then
                targets+=("$app_path")
            fi
        done < <(find "$PROJECT_ROOT" -name "*.app" -type d -print0 2>/dev/null)
        
        # Find .pkg files (for re-signing)
        while IFS= read -r -d '' pkg_path; do
            if [ -f "$pkg_path" ]; then
                targets+=("$pkg_path")
            fi
        done < <(find "$PROJECT_ROOT/artifacts" -name "*.pkg" -type f -print0 2>/dev/null)
    fi
    
    if [ ${#targets[@]} -eq 0 ]; then
        log_warning "No targets found to process"
        return 0
    fi
    
    log_info "Found ${#targets[@]} targets to process"
    
    # Process each target
    local overall_success=true
    local processed_count=0
    
    for target in "${targets[@]}"; do
        processed_count=$((processed_count + 1))
        log_info "[$processed_count/${#targets[@]}] Processing: $(basename "$target")"
        
        if [[ "$target" == *.app ]]; then
            # Process .app bundle - create new package
            if process_app_bundle "$target"; then
                log_success "Successfully processed app bundle: $(basename "$target")"
            else
                log_error "Failed to process app bundle: $(basename "$target")"
                overall_success=false
            fi
        elif [[ "$target" == *.pkg ]]; then
            # Process existing .pkg - re-sign if needed
            if process_existing_pkg "$target"; then
                log_success "Successfully processed package: $(basename "$target")"
            else
                log_error "Failed to process package: $(basename "$target")"
                overall_success=false
            fi
        else
            log_warning "Unknown target type: $(basename "$target")"
        fi
    done
    
    return $overall_success
}

# Function to process .app bundle using Python script
process_app_bundle() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)
    local pkg_name
    
    # Determine package name based on app
    if [[ "$app_name" =~ [Ss]erver ]]; then
        pkg_name="R2MIDI-Server-$VERSION"
    elif [[ "$app_name" =~ [Cc]lient ]]; then
        pkg_name="R2MIDI-Client-$VERSION"
    else
        pkg_name="R2MIDI-${app_name// /-}-$VERSION"
    fi
    
    log_info "Creating package: $pkg_name from app: $app_name"
    
    # Prepare arguments for Python script
    local python_args=(
        "--app-path" "$app_path"
        "--pkg-name" "$pkg_name"
        "--version" "$VERSION"
        "--build-type" "$BUILD_TYPE"
    )
    
    if [ "$SKIP_NOTARIZATION" = true ]; then
        python_args+=("--skip-notarize")
    fi
    
    # Set output directory
    python_args+=("--output-dir" "$PROJECT_ROOT/artifacts")
    
    # Run the Python script that uses macos-pkg-builder
    log_info "Running: python3 scripts/build-pkg-with-macos-builder.py ${python_args[*]}"
    
    if cd "$PROJECT_ROOT" && python3 scripts/build-pkg-with-macos-builder.py "${python_args[@]}"; then
        log_success "Package creation completed"
        return 0
    else
        log_error "Package creation failed"
        return 1
    fi
}

# Function to process existing .pkg file
process_existing_pkg() {
    local pkg_path="$1"
    
    log_info "Processing existing package: $(basename "$pkg_path")"
    
    # Check if package is already signed
    if pkgutil --check-signature "$pkg_path" >/dev/null 2>&1; then
        log_info "Package is already signed"
        
        # Handle notarization if needed
        if [ "$SKIP_NOTARIZATION" = false ] && [ "$BUILD_TYPE" != "dev" ]; then
            if handle_notarization "$pkg_path"; then
                log_success "Notarization completed"
            else
                log_warning "Notarization failed or skipped"
            fi
        fi
        
        return 0
    else
        log_info "Package is not signed"
        
        # If we have installer identity, try to sign it
        if [ -n "${INSTALLER_IDENTITY:-}" ] && [ "$BUILD_TYPE" != "dev" ]; then
            log_info "Attempting to sign package..."
            
            local signed_pkg="${pkg_path%.pkg}-signed.pkg"
            if productsign --sign "$INSTALLER_IDENTITY" "$pkg_path" "$signed_pkg"; then
                mv "$signed_pkg" "$pkg_path"
                log_success "Package signed successfully"
                
                # Handle notarization
                if [ "$SKIP_NOTARIZATION" = false ]; then
                    if handle_notarization "$pkg_path"; then
                        log_success "Notarization completed"
                    else
                        log_warning "Notarization failed or skipped"
                    fi
                fi
            else
                log_warning "Package signing failed"
            fi
        else
            log_info "Skipping signing (no installer identity or dev build)"
        fi
        
        return 0
    fi
}

# Function to handle notarization
handle_notarization() {
    local pkg_path="$1"
    
    if [ "$SKIP_NOTARIZATION" = true ] || [ "$BUILD_TYPE" = "dev" ]; then
        log_info "Skipping notarization"
        return 0
    fi
    
    log_info "Starting notarization for: $(basename "$pkg_path")"
    
    # Check for required credentials
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        log_warning "Notarization credentials not available, skipping"
        return 0
    fi
    
    log_info "Submitting for notarization..."
    
    # Create temporary profile
    local profile_name="r2midi-notarization-$(date +%s)"
    
    if xcrun notarytool store-credentials "$profile_name" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" 2>/dev/null; then
        
        # Submit and wait
        local output
        if output=$(xcrun notarytool submit "$pkg_path" \
            --keychain-profile "$profile_name" \
            --wait \
            --timeout 30m 2>&1); then
            
            if echo "$output" | grep -q "status: Accepted"; then
                log_success "Notarization accepted"
                
                # Staple
                if xcrun stapler staple "$pkg_path"; then
                    log_success "Notarization stapled successfully"
                else
                    log_warning "Failed to staple (package is still notarized)"
                fi
                
                # Cleanup profile
                xcrun notarytool delete-credentials "$profile_name" 2>/dev/null || true
                return 0
            else
                log_error "Notarization failed: $output"
                xcrun notarytool delete-credentials "$profile_name" 2>/dev/null || true
                return 1
            fi
        else
            log_error "Notarization submission failed: $output"
            xcrun notarytool delete-credentials "$profile_name" 2>/dev/null || true
            return 1
        fi
    else
        log_error "Failed to create notarization profile"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Performing cleanup..."
    
    # Remove temporary keychain if created
    if [ -n "${TEMP_KEYCHAIN_NAME:-}" ]; then
        log_info "Removing temporary keychain: $TEMP_KEYCHAIN_NAME"
        security delete-keychain "$TEMP_KEYCHAIN_NAME" 2>/dev/null || true
    fi
    
    # Remove certificate files
    rm -rf /tmp/github_certs 2>/dev/null || true
    
    log_info "Cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Main function
main() {
    local start_time=$(date +%s)
    
    log_step "Starting Simplified Signing Process"
    
    # Setup macos-pkg-builder
    if ! setup_macos_pkg_builder; then
        log_error "Failed to setup macOS-Pkg-Builder"
        exit 1
    fi
    
    # Get signing identity
    if ! get_signing_identity; then
        log_error "Failed to get signing identity"
        exit 1
    fi
    
    # Process targets
    if process_targets; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "🎉 Signing and notarization completed successfully!"
        log_info "Total duration: ${duration}s"
        
        # Show final artifacts
        if [ -d "$PROJECT_ROOT/artifacts" ]; then
            log_info "Generated artifacts:"
            find "$PROJECT_ROOT/artifacts" -name "*.pkg" | while read -r pkg; do
                if [ -f "$pkg" ]; then
                    local size=$(du -sh "$pkg" | cut -f1)
                    local signed_status="unsigned"
                    if pkgutil --check-signature "$pkg" >/dev/null 2>&1; then
                        signed_status="signed"
                    fi
                    log_success "  $(basename "$pkg") ($size, $signed_status)"
                fi
            done
        fi
        
        exit 0
    else
        log_error "❌ Signing and notarization failed"
        exit 1
    fi
}

# Run main function
main "$@"
