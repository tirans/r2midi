#!/bin/bash
set -euo pipefail
# Extract version information and set GitHub Actions outputs
# Usage: extract-version.sh [input_version]
INPUT_VERSION="${1:-}"
echo "📋 Extracting version information..."
# Function to extract version from server/version.py
get_version_from_file() {
    if [ -f "server/version.py" ]; then
        grep -o '__version__ = "[^"]*"' server/version.py | cut -d'"' -f2
    else
        echo ""
    fi
}
# Determine the version to use
if [ -n "$INPUT_VERSION" ]; then
    VERSION="$INPUT_VERSION"
    echo "Using provided version: $VERSION"
else
    VERSION=$(get_version_from_file)
    if [ -z "$VERSION" ]; then
        echo "❌ Error: Could not extract version from server/version.py"
        exit 1
    fi
    echo "Extracted version from server/version.py: $VERSION"
fi
# Validate version format (basic semver check)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$ ]]; then
    echo "⚠️ Warning: Version '$VERSION' doesn't follow semantic versioning format"
fi
# Set environment variables
export APP_VERSION="$VERSION"
echo "APP_VERSION=$VERSION" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
# Set GitHub Actions outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "version=$VERSION" >> "$GITHUB_OUTPUT"
    echo "app_version=$VERSION" >> "$GITHUB_OUTPUT"

    # Also set individual version components
    if [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "major=${BASH_REMATCH[1]}" >> "$GITHUB_OUTPUT"
        echo "minor=${BASH_REMATCH[2]}" >> "$GITHUB_OUTPUT"
        echo "patch=${BASH_REMATCH[3]}" >> "$GITHUB_OUTPUT"
    fi
fi
# Generate version info for other scripts
cat > version_info.txt << EOF
# R2MIDI Version Information
VERSION=$VERSION
MAJOR=${BASH_REMATCH[1]:-0}
MINOR=${BASH_REMATCH[2]:-0}
PATCH=${BASH_REMATCH[3]:-0}
EXTRACTED_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
SOURCE_FILE=server/version.py
EOF
# Also create version info as JSON for other tools
cat > version_info.json << EOF
{
  "version": "$VERSION",
  "major": ${BASH_REMATCH[1]:-0},
  "minor": ${BASH_REMATCH[2]:-0},
  "patch": ${BASH_REMATCH[3]:-0},
  "extractedDate": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "sourceFile": "server/version.py"
}
EOF
# Update GitHub Actions step summary if available
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "### 📋 Version Information" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "**Version**: \`$VERSION\`" >> "$GITHUB_STEP_SUMMARY"
    echo "**Source**: server/version.py" >> "$GITHUB_STEP_SUMMARY"

    if [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "**Components**: Major: ${BASH_REMATCH[1]}, Minor: ${BASH_REMATCH[2]}, Patch: ${BASH_REMATCH[3]}" >> "$GITHUB_STEP_SUMMARY"
    fi

    echo "**Extracted**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
fi
echo "✅ Version information extracted and set:"
echo "   Version: $VERSION"
echo "   Environment variable: APP_VERSION=$VERSION"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "   GitHub outputs: version, app_version, major, minor, patch"
fi
echo "   Info files: version_info.txt, version_info.json"