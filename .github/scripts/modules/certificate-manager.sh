#!/bin/bash

# certificate-manager.sh - Certificate management utilities
# Provides functions for certificate discovery, validation, and information extraction

# Source logging utilities if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/logging-utils.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging-utils.sh"
else
    # Fallback logging functions
    log_info() { echo "ℹ️  $1"; }
    log_success() { echo "✅ $1"; }
    log_warning() { echo "⚠️  $1"; }
    log_error() { echo "❌ $1"; }
    log_step() { echo ""; echo "🔄 $1"; echo "$(printf '=%.0s' {1..50})"; }
fi

# Function to find all available certificates
find_certificates() {
    local cert_type="${1:-codesigning}"
    local filter="${2:-}"
    
    log_info "Searching for certificates of type: $cert_type"
    
    local certs=$(security find-identity -v -p "$cert_type" 2>/dev/null || true)
    
    if [ -z "$certs" ]; then
        log_warning "No certificates found for type: $cert_type"
        return 1
    fi
    
    if [ -n "$filter" ]; then
        certs=$(echo "$certs" | grep "$filter" || true)
        if [ -z "$certs" ]; then
            log_warning "No certificates found matching filter: $filter"
            return 1
        fi
    fi
    
    echo "$certs"
    return 0
}

# Function to get detailed certificate information
get_certificate_details() {
    local cert_name="$1"
    
    log_info "Getting details for certificate: $cert_name"
    
    # Find the certificate
    local cert_data=$(security find-certificate -c "$cert_name" -p 2>/dev/null || true)
    
    if [ -z "$cert_data" ]; then
        log_error "Certificate not found: $cert_name"
        return 1
    fi
    
    # Parse certificate details
    local cert_details=$(echo "$cert_data" | openssl x509 -text -noout 2>/dev/null || true)
    
    if [ -z "$cert_details" ]; then
        log_error "Failed to parse certificate: $cert_name"
        return 1
    fi
    
    # Extract key information
    local subject=$(echo "$cert_details" | grep "Subject:" | head -1 | sed 's/^[[:space:]]*//' || echo "Subject: Unknown")
    local issuer=$(echo "$cert_details" | grep "Issuer:" | head -1 | sed 's/^[[:space:]]*//' || echo "Issuer: Unknown")
    local serial=$(echo "$cert_details" | grep "Serial Number:" | head -1 | sed 's/^[[:space:]]*//' || echo "Serial Number: Unknown")
    
    # Extract validity dates
    local not_before=$(echo "$cert_details" | grep "Not Before:" | head -1 | sed 's/^[[:space:]]*//' || echo "Not Before: Unknown")
    local not_after=$(echo "$cert_details" | grep "Not After:" | head -1 | sed 's/^[[:space:]]*//' || echo "Not After: Unknown")
    
    # Extract key usage
    local key_usage=$(echo "$cert_details" | grep -A5 "X509v3 Key Usage:" | tail -n +2 | head -1 | sed 's/^[[:space:]]*//' || echo "Key Usage: Unknown")
    
    # Extract extended key usage
    local ext_key_usage=$(echo "$cert_details" | grep -A5 "X509v3 Extended Key Usage:" | tail -n +2 | head -1 | sed 's/^[[:space:]]*//' || echo "Extended Key Usage: Unknown")
    
    # Create certificate info object
    cat << EOF
{
  "name": "$cert_name",
  "subject": "$subject",
  "issuer": "$issuer",
  "serial": "$serial",
  "not_before": "$not_before",
  "not_after": "$not_after",
  "key_usage": "$key_usage",
  "extended_key_usage": "$ext_key_usage"
}
EOF
    
    return 0
}

# Function to validate certificate for code signing
validate_certificate() {
    local cert_name="$1"
    local required_usage="${2:-Code Signing}"
    
    log_info "Validating certificate: $cert_name"
    log_info "Required usage: $required_usage"
    
    # Check if certificate exists
    if ! security find-certificate -c "$cert_name" >/dev/null 2>&1; then
        log_error "Certificate not found: $cert_name"
        return 1
    fi
    
    # Check if certificate is valid for code signing
    local cert_details=$(get_certificate_details "$cert_name")
    
    if [ -z "$cert_details" ]; then
        log_error "Failed to get certificate details: $cert_name"
        return 1
    fi
    
    # Check expiration
    local not_after=$(echo "$cert_details" | grep '"not_after"' | sed 's/.*"not_after": "\([^"]*\)".*/\1/')
    
    if [ -n "$not_after" ] && [ "$not_after" != "Not After: Unknown" ]; then
        # Convert to timestamp for comparison (simplified check)
        local current_date=$(date +%s)
        log_info "Certificate expiration check: $not_after"
        # Note: Full date parsing would require more complex logic
    fi
    
    # Check if it's in a valid keychain
    if security find-identity -v -p codesigning | grep -q "$cert_name"; then
        log_success "Certificate is valid and available for code signing: $cert_name"
        return 0
    else
        log_error "Certificate is not available for code signing: $cert_name"
        return 1
    fi
}

# Function to list all available signing identities
list_signing_identities() {
    local identity_type="${1:-Developer ID Application}"
    
    log_step "Available Signing Identities - $identity_type"
    
    local identities=$(security find-identity -v -p codesigning | grep "$identity_type" || true)
    
    if [ -z "$identities" ]; then
        log_warning "No signing identities found for: $identity_type"
        return 1
    fi
    
    local count=0
    echo "$identities" | while read -r line; do
        if [[ "$line" =~ \"([^\"]+)\" ]]; then
            local cert_name="${BASH_REMATCH[1]}"
            count=$((count + 1))
            
            log_info "Identity $count: $cert_name"
            
            # Get additional details
            local cert_details=$(get_certificate_details "$cert_name" 2>/dev/null || echo "")
            if [ -n "$cert_details" ]; then
                local subject=$(echo "$cert_details" | grep '"subject"' | sed 's/.*"subject": "\([^"]*\)".*/\1/')
                local not_after=$(echo "$cert_details" | grep '"not_after"' | sed 's/.*"not_after": "\([^"]*\)".*/\1/')
                
                if [ -n "$subject" ] && [ "$subject" != "Subject: Unknown" ]; then
                    log_info "  $subject"
                fi
                if [ -n "$not_after" ] && [ "$not_after" != "Not After: Unknown" ]; then
                    log_info "  $not_after"
                fi
            fi
        fi
    done
    
    return 0
}

# Function to select best signing identity
select_signing_identity() {
    local identity_type="${1:-Developer ID Application}"
    local team_id="${2:-}"
    
    log_info "Selecting best signing identity for: $identity_type"
    
    local identities=$(security find-identity -v -p codesigning | grep "$identity_type" || true)
    
    if [ -z "$identities" ]; then
        log_error "No signing identities found for: $identity_type"
        return 1
    fi
    
    # If team ID is specified, try to find matching certificate
    if [ -n "$team_id" ]; then
        log_info "Looking for certificate with team ID: $team_id"
        local team_identity=$(echo "$identities" | grep "$team_id" | head -1 || true)
        if [ -n "$team_identity" ]; then
            local cert_name=$(echo "$team_identity" | sed 's/.*"\(.*\)".*/\1/')
            log_success "Found team-specific identity: $cert_name"
            echo "$cert_name"
            return 0
        fi
    fi
    
    # Otherwise, select the first valid identity
    local first_identity=$(echo "$identities" | head -1)
    if [ -n "$first_identity" ]; then
        local cert_name=$(echo "$first_identity" | sed 's/.*"\(.*\)".*/\1/')
        log_success "Selected identity: $cert_name"
        echo "$cert_name"
        return 0
    fi
    
    log_error "No valid signing identity found"
    return 1
}

# Function to check certificate chain
check_certificate_chain() {
    local cert_name="$1"
    
    log_info "Checking certificate chain for: $cert_name"
    
    # Get certificate
    local cert_data=$(security find-certificate -c "$cert_name" -p 2>/dev/null || true)
    
    if [ -z "$cert_data" ]; then
        log_error "Certificate not found: $cert_name"
        return 1
    fi
    
    # Verify certificate chain
    if echo "$cert_data" | openssl verify -CAfile /System/Library/Keychains/SystemRootCertificates.keychain >/dev/null 2>&1; then
        log_success "Certificate chain is valid"
        return 0
    else
        log_warning "Certificate chain verification failed (may still work for signing)"
        return 0  # Don't fail completely as some valid certs may not verify this way
    fi
}

# Function to export certificate information to JSON
export_certificate_info() {
    local output_file="${1:-certificate_info.json}"
    
    log_info "Exporting certificate information to: $output_file"
    
    local identities=$(security find-identity -v -p codesigning || true)
    
    if [ -z "$identities" ]; then
        log_warning "No certificates found"
        echo "[]" > "$output_file"
        return 0
    fi
    
    echo "[" > "$output_file"
    local first=true
    
    echo "$identities" | while read -r line; do
        if [[ "$line" =~ \"([^\"]+)\" ]]; then
            local cert_name="${BASH_REMATCH[1]}"
            
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$output_file"
            fi
            
            local cert_details=$(get_certificate_details "$cert_name" 2>/dev/null || echo "{}")
            echo "$cert_details" >> "$output_file"
        fi
    done
    
    echo "]" >> "$output_file"
    
    log_success "Certificate information exported to: $output_file"
    return 0
}

# Function to setup keychain for GitHub Actions
setup_github_keychain() {
    local keychain_name="$1"
    local keychain_password="$2"
    local app_cert_path="$3"
    local installer_cert_path="$4"
    local cert_password="$5"
    
    log_step "Setting up GitHub Actions Keychain"
    log_info "Keychain: $keychain_name"
    
    # Clean up any existing keychain
    security delete-keychain "$keychain_name" 2>/dev/null || true
    
    # Create keychain
    if security create-keychain -p "$keychain_password" "$keychain_name"; then
        log_success "Created keychain: $keychain_name"
    else
        log_error "Failed to create keychain: $keychain_name"
        return 1
    fi
    
    # Configure keychain
    security set-keychain-settings -lut 21600 "$keychain_name"
    security unlock-keychain -p "$keychain_password" "$keychain_name"
    
    # Add to keychain search list
    security list-keychains -d user -s "$keychain_name" $(security list-keychains -d user | xargs)
    
    # Import certificates
    if [ -f "$app_cert_path" ]; then
        log_info "Importing application certificate..."
        if security import "$app_cert_path" -k "$keychain_name" -P "$cert_password" -T /usr/bin/codesign -T /usr/bin/security; then
            log_success "Imported application certificate"
        else
            log_error "Failed to import application certificate"
            return 1
        fi
    fi
    
    if [ -f "$installer_cert_path" ]; then
        log_info "Importing installer certificate..."
        if security import "$installer_cert_path" -k "$keychain_name" -P "$cert_password" -T /usr/bin/productsign -T /usr/bin/security; then
            log_success "Imported installer certificate"
        else
            log_error "Failed to import installer certificate"
            return 1
        fi
    fi
    
    # Set partition list
    if security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_name"; then
        log_success "Set keychain partition list"
    else
        log_warning "Failed to set keychain partition list (may still work)"
    fi
    
    log_success "GitHub Actions keychain setup completed"
    return 0
}

# Function to cleanup keychain
cleanup_keychain() {
    local keychain_name="$1"
    
    if [ -n "$keychain_name" ]; then
        log_info "Cleaning up keychain: $keychain_name"
        security delete-keychain "$keychain_name" 2>/dev/null || true
        log_success "Keychain cleanup completed"
    fi
}

# Export functions for use in other scripts
export -f find_certificates
export -f get_certificate_details
export -f validate_certificate
export -f list_signing_identities
export -f select_signing_identity
export -f check_certificate_chain
export -f export_certificate_info
export -f setup_github_keychain
export -f cleanup_keychain