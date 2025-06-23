#!/bin/bash
# Additional module for enhanced signing cleanup

# Function to perform deep app bundle cleanup
deep_clean_app_bundle() {
    local app_path="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(cd "$script_dir/../../.." && pwd)"
    local deep_clean_script="$project_root/scripts/deep_clean_app_bundle.py"
    
    if [ ! -e "$app_path" ]; then
        log_error "App bundle does not exist: $app_path"
        return 1
    fi
    
    if [ -f "$deep_clean_script" ]; then
        log_info "Running deep clean on $(basename "$app_path")..."
        
        # Make script executable
        chmod +x "$deep_clean_script"
        
        # Run deep clean
        if python3 "$deep_clean_script" "$app_path"; then
            log_success "Deep clean completed successfully"
            
            # Verify cleanup
            local xattr_count=$(find "$app_path" -exec xattr -l {} \; 2>/dev/null | wc -l || echo "0")
            log_info "Remaining extended attributes: $xattr_count"
            
            if [ "$xattr_count" -eq 0 ]; then
                log_success "App bundle is completely clean"
                return 0
            else
                log_warning "Some extended attributes remain"
                return 0  # Continue anyway
            fi
        else
            log_error "Deep clean script failed"
            return 1
        fi
    else
        log_warning "Deep clean script not found, using fallback cleanup"
        
        # Fallback cleanup
        find "$app_path" -name ".DS_Store" -delete 2>/dev/null || true
        find "$app_path" -name "._*" -delete 2>/dev/null || true
        find "$app_path" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
        xattr -cr "$app_path" 2>/dev/null || true
        
        return 0
    fi
}

# Export the function for use in other scripts
export -f deep_clean_app_bundle
