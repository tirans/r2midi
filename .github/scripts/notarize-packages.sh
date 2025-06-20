#!/bin/bash

# notarize-packages.sh - Notarize packages with Apple notarytool
# Usage: ./notarize-packages.sh

set -euo pipefail

echo "📤 Notarizing packages with Apple notarytool..."
echo "🚫 IMPORTANT: Not using Briefcase - using native Apple notarytool"
echo "This process may take 5-30 minutes depending on Apple's queue..."

# Check required environment variables
required_vars=(
    "APPLE_ID"
    "APPLE_ID_PASSWORD"
    "APPLE_TEAM_ID"
)

echo "🔍 Verifying Apple credentials..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "❌ $var not set. Run setup-apple-certificates.sh first."
        exit 1
    fi
done

echo "✅ Apple credentials verified"
echo "Apple ID: $APPLE_ID"
echo "Team ID: $APPLE_TEAM_ID"

# Function to notarize a file with proper error handling
notarize_file_native() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local file_type="${file_name##*.}"
    
    echo ""
    echo "📤 Submitting $file_name for notarization..."
    echo "  File type: $file_type"
    echo "  File size: $(du -h "$file_path" | cut -f1)"
    
    # Verify file is signed before notarization
    echo "  🔍 Verifying file signature..."
    if ! codesign --verify --verbose "$file_path" 2>/dev/null; then
        echo "  ❌ File is not signed - cannot notarize"
        return 1
    fi
    echo "  ✅ File signature verified"
    
    # Submit for notarization with increased timeout
    echo "  🔄 Starting notarization submission..."
    local submit_output
    local start_time=$(date +%s)
    
    submit_output=$(xcrun notarytool submit "$file_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --timeout 45m \
        2>&1)
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "  ⏱️ Notarization took ${duration} seconds"
    echo "  📋 Notarization output for $file_name:"
    echo "$submit_output" | head -20  # Show first 20 lines to avoid log spam
    
    if [ $exit_code -eq 0 ] && echo "$submit_output" | grep -q "status: Accepted"; then
        echo "  ✅ Notarization successful for $file_name"
        
        echo "  📎 Stapling notarization ticket..."
        if xcrun stapler staple "$file_path"; then
            echo "  ✅ Successfully stapled notarization ticket to $file_name"
            
            echo "  🔍 Verifying stapled ticket..."
            if xcrun stapler validate "$file_path"; then
                echo "  ✅ Stapled ticket validation passed"
            else
                echo "  ⚠️ Stapled ticket validation failed, but file is notarized"
            fi
            
            echo "  🔍 Final Gatekeeper assessment..."
            # Final Gatekeeper check
            if spctl --assess --type install "$file_path" 2>/dev/null; then
                echo "  ✅ Final Gatekeeper assessment: APPROVED"
            else
                echo "  ⚠️ Final Gatekeeper assessment failed"
            fi
            
        else
            echo "  ⚠️ Warning: Failed to staple $file_name, but notarization succeeded"
            echo "  📋 File is notarized but ticket not stapled"
        fi
        
        return 0
    else
        echo "  ❌ Notarization failed for $file_name"
        
        # Try to get detailed error information
        echo "  🔍 Attempting to get detailed error log..."
        local submission_id=$(echo "$submit_output" | grep -o 'id: [a-f0-9-]*' | cut -d' ' -f2 | head -1)
        
        if [ -n "$submission_id" ]; then
            echo "  📋 Submission ID: $submission_id"
            echo "  📋 Getting detailed log..."
            xcrun notarytool log "$submission_id" \
                --apple-id "$APPLE_ID" \
                --password "$APPLE_ID_PASSWORD" \
                --team-id "$APPLE_TEAM_ID" 2>/dev/null | head -50 || echo "  Could not retrieve detailed log"
        fi
        
        return 1
    fi
}

# Check for packages to notarize
echo ""
echo "🔍 Looking for packages to notarize..."

if [ ! -d "artifacts" ]; then
    echo "❌ Artifacts directory not found"
    exit 1
fi

# Count packages
total_files=0
echo "📦 Found packages:"
for file in artifacts/*.pkg artifacts/*.dmg; do
    if [ -f "$file" ]; then
        total_files=$((total_files + 1))
        size=$(du -h "$file" | cut -f1)
        echo "  📦 $(basename "$file") ($size)"
    fi
done

if [ $total_files -eq 0 ]; then
    echo "❌ No PKG or DMG files found in artifacts directory"
    echo "📁 Artifacts directory contents:"
    ls -la artifacts/
    exit 1
fi

echo ""
echo "📤 Starting notarization process for $total_files files..."
echo ""

# Track notarization results
declare -a notarized_files=()
declare -a failed_files=()

# Notarize all packages
for file in artifacts/*.pkg artifacts/*.dmg; do
    if [ -f "$file" ]; then
        if notarize_file_native "$file"; then
            notarized_files+=("$(basename "$file")")
        else
            failed_files+=("$(basename "$file")")
        fi
        echo ""  # Add spacing between files
    fi
done

# Summary
echo "📋 NOTARIZATION SUMMARY"
echo "======================"
echo "Total files: $total_files"
echo "Successfully notarized: ${#notarized_files[@]}"
echo "Failed: ${#failed_files[@]}"
echo ""

if [ ${#notarized_files[@]} -gt 0 ]; then
    echo "✅ Successfully notarized files:"
    for file in "${notarized_files[@]}"; do
        echo "  ✅ $file"
    done
    echo ""
fi

if [ ${#failed_files[@]} -gt 0 ]; then
    echo "❌ Failed notarization:"
    for file in "${failed_files[@]}"; do
        echo "  ❌ $file"
    done
    echo ""
    echo "⚠️ Some files failed notarization - these will still be uploaded but may show security warnings"
fi

# Set environment variable for build summary
{
    echo "NOTARIZED_COUNT=${#notarized_files[@]}"
    echo "TOTAL_PACKAGES=$total_files"
} >> "${GITHUB_ENV:-/dev/null}"

# Determine overall result
if [ ${#notarized_files[@]} -eq $total_files ]; then
    echo "🎉 ALL PACKAGES SUCCESSFULLY NOTARIZED!"
    exit 0
elif [ ${#notarized_files[@]} -gt 0 ]; then
    echo "⚠️ PARTIAL SUCCESS - Some packages notarized"
    # Don't fail for partial success
    exit 0
else
    echo "❌ NO PACKAGES WERE NOTARIZED - Check Apple ID credentials and certificates"
    
    # Check build type to decide whether to fail
    BUILD_TYPE=${BUILD_TYPE:-"dev"}
    if [ "$BUILD_TYPE" = "production" ]; then
        echo "❌ Failing production build due to notarization failure"
        exit 1
    else
        echo "⚠️ Continuing with dev build despite notarization failure"
        exit 0
    fi
fi
