#!/bin/bash
set -euo pipefail

# Notarize Packages with Apple notarytool
# Usage: notarize-native-packages.sh

echo "📤 Notarizing packages with Apple notarytool..."
echo "🚫 IMPORTANT: Not using Briefcase - using native Apple notarytool"
echo "This process may take 5-30 minutes depending on Apple's queue..."

# Verify required environment variables
if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
    echo "❌ Missing required Apple credentials. Run setup-github-secrets-certificates.sh first"
    exit 1
fi

# Function to notarize a file with proper error handling
notarize_file_native() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local file_type="${file_name##*.}"
    
    echo "📤 Submitting $file_name for notarization..."
    echo "  File type: $file_type"
    echo "  File size: $(du -h "$file_path" | cut -f1)"
    
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
        xcrun stapler staple "$file_path"
        
        if [ $? -eq 0 ]; then
            echo "  ✅ Successfully stapled notarization ticket to $file_name"
            
            echo "  🔍 Verifying stapled ticket..."
            xcrun stapler validate "$file_path"
            if [ $? -eq 0 ]; then
                echo "  ✅ Stapled ticket validation passed"
            else
                echo "  ⚠️ Stapled ticket validation failed, but file is notarized"
            fi
            
            echo "  🔍 Final Gatekeeper assessment..."
            # Final Gatekeeper check
            spctl --assess --type install "$file_path" && \
                echo "  ✅ Final Gatekeeper assessment: APPROVED" || \
                echo "  ⚠️ Final Gatekeeper assessment failed"
            
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
                --team-id "$APPLE_TEAM_ID" 2>/dev/null || echo "  Could not retrieve detailed log"
        fi
        
        return 1
    fi
}

# Track notarization results
declare -a notarized_files=()
declare -a failed_files=()
total_files=0

echo "🔍 Found packages to notarize:"
for file in artifacts/*.pkg artifacts/*.dmg; do
    if [ -f "$file" ]; then
        total_files=$((total_files + 1))
        size=$(du -h "$file" | cut -f1)
        echo "  📦 $(basename "$file") ($size)"
    fi
done

echo ""
echo "📤 Starting notarization process for $total_files files..."
echo ""

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
echo "NOTARIZED_COUNT=${#notarized_files[@]}" >> "$GITHUB_ENV"
echo "TOTAL_PACKAGES=$total_files" >> "$GITHUB_ENV"

if [ ${#notarized_files[@]} -eq $total_files ]; then
    echo "🎉 ALL PACKAGES SUCCESSFULLY NOTARIZED!"
elif [ ${#notarized_files[@]} -gt 0 ]; then
    echo "⚠️ PARTIAL SUCCESS - Some packages notarized"
else
    echo "❌ NO PACKAGES WERE NOTARIZED - Check Apple ID credentials and certificates"
fi

echo "✅ Notarization process complete"
