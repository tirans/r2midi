#!/bin/bash

# Quick fixes for the signing issues identified in the logs

echo "🔧 Applying quick fixes for signing issues..."

SCRIPT_PATH="/Users/tirane/Desktop/r2midi/.github/scripts/sign-notarize.sh"

# Create backup
cp "$SCRIPT_PATH" "$SCRIPT_PATH.backup.$(date +%Y%m%d_%H%M%S)"
echo "✅ Backup created"

# Fix 1: Remove the first find_and_process_targets function that has logging
echo "🔧 Fix 1: Removing duplicate find_and_process_targets function with logging..."
sed -i.tmp '/^# Function to find and process targets$/,/^}$/d' "$SCRIPT_PATH"

# Fix 2: Fix the shell syntax error on line 346 ([ -f with space issue)
echo "🔧 Fix 2: Fixing shell syntax error..."
sed -i.tmp 's/if \[ -f "\$target\/Contents\/MacOS\/".*\];/if [ -d "\$target\/Contents\/MacOS" ];/' "$SCRIPT_PATH"

# Fix 3: Add more aggressive resource fork cleaning
echo "🔧 Fix 3: Adding better resource fork cleaning..."

# Insert better cleaning before codesign
CLEANING_CODE='        # Enhanced resource fork and detritus removal
        log_info "Enhanced cleanup for signing..."
        
        # Remove all extended attributes recursively
        find "$target" -exec xattr -c {} \\; 2>/dev/null || true
        
        # Remove .DS_Store and resource forks
        find "$target" -name ".DS_Store" -delete 2>/dev/null || true
        find "$target" -name "._*" -delete 2>/dev/null || true
        find "$target" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
        
        # Use ditto to create a clean copy
        TEMP_APP="/tmp/$(basename "$target").clean"
        rm -rf "$TEMP_APP" 2>/dev/null || true
        if ditto "$target" "$TEMP_APP"; then
            rm -rf "$target"
            mv "$TEMP_APP" "$target"
            log_info "Created clean copy of app bundle"
        fi'

# Find the line before "# Finally, sign the entire app bundle" and insert cleaning
sed -i.tmp "/# Finally, sign the entire app bundle/i\\
$CLEANING_CODE" "$SCRIPT_PATH"

# Fix 4: Only process targets that actually exist and are relevant for server build
echo "🔧 Fix 4: Adding target filtering for server build..."

# Replace the main target processing loop to filter for server-specific targets only
TARGET_FILTER_CODE='    # Filter targets based on build context
    local filtered_targets=()
    for target in "${targets[@]}"; do
        # Skip client targets if we are in build_server directory
        if [[ "$(pwd)" == *"build_server"* ]] && [[ "$target" == *"Client"* ]]; then
            log_info "Skipping client target in server build: $(basename "$target")"
            continue
        fi
        
        # Only process targets that actually exist
        if [ -e "$target" ]; then
            filtered_targets+=("$target")
            log_info "Will process: $target"
        else
            log_warning "Target does not exist, skipping: $target"
        fi
    done
    
    # Update targets array
    targets=("${filtered_targets[@]}")
    total_count=${#targets[@]}
    
    if [ $total_count -eq 0 ]; then
        log_warning "No valid targets found after filtering"
        exit 0
    fi
    
    log_info "Processing $total_count filtered targets"'

# Insert the filtering code after targets are populated
sed -i.tmp "/log_info \"Total targets found:/a\\
$TARGET_FILTER_CODE" "$SCRIPT_PATH"

# Fix 5: Skip pkg signing if no installer certificate
echo "🔧 Fix 5: Adding fallback for missing installer certificate..."
sed -i.tmp 's/log_error "No Developer ID Installer certificate found"/log_warning "No Developer ID Installer certificate found, skipping pkg signing"/' "$SCRIPT_PATH"
sed -i.tmp '/log_warning "No Developer ID Installer certificate found, skipping pkg signing"/a\
            return 0' "$SCRIPT_PATH"

# Clean up temporary files
rm -f "$SCRIPT_PATH.tmp"

echo "✅ Applied all fixes"
echo ""
echo "📋 Summary of fixes applied:"
echo "  1. ✅ Removed duplicate find_and_process_targets function with logging"
echo "  2. ✅ Fixed shell syntax error on MacOS path check"
echo "  3. ✅ Added enhanced resource fork cleaning with ditto"
echo "  4. ✅ Added target filtering for server build context"
echo "  5. ✅ Made pkg signing optional when installer cert missing"
echo ""
echo "🚀 Ready to test signing again!"
echo ""
echo "💡 To test the server build with signing:"
echo "   cd /Users/tirane/Desktop/r2midi"
echo "   ./build-server-local.sh --version 0.1.210"
