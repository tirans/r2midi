#!/bin/bash
set -euo pipefail

# Load Apple credentials from GitHub secrets or local config
# This script provides seamless switching between GitHub runners and self-hosted runners
# Usage: source load-apple-credentials.sh

echo "🔑 Loading Apple credentials..."

# Function to extract value from JSON using grep/sed (fallback when jq is not available)
extract_json_value() {
    local json_file="$1"
    local key_path="$2"
    
    # Convert dot notation to grep pattern (e.g., "apple_developer.apple_id" -> "apple_id")
    local key=$(echo "$key_path" | sed 's/.*\.//')
    
    # Extract the value using grep and sed
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$json_file" | sed "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Check if we have local config file (self-hosted runner mode)
if [ -f "apple_credentials/config/app_config.json" ]; then
    echo "📱 Local config file found - checking for credentials..."
    
    # Try to load credentials from local config
    if command -v jq >/dev/null 2>&1; then
        # Use jq if available (preferred method)
        LOCAL_APPLE_ID=$(jq -r '.apple_developer.apple_id' apple_credentials/config/app_config.json 2>/dev/null || echo "")
        LOCAL_APPLE_ID_PASSWORD=$(jq -r '.apple_developer.app_specific_password' apple_credentials/config/app_config.json 2>/dev/null || echo "")
        LOCAL_TEAM_ID=$(jq -r '.apple_developer.team_id' apple_credentials/config/app_config.json 2>/dev/null || echo "")
    else
        # Fallback: use grep/sed when jq is not available
        echo "📝 jq not found, using fallback method to parse JSON..."
        LOCAL_APPLE_ID=$(extract_json_value "apple_credentials/config/app_config.json" "apple_developer.apple_id" 2>/dev/null || echo "")
        LOCAL_APPLE_ID_PASSWORD=$(extract_json_value "apple_credentials/config/app_config.json" "apple_developer.app_specific_password" 2>/dev/null || echo "")
        LOCAL_TEAM_ID=$(extract_json_value "apple_credentials/config/app_config.json" "apple_developer.team_id" 2>/dev/null || echo "")
    fi
    
    # Check if we got valid local credentials
    if [ -n "$LOCAL_APPLE_ID" ] && [ "$LOCAL_APPLE_ID" != "null" ] && \
       [ -n "$LOCAL_APPLE_ID_PASSWORD" ] && [ "$LOCAL_APPLE_ID_PASSWORD" != "null" ] && \
       [ -n "$LOCAL_TEAM_ID" ] && [ "$LOCAL_TEAM_ID" != "null" ]; then
        
        echo "✅ Using local Apple credentials from app_config.json"
        echo "   Apple ID: $LOCAL_APPLE_ID"
        echo "   Team ID: $LOCAL_TEAM_ID"
        echo "   App-specific password: [REDACTED]"
        
        # Export final credentials
        export APPLE_ID_FINAL="$LOCAL_APPLE_ID"
        export APPLE_ID_PASSWORD_FINAL="$LOCAL_APPLE_ID_PASSWORD"
        export APPLE_TEAM_ID_FINAL="$LOCAL_TEAM_ID"
        
        echo "🎯 Self-hosted runner mode: Using local credentials"
        return 0
    else
        echo "⚠️ Local config file exists but credentials are incomplete or invalid"
        echo "   Apple ID: ${LOCAL_APPLE_ID:-'missing'}"
        echo "   Team ID: ${LOCAL_TEAM_ID:-'missing'}"
        echo "   App-specific password: ${LOCAL_APPLE_ID_PASSWORD:+'present'}"
    fi
fi

# Fallback to GitHub secrets (GitHub runner mode)
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ID_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "✅ Using GitHub secrets for Apple credentials"
    echo "   Apple ID: $APPLE_ID"
    echo "   Team ID: $APPLE_TEAM_ID"
    echo "   App-specific password: [REDACTED]"
    
    # Export final credentials
    export APPLE_ID_FINAL="$APPLE_ID"
    export APPLE_ID_PASSWORD_FINAL="$APPLE_ID_PASSWORD"
    export APPLE_TEAM_ID_FINAL="$APPLE_TEAM_ID"
    
    echo "🎯 GitHub runner mode: Using secrets"
    return 0
fi

# No valid credentials found
echo "❌ Error: No valid Apple credentials found"
echo ""
echo "For self-hosted runners:"
echo "  - Ensure apple_credentials/config/app_config.json exists"
echo "  - Ensure it contains valid apple_developer.apple_id, apple_developer.app_specific_password, and apple_developer.team_id"
echo ""
echo "For GitHub runners:"
echo "  - Ensure APPLE_ID, APPLE_ID_PASSWORD, and APPLE_TEAM_ID secrets are configured"
echo ""
exit 1