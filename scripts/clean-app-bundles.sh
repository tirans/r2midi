#!/bin/bash
set -euo pipefail

# clean-app-bundles.sh - Clean all app bundles before signing

echo "🧹 App Bundle Bulletproof Cleaning"
echo "================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN_SCRIPT="$SCRIPT_DIR/bulletproof_clean_app_bundle.py"

# Make clean script executable
chmod +x "$CLEAN_SCRIPT"

# Function to clean a single app bundle
clean_app() {
    local app_path="$1"
    echo "Cleaning: $(basename "$app_path")"
    
    # Try ditto method first (most reliable)
    if python3 "$CLEAN_SCRIPT" --method ditto "$app_path"; then
        echo "✅ Successfully cleaned with ditto: $(basename "$app_path")"
        return 0
    else
        # Fallback to auto method
        echo "⚠️  Ditto failed, trying auto method..."
        if python3 "$CLEAN_SCRIPT" --method auto "$app_path"; then
            echo "✅ Successfully cleaned with auto: $(basename "$app_path")"
            return 0
        else
            echo "❌ Failed to clean: $(basename "$app_path")"
            return 1
        fi
    fi
}

# Find and clean all app bundles
find_and_clean_apps() {
    local search_paths=("build_client/dist" "build_server/dist" "dist" ".")
    local found_apps=0
    local cleaned_apps=0
    
    for search_path in "${search_paths[@]}"; do
        if [ -d "$search_path" ]; then
            while IFS= read -r -d '' app; do
                found_apps=$((found_apps + 1))
                if clean_app "$app"; then
                    cleaned_apps=$((cleaned_apps + 1))
                fi
            done < <(find "$search_path" -name "*.app" -type d -print0 2>/dev/null)
        fi
    done
    
    echo ""
    echo "Summary:"
    echo "- Found $found_apps app bundle(s)"
    echo "- Successfully cleaned $cleaned_apps app bundle(s)"
    
    if [ "$found_apps" -eq 0 ]; then
        echo "⚠️  No app bundles found"
        return 1
    elif [ "$cleaned_apps" -lt "$found_apps" ]; then
        echo "⚠️  Some app bundles failed to clean"
        return 1
    else
        echo "✅ All app bundles cleaned successfully"
        return 0
    fi
}

# Main execution
if [ $# -gt 0 ]; then
    # Clean specific app bundle(s) passed as arguments
    for app_path in "$@"; do
        clean_app "$app_path"
    done
else
    # Auto-find and clean all app bundles
    find_and_clean_apps
fi
