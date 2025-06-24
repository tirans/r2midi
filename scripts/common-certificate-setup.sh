#!/bin/bash

# common-certificate-setup.sh - Common certificate setup for all macOS builds
# This script provides a unified certificate loading and validation approach

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}▶ $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

# Global variables
CERT_LOADED=false
CERT_IDENTITY=""
CERT_TEAM_ID=""
CERT_TYPE=""
CERT_EXPIRY=""
CERT_SUMMARY=""

# Function to detect environment
detect_environment() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "github"
    else
        echo "local"
    fi
}

# Function to find local certificates
find_local_certificates() {
    local cert_dir="${1:-apple_credentials/certificates}"

    if [ -d "$cert_dir" ]; then
        find "$cert_dir" -name "*.p12" -type f 2>/dev/null
    else
        return 1
    fi
}

# Function to load certificate from P12 file
load_p12_certificate() {
    local p12_path="$1"
    local p12_password="${2:-x2G2srk2RHtp}"
    local keychain_name="${3:-r2midi-build}"

    log_info "Loading P12 certificate from: $p12_path"

    if [ ! -f "$p12_path" ]; then
        log_error "P12 file not found: $p12_path"
        return 1
    fi

    # Create temporary keychain
    local temp_keychain="/tmp/${keychain_name}-$(date +%s).keychain"
    local keychain_password="temp_pass_$(date +%s)"

    # Delete existing keychain if it exists
    security delete-keychain "$temp_keychain" 2>/dev/null || true

    # Create new keychain
    if ! security create-keychain -p "$keychain_password" "$temp_keychain"; then
        log_error "Failed to create temporary keychain"
        return 1
    fi

    # Configure keychain
    security set-keychain-settings -t 3600 -l "$temp_keychain"
    security unlock-keychain -p "$keychain_password" "$temp_keychain"

    # Add to keychain search list
    security list-keychains -d user -s "$temp_keychain" $(security list-keychains -d user | tr -d '"')

    # Import P12 certificate
    if ! security import "$p12_path" -k "$temp_keychain" -P "$p12_password" -T /usr/bin/codesign -T /usr/bin/productsign; then
        log_error "Failed to import P12 certificate"
        security delete-keychain "$temp_keychain" 2>/dev/null || true
        return 1
    fi

    # Set partition list
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$temp_keychain" 2>/dev/null || true

    # Store keychain info for cleanup
    echo "$temp_keychain" > /tmp/.r2midi_temp_keychain

    log_success "Certificate loaded successfully into temporary keychain"
    return 0
}

# Function to find signing identity
find_signing_identity() {
    local cert_type="${1:-Developer ID Application}"

    log_info "Searching for signing identity: $cert_type" >&2

    local identities=$(security find-identity -v -p codesigning 2>/dev/null | grep "$cert_type" || true)

    if [ -z "$identities" ]; then
        log_warning "No signing identities found for: $cert_type" >&2
        return 1
    fi

    # Extract the first matching identity
    local identity=$(echo "$identities" | head -1 | sed 's/.*"\(.*\)".*/\1/')

    if [ -n "$identity" ]; then
        log_success "Found signing identity: $identity" >&2
        echo "$identity"
        return 0
    fi

    return 1
}

# Function to validate certificate
validate_certificate() {
    local identity="$1"

    log_info "Validating certificate: $identity"

    # First check if the certificate appears in the codesigning identities
    local identities=$(security find-identity -v -p codesigning 2>/dev/null || true)

    if echo "$identities" | grep -F "$identity" >/dev/null 2>&1; then
        log_success "Certificate found in codesigning identities"

        # Try to extract additional info
        # Extract team ID from the identity string if it contains it
        if [[ "$identity" =~ \(([A-Z0-9]+)\) ]]; then
            CERT_TEAM_ID="${BASH_REMATCH[1]}"
            log_info "Team ID: $CERT_TEAM_ID"
        fi

        # For now, assume the certificate is valid if it appears in the identity list
        log_success "Certificate validation passed"
        return 0
    else
        log_error "Certificate not found in codesigning identities"
        return 1
    fi
}

# Function to setup certificates for build
setup_certificates() {
    local skip_signing="${1:-false}"

    log_section "Certificate Setup"

    if [ "$skip_signing" = "true" ]; then
        log_warning "Skipping certificate setup (--no-sign specified)"
        CERT_LOADED=false
        CERT_SUMMARY="Signing disabled"
        return 0
    fi

    local env_type=$(detect_environment)
    log_info "Environment: $env_type"

    # Try to find existing valid certificates first
    log_info "Checking for existing valid certificates..."

    # Check for Developer ID Application certificate
    if CERT_IDENTITY=$(find_signing_identity "Developer ID Application"); then
        if validate_certificate "$CERT_IDENTITY"; then
            CERT_LOADED=true
            CERT_TYPE="Developer ID Application"
            CERT_SUMMARY="Using existing certificate: $CERT_IDENTITY"
            log_success "Found valid existing certificate"
            return 0
        fi
    fi

    # If no existing certificate found, try to load from P12
    if [ "$env_type" = "local" ]; then
        log_info "No existing certificate found, attempting to load from P12 file..."

        # Look for P12 files
        local cert_dir="apple_credentials/certificates"
        log_info "Looking for P12 files in: $cert_dir"

        if [ -d "$cert_dir" ]; then
            local p12_files=$(find "$cert_dir" -name "*.p12" -type f 2>/dev/null)

            if [ -n "$p12_files" ]; then
                # Try each P12 file
                while IFS= read -r p12_file; do
                    log_info "Trying P12 file: $p12_file"

                    if load_p12_certificate "$p12_file"; then
                        # Check if certificate was loaded
                        if CERT_IDENTITY=$(find_signing_identity "Developer ID Application"); then
                            if validate_certificate "$CERT_IDENTITY"; then
                                CERT_LOADED=true
                                CERT_TYPE="Developer ID Application"
                                CERT_SUMMARY="Loaded certificate from P12: $(basename "$p12_file")"
                                log_success "Successfully loaded certificate from P12"
                                return 0
                            fi
                        fi
                    fi
                done <<< "$p12_files"
            else
                log_warning "No P12 files found in $cert_dir"
            fi
        else
            log_warning "Certificate directory not found: $cert_dir"
        fi
    fi

    # GitHub Actions environment
    if [ "$env_type" = "github" ]; then
        log_info "GitHub Actions environment - certificates should be loaded by workflow"

        # Check if certificates are available
        if CERT_IDENTITY=$(find_signing_identity "Developer ID Application"); then
            if validate_certificate "$CERT_IDENTITY"; then
                CERT_LOADED=true
                CERT_TYPE="Developer ID Application"
                CERT_SUMMARY="Using GitHub Actions certificate"
                return 0
            fi
        fi
    fi

    # No certificates available - but this is not a fatal error
    log_warning "No valid signing certificates found"
    log_info "Will create unsigned build"
    CERT_LOADED=false
    CERT_SUMMARY="No certificates available - unsigned build"
    return 0  # Return success so build can continue
}

# Function to cleanup temporary keychain
cleanup_certificates() {
    log_info "Cleaning up temporary certificates..."

    if [ -f /tmp/.r2midi_temp_keychain ]; then
        local temp_keychain=$(cat /tmp/.r2midi_temp_keychain)
        if [ -n "$temp_keychain" ]; then
            log_info "Removing temporary keychain: $temp_keychain"
            security delete-keychain "$temp_keychain" 2>/dev/null || true
        fi
        rm -f /tmp/.r2midi_temp_keychain
    fi

    log_success "Certificate cleanup completed"
}

# Function to get certificate summary
get_certificate_summary() {
    if [ "$CERT_LOADED" = "true" ]; then
        cat << EOF

📋 Certificate Summary:
  • Status: ✅ Loaded
  • Type: $CERT_TYPE
  • Identity: $CERT_IDENTITY
  • Team ID: ${CERT_TEAM_ID:-Unknown}
  • Expires: ${CERT_EXPIRY:-Unknown}
  • Summary: $CERT_SUMMARY
EOF
    else
        cat << EOF

📋 Certificate Summary:
  • Status: ❌ Not Loaded
  • Summary: $CERT_SUMMARY
EOF
    fi
}

# Function to print build summary with certificate info
print_build_summary() {
    local build_name="$1"
    local build_status="${2:-unknown}"
    local additional_info="${3:-}"

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}📊 Build Summary: $build_name${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    # Build status
    if [ "$build_status" = "success" ]; then
        echo -e "  • Build Status: ${GREEN}✅ Success${NC}"
    elif [ "$build_status" = "failed" ]; then
        echo -e "  • Build Status: ${RED}❌ Failed${NC}"
    else
        echo -e "  • Build Status: ${YELLOW}⚠️  $build_status${NC}"
    fi

    # Certificate info
    if [ "$CERT_LOADED" = "true" ]; then
        echo -e "  • Signing: ${GREEN}✅ Enabled${NC}"
        echo -e "  • Certificate: $CERT_IDENTITY"
        [ -n "$CERT_TEAM_ID" ] && echo -e "  • Team ID: $CERT_TEAM_ID"
    else
        echo -e "  • Signing: ${YELLOW}⚠️  Disabled${NC}"
        echo -e "  • Reason: $CERT_SUMMARY"
    fi

    # Additional info
    if [ -n "$additional_info" ]; then
        echo ""
        echo "$additional_info"
    fi

    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

# Export all functions and variables
export -f log_info log_success log_warning log_error log_section
export -f detect_environment find_local_certificates load_p12_certificate
export -f find_signing_identity validate_certificate setup_certificates
export -f cleanup_certificates get_certificate_summary print_build_summary
export CERT_LOADED CERT_IDENTITY CERT_TEAM_ID CERT_TYPE CERT_EXPIRY CERT_SUMMARY

# If script is run directly (not sourced), show usage
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Common Certificate Setup Script"
    echo ""
    echo "This script should be sourced by build scripts:"
    echo "  source $(dirname "$0")/scripts/common-certificate-setup.sh"
    echo ""
    echo "Functions provided:"
    echo "  • setup_certificates [skip_signing]"
    echo "  • cleanup_certificates"
    echo "  • get_certificate_summary"
    echo "  • print_build_summary"
    echo ""
    echo "Example usage:"
    echo "  setup_certificates false"
    echo "  # ... do build ..."
    echo "  cleanup_certificates"
    echo "  print_build_summary 'MyApp' 'success'"
fi
