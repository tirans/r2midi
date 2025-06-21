#!/bin/bash
# clean-environment.sh - Complete environment cleanup script
set -euo pipefail

DEEP_CLEAN=false
KEEP_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deep) DEEP_CLEAN=true; shift ;;
        --keep-cache) KEEP_CACHE=true; shift ;;
        *) echo "Usage: $0 [--deep] [--keep-cache]"; exit 1 ;;
    esac
done

echo "🧹 Starting comprehensive environment cleanup..."

safe_remove() {
    local path="$1"
    local description="$2"
    if [ -e "$path" ]; then
        echo "  🗑️ Removing $description: $path"
        rm -rf "$path" 2>/dev/null || echo "    ⚠️ Failed to remove $path"
    fi
}

# Robust cleanup function for build directories
robust_cleanup() {
    local dir="$1"
    local description="$2"
    echo "  🧹 Robust cleanup of $description: $dir"
    
    # Try multiple cleanup methods
    if [ -d "$dir" ]; then
        # First try normal removal
        rm -rf "$dir" 2>/dev/null || true
        
        # If directory still exists, try with sudo
        if [ -d "$dir" ]; then
            echo "    Trying with elevated permissions..."
            sudo rm -rf "$dir" 2>/dev/null || true
        fi
        
        # If still exists, try to remove contents first
        if [ -d "$dir" ]; then
            echo "    Trying selective cleanup..."
            find "$dir" -type f -delete 2>/dev/null || true
            find "$dir" -type d -empty -delete 2>/dev/null || true
            rm -rf "$dir" 2>/dev/null || true
        fi
        
        # Final check
        if [ -d "$dir" ]; then
            echo "    ⚠️ Failed to completely remove $dir. Manual cleanup may be required."
        else
            echo "    ✅ $description cleaned successfully"
        fi
    fi
}

# Clean build artifacts
safe_remove "build" "main build directory"
safe_remove "dist" "main dist directory"
safe_remove "build_native" "native build directory"

# Use robust cleanup for problematic py2app build directories
robust_cleanup "build_client" "client build directory"
robust_cleanup "build_server" "server build directory"

safe_remove "artifacts" "artifacts directory"

# Clean virtual environments
safe_remove "venv" "main virtual environment"
safe_remove "venv_client" "client virtual environment"
safe_remove "venv_server" "server virtual environment"
safe_remove ".venv" "hidden virtual environment"

if [ "$DEEP_CLEAN" = "true" ]; then
    for venv_name in venv-* .venv-* env-* .env-*; do
        safe_remove "$venv_name" "virtual environment ($venv_name)"
    done
fi

# Clean Python cache
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true

# Clean py2app cache
safe_remove "~/.py2app" "py2app cache"
safe_remove "$HOME/.py2app" "py2app cache"

# Clean setuptools/wheel cache and build artifacts
find . -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.egg" -delete 2>/dev/null || true

# Clean security artifacts
safe_remove "*.p12" "certificate files"
safe_remove "entitlements.plist" "entitlements file"

# Clean package caches if requested
if [ "$KEEP_CACHE" = "false" ]; then
    python3 -m pip cache purge 2>/dev/null || true
    command -v brew >/dev/null && brew cleanup 2>/dev/null || true
fi

echo "✅ Environment cleanup completed!"
