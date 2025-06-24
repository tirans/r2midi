#!/bin/bash
set -euo pipefail

# sign-pkg.sh - Sign and notarize .pkg files
# Supports both local builds (using app_config.json) and GitHub Actions (using secrets)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source logging utilities
if [ -f "$MODULES_DIR/logging-utils.sh" ]; then
    source "$MODULES_DIR/logging-utils.sh"
else
    # Fallback logging functions
    log_info() { echo "ℹ️  $1"; }
    log_success() { echo "✅ $1"; }
    log_warning() { echo "⚠️  $1"; }
    log_error() { echo "❌ $1"; }
    log_step() { echo ""; echo "🔄 $1"; echo "$(printf '=%.0s' {1..50})"; }
fi

# Default values
PKG_PATH=""
SKIP_NOTARIZATION=false
TEMP_KEYCHAIN=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --pkg)
            PKG_PATH="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --help)
            cat << EOF
PKG Signing and Notarization Script

Usage: $0 --pkg <path_to_pkg> [options]

Options:
  --pkg PATH           Path to the .pkg file to sign and notarize
  --skip-notarize      Skip notarization step
  --help               Show this help

Examples:
  $0 --pkg artifacts/MyApp-1.0.0.pkg
  $0 --pkg artifacts/MyApp-1.0.0.pkg --skip-notarize
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
if [ -z "$PKG_PATH" ]; then
    log_error "PKG path is required. Use --pkg <path>"
    exit 1
fi

if [ ! -f "$PKG_PATH" ]; then
    log_error "PKG file does not exist: $PKG_PATH"
    exit 1
fi

log_step "PKG Signing and Notarization"
log_info "PKG Path: $PKG_PATH"
log_info "Skip Notarization: $SKIP_NOTARIZATION"

# Determine environment type
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    ENV_TYPE="github"
    log_info "Environment: GitHub Actions"
else
    ENV_TYPE="local"
    log_info "Environment: Local Build"
fi

# Function to cleanup temporary files
cleanup_temp_files() {
    if [ -n "${TEMP_CERT_DIR:-}" ] && [ -d "$TEMP_CERT_DIR" ]; then
        log_info "Cleaning up temporary certificate files: $TEMP_CERT_DIR"
        rm -rf "$TEMP_CERT_DIR" 2>/dev/null || true
    fi
}

# Set up cleanup trap
trap cleanup_temp_files EXIT

# Function to setup certificates for local builds
setup_local_certificates() {
    log_step "Setting up certificates for local build"

    # Find project root directory (go up from .github/scripts to project root)
    local project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"

    # Read configuration from app_config.json
    local config_file="$project_root/apple_credentials/config/app_config.json"
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Extract configuration values
    local p12_path=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['p12_path'])" 2>/dev/null || echo "")
    local p12_password=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['p12_password'])" 2>/dev/null || echo "")

    if [ -z "$p12_path" ] || [ -z "$p12_password" ]; then
        log_error "Failed to read p12_path or p12_password from $config_file"
        return 1
    fi

    local installer_cert_path="$project_root/${p12_path}/installer_cert.p12"

    if [ ! -f "$installer_cert_path" ]; then
        log_error "Installer certificate not found: $installer_cert_path"
        return 1
    fi

    log_info "Found installer certificate: $installer_cert_path"

    # Import certificate to login keychain (no password prompt)
    log_info "Importing installer certificate to login keychain..."
    if security import "$installer_cert_path" -P "$p12_password" -T /usr/bin/productsign -A 2>/dev/null; then
        log_success "Certificate imported successfully"
    else
        log_warning "Certificate may already be imported or import failed"
    fi

    # Find the installer identity with multiple approaches
    local installer_identity=""

    # Try method 1: Standard identity search
    installer_identity=$(security find-identity -v | grep "Developer ID Installer" | head -1 | sed 's/.*) //' | sed 's/"//g' || echo "")

    # Try method 2: Search in login keychain specifically
    if [ -z "$installer_identity" ]; then
        log_info "Trying to find identity in login keychain specifically..."
        installer_identity=$(security find-identity -v ~/Library/Keychains/login.keychain-db | grep "Developer ID Installer" | head -1 | sed 's/.*) //' | sed 's/"//g' || echo "")
    fi

    # Try method 3: Search for certificate and extract common name
    if [ -z "$installer_identity" ]; then
        log_info "Trying to find certificate by common name..."
        installer_identity=$(security find-certificate -a -c "Developer ID Installer" | grep "labl" | head -1 | sed 's/.*"labl"<blob>="//' | sed 's/"$//' || echo "")
    fi

    # Try method 4: Use the certificate subject from the imported certificate
    if [ -z "$installer_identity" ]; then
        log_info "Using certificate subject from imported certificate..."
        installer_identity="Developer ID Installer: Tiran Efrat (79449BGAM5)"
    fi

    if [ -z "$installer_identity" ]; then
        log_error "Failed to find installer identity in keychain"
        log_info "Available identities:"
        security find-identity -v || true
        log_info "Available certificates:"
        security find-certificate -a -p | grep -c "BEGIN CERTIFICATE" || echo "0"
        return 1
    fi

    log_success "Installer identity found: $installer_identity"
    export INSTALLER_IDENTITY="$installer_identity"
    return 0
}

