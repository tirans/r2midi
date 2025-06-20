#!/bin/bash

# Make this script executable first
chmod +x "$0" 2>/dev/null || true

# Make all GitHub Actions scripts executable
# Usage: make-scripts-executable.sh

echo "🔧 Making all GitHub Actions scripts executable..."

SCRIPTS_DIR=".github/scripts"

if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "❌ Error: Scripts directory not found: $SCRIPTS_DIR"
    exit 1
fi

# Find all shell scripts and make them executable
find "$SCRIPTS_DIR" -name "*.sh" -type f | while read script; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        echo "✅ Made executable: $(basename "$script")"
    fi
done

# Also make the test scripts in root executable
for test_script in "test-qt-fixes.sh" "test-server-build.sh" "verify-server-build-fixes.sh"; do
    if [ -f "$test_script" ]; then
        chmod +x "$test_script"
        echo "✅ Made executable: $test_script"
    fi
done

# Specifically ensure the new scripts are executable
NEW_SCRIPTS=(
    "configure-build.sh"
    "setup-python-environment.sh"
    "install-dependencies.sh"
    "setup-apple-certificates.sh"
    "build-server-app.sh"
    "build-server-app-isolated.sh"
    "build-client-app.sh"
    "sign-apps.sh"
    "create-pkg-installers.sh"
    "create-dmg-installers.sh"
    "notarize-packages.sh"
    "create-build-report.sh"
    "cleanup-build.sh"
    "debug-server-dependencies.sh"
    "make-scripts-executable.sh"
)

echo ""
echo "🔍 Verifying new scripts are executable:"

for script in "${NEW_SCRIPTS[@]}"; do
    script_path="$SCRIPTS_DIR/$script"
    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        echo "✅ $script - executable"
    elif [ -f "$script_path" ]; then
        chmod +x "$script_path"
        echo "🔧 $script - made executable"
    else
        echo "❌ $script - not found"
    fi
done

echo ""
echo "📋 All executable scripts in $SCRIPTS_DIR:"
find "$SCRIPTS_DIR" -name "*.sh" -type f -executable | sort | while read script; do
    echo "  ✅ $(basename "$script")"
done

echo ""
echo "✅ All scripts are now executable!"
echo "🎯 Ready for GitHub Actions workflow execution"
