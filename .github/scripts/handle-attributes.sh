#!/bin/bash
# handle-attributes.sh - Handle com.apple.provenance attribute issues

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "Usage: $0 <app_bundle_path>"
    exit 1
fi

echo "🔧 Fixing com.apple.provenance attributes in: $(basename "$APP_PATH")"

# Function to recreate a file without extended attributes
recreate_file_clean() {
    local file="$1"
    local temp_file="${file}.temp.$(date +%s)"
    
    # Copy the file content without extended attributes
    if dd if="$file" of="$temp_file" bs=1M 2>/dev/null; then
        # Preserve permissions
        chmod --reference="$file" "$temp_file" 2>/dev/null || true
        
        # Replace original with clean version
        mv "$temp_file" "$file"
        echo "  ✅ Recreated: $(basename "$file")"
        return 0
    else
        rm -f "$temp_file" 2>/dev/null || true
        echo "  ❌ Failed to recreate: $(basename "$file")"
        return 1
    fi
}

# First, try the standard approach
echo "  🧹 Attempting standard xattr removal..."
find "$APP_PATH" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

# Check if any com.apple.provenance attributes remain
REMAINING=$(find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | grep -c "com.apple.provenance" || echo "0")

if [ "$REMAINING" -eq 0 ]; then
    echo "  ✅ Successfully removed all com.apple.provenance attributes"
    exit 0
fi

echo "  ⚠️  $REMAINING files still have com.apple.provenance attributes"
echo "  🔧 Using file recreation method..."

# Find files with com.apple.provenance and recreate them
find "$APP_PATH" -type f | while read -r file; do
    if xattr -l "$file" 2>/dev/null | grep -q "com.apple.provenance"; then
        echo "  🔄 Processing: $(basename "$file")"
        recreate_file_clean "$file"
    fi
done

# Final verification
FINAL_COUNT=$(find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | grep -c "com.apple.provenance" || echo "0")

if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "  ✅ All com.apple.provenance attributes removed successfully!"
    exit 0
else
    echo "  ⚠️  $FINAL_COUNT files still have com.apple.provenance attributes"
    echo "  🔍 These may be system-protected attributes that cannot be removed"
    exit 0  # Don't fail the build for this
fi