# Function to setup certificates for GitHub Actions
setup_github_certificates() {
    log_step "Setting up certificates for GitHub Actions"

    # Check required environment variables
    if [ -z "${APPLE_DEVELOPER_ID_INSTALLER_CERT:-}" ]; then
        log_error "APPLE_DEVELOPER_ID_INSTALLER_CERT environment variable is not set"
        return 1
    fi

    if [ -z "${APPLE_CERT_PASSWORD:-}" ]; then
        log_error "APPLE_CERT_PASSWORD environment variable is not set"
        return 1
    fi

    # Create temporary directory for certificates
    local cert_dir="/tmp/github_certs"
    mkdir -p "$cert_dir"

    # Decode and save installer certificate
    local installer_cert_path="$cert_dir/installer_cert.p12"
    echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > "$installer_cert_path"

    log_info "Installer certificate saved to: $installer_cert_path"

    # Import certificate to login keychain (no password prompt)
    log_info "Importing installer certificate to login keychain..."
    if security import "$installer_cert_path" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/productsign -A 2>/dev/null; then
        log_success "Certificate imported successfully"
    else
        log_warning "Certificate may already be imported or import failed"
    fi

    # Find the installer identity with multiple approaches
    local installer_identity=""

    # Try method 1: Standard identity search
    installer_identity=$(security find-identity -v | grep "Developer ID Installer" | head -1 | sed 's/.*) //' | sed 's/"//g' || echo "")

    # Try method 2: Search in login keychain specifically
    if [ -z "$installer_identity" ]; then
        log_info "Trying to find identity in login keychain specifically..."
        installer_identity=$(security find-identity -v ~/Library/Keychains/login.keychain-db | grep "Developer ID Installer" | head -1 | sed 's/.*) //' | sed 's/"//g' || echo "")
    fi

    # Try method 3: Search for certificate and extract common name
    if [ -z "$installer_identity" ]; then
        log_info "Trying to find certificate by common name..."
        installer_identity=$(security find-certificate -a -c "Developer ID Installer" | grep "labl" | head -1 | sed 's/.*"labl"<blob>="//' | sed 's/"$//' || echo "")
    fi

    # Try method 4: Use the certificate subject from the imported certificate
    if [ -z "$installer_identity" ]; then
        log_info "Using certificate subject from imported certificate..."
        installer_identity="Developer ID Installer: Tiran Efrat (79449BGAM5)"
    fi

    if [ -z "$installer_identity" ]; then
        log_error "Failed to find installer identity in keychain"
        log_info "Available identities:"
        security find-identity -v || true
        log_info "Available certificates:"
        security find-certificate -a -p | grep -c "BEGIN CERTIFICATE" || echo "0"
        return 1
    fi

    log_success "Installer identity found: $installer_identity"
    export INSTALLER_IDENTITY="$installer_identity"
    return 0
}

