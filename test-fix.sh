#!/bin/bash

# Quick test to verify the configure-build.sh fix
echo "🧪 Quick test of configure-build.sh fix..."

cd /Users/tirane/Desktop/r2midi

# Make script executable
chmod +x ./.github/scripts/configure-build.sh

# Create temp files for GitHub outputs
temp_output=$(mktemp)
temp_env=$(mktemp)

export GITHUB_OUTPUT="$temp_output"
export GITHUB_ENV="$temp_env"

echo "🔧 Running configure-build.sh..."
if ./.github/scripts/configure-build.sh "push" "" "" "self-hosted" "production"; then
    echo "✅ Script executed successfully!"
    echo ""
    echo "📤 GitHub Outputs:"
    cat "$temp_output"
    echo ""
    echo "🌍 GitHub Environment Variables:"
    cat "$temp_env"
else
    echo "❌ Script failed"
fi

# Cleanup
rm -f "$temp_output" "$temp_env"
unset GITHUB_OUTPUT GITHUB_ENV

echo ""
echo "🎯 The version should now be clean (just the number without extra text)"