# Function to sign PKG
sign_pkg() {
    local pkg_path="$1"
    local installer_identity="$2"

    log_step "Signing PKG"
    log_info "PKG: $pkg_path"
    log_info "Identity: $installer_identity"

    # Create signed PKG path
    local pkg_dir=$(dirname "$pkg_path")
    local pkg_name=$(basename "$pkg_path" .pkg)
    local signed_pkg_path="${pkg_dir}/${pkg_name}-signed.pkg"

    # Sign the PKG
    log_info "Signing PKG with productsign..."
    if productsign --sign "$installer_identity" "$pkg_path" "$signed_pkg_path"; then
        log_success "PKG signed successfully: $signed_pkg_path"

        # Replace original with signed version
        mv "$signed_pkg_path" "$pkg_path"
        log_info "Replaced original PKG with signed version"

        # Verify signature
        log_info "Verifying PKG signature..."
        if pkgutil --check-signature "$pkg_path"; then
            log_success "PKG signature verified"
        else
            log_warning "PKG signature verification failed"
        fi

        return 0
    else
        log_error "Failed to sign PKG"
        return 1
    fi
}

# Function to notarize PKG
notarize_pkg() {
    local pkg_path="$1"

    if [ "$SKIP_NOTARIZATION" = "true" ]; then
        log_info "Skipping notarization as requested"
        return 0
    fi

    log_step "Notarizing PKG"
    log_info "PKG: $pkg_path"

    # Get Apple ID and password based on environment
    local apple_id=""
    local apple_password=""
    local team_id=""

    if [ "$ENV_TYPE" = "github" ]; then
        apple_id="${APPLE_ID:-}"
        apple_password="${APPLE_ID_PASSWORD:-}"
        team_id="${APPLE_TEAM_ID:-}"
    else
        # Read from app_config.json
        local config_file="apple_credentials/config/app_config.json"
        if [ -f "$config_file" ]; then
            apple_id=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['apple_id'])" 2>/dev/null || echo "")
            apple_password=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['app_specific_password'])" 2>/dev/null || echo "")
            team_id=$(python3 -c "import json; print(json.load(open('$config_file'))['apple_developer']['team_id'])" 2>/dev/null || echo "")
        fi
    fi

    if [ -z "$apple_id" ] || [ -z "$apple_password" ] || [ -z "$team_id" ]; then
        log_error "Missing Apple ID, password, or team ID for notarization"
        return 1
    fi

    log_info "Apple ID: $apple_id"
    log_info "Team ID: $team_id"

    # Submit for notarization
    log_info "Submitting PKG for notarization..."
    local submit_output=$(xcrun notarytool submit "$pkg_path" \
        --apple-id "$apple_id" \
        --password "$apple_password" \
        --team-id "$team_id" \
        --wait 2>&1)

    if echo "$submit_output" | grep -q "status: Accepted"; then
        log_success "PKG notarization completed successfully"

        # Staple the notarization
        log_info "Stapling notarization to PKG..."
        if xcrun stapler staple "$pkg_path"; then
            log_success "Notarization stapled successfully"
        else
            log_warning "Failed to staple notarization (PKG is still notarized)"
        fi

        return 0
    else
        log_error "PKG notarization failed"
        log_error "Output: $submit_output"
        return 1
    fi
}

# Main execution
main() {
    log_step "Starting PKG signing and notarization process"

    # Setup certificates based on environment and get installer identity
    local installer_identity=""
    if [ "$ENV_TYPE" = "github" ]; then
        setup_github_certificates
        installer_identity="$INSTALLER_IDENTITY"
    else
        setup_local_certificates
        installer_identity="$INSTALLER_IDENTITY"
    fi

    if [ -z "$installer_identity" ]; then
        log_error "Failed to get installer identity"
        exit 1
    fi


    # Sign the PKG
    if ! sign_pkg "$PKG_PATH" "$installer_identity"; then
        log_error "Failed to sign PKG"
        exit 1
    fi

    # Notarize the PKG
    if ! notarize_pkg "$PKG_PATH"; then
        log_error "Failed to notarize PKG"
        exit 1
    fi

    log_success "PKG signing and notarization completed successfully!"
    log_info "Signed and notarized PKG: $PKG_PATH"
}

# Run main function
main
