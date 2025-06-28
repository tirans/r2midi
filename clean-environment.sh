#!/bin/bash
# clean-environment.sh - Complete environment cleanup script
set -euo pipefail

DEEP_CLEAN=false
KEEP_CACHE=false
PRESERVE_PACKAGES=true  # New option to preserve signed .pkg files

while [[ $# -gt 0 ]]; do
    case $1 in
        --deep) DEEP_CLEAN=true; shift ;;
        --keep-cache) KEEP_CACHE=true; shift ;;
        --no-preserve-packages) PRESERVE_PACKAGES=false; shift ;;
        *) echo "Usage: $0 [--deep] [--keep-cache] [--no-preserve-packages]"; exit 1 ;;
    esac
done

echo "🧹 Starting comprehensive environment cleanup..."

# Count files before cleanup for progress tracking
echo "  📈 Scanning for cleanup targets..."
BEFORE_COUNT=$(find . -type f 2>/dev/null | wc -l | tr -d ' ')
echo "  📄 Files before cleanup: $BEFORE_COUNT"

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

# Clean build artifacts (but preserve signed packages)
echo "  🧹 Cleaning build artifacts while preserving signed packages..."
safe_remove "build" "main build directory"
safe_remove "dist" "main dist directory"
safe_remove "build_native" "native build directory"

# Use robust cleanup for problematic py2app build directories
robust_cleanup "build_client" "client build directory"
robust_cleanup "build_server" "server build directory"

# Preserve signed .pkg files but clean other artifacts
if [ -d "artifacts" ]; then
    if [ "$PRESERVE_PACKAGES" = "true" ]; then
        echo "  📦 Preserving signed .pkg files in artifacts directory..."
        # Create a temporary backup of .pkg files
        TEMP_PKG_DIR="/tmp/r2midi_pkg_backup_$"
        mkdir -p "$TEMP_PKG_DIR"
        
        # Move .pkg files to temporary location
        find artifacts -name "*.pkg" -exec mv {} "$TEMP_PKG_DIR/" \; 2>/dev/null || true
        
        # Count preserved packages
        PKG_COUNT=$(find "$TEMP_PKG_DIR" -name "*.pkg" 2>/dev/null | wc -l | tr -d ' ')
        
        # Remove artifacts directory
        safe_remove "artifacts" "artifacts directory"
        
        # Recreate artifacts directory and restore .pkg files
        mkdir -p "artifacts"
        if [ "$PKG_COUNT" -gt 0 ]; then
            mv "$TEMP_PKG_DIR"/*.pkg "artifacts/" 2>/dev/null || true
            echo "    ✅ Preserved $PKG_COUNT signed .pkg file(s)"
        else
            echo "    ℹ️  No .pkg files found to preserve"
        fi
        
        # Clean up temporary directory
        rm -rf "$TEMP_PKG_DIR"
    else
        echo "  🗑️ Complete artifacts cleanup (including .pkg files)..."
        safe_remove "artifacts" "artifacts directory"
    fi
else
    echo "  ℹ️  No artifacts directory found"
fi

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

# Clean Python cache and extended attributes more thoroughly
echo "  🧹 Deep Python cache cleanup..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true
find . -name "*.pyd" -delete 2>/dev/null || true

# Remove extended attributes from all files
echo "  🧹 Removing extended attributes..."
find . -exec xattr -c {} \; 2>/dev/null || true

# Clean macOS specific metadata
echo "  🧹 Removing macOS metadata..."
find . -name ".DS_Store" -delete 2>/dev/null || true
find . -name "._*" -delete 2>/dev/null || true
find . -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name ".AppleDouble" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name ".LSOverride" -delete 2>/dev/null || true

# Clean development artifacts
echo "  🧹 Removing development artifacts..."
find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name ".coverage" -delete 2>/dev/null || true
find . -name "*.coverage" -delete 2>/dev/null || true
find . -name ".tox" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name ".mypy_cache" -type d -exec rm -rf {} + 2>/dev/null || true

# Clean py2app cache
safe_remove "~/.py2app" "py2app cache"
safe_remove "$HOME/.py2app" "py2app cache"

# Clean setuptools/wheel cache and build artifacts
find . -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.egg" -delete 2>/dev/null || true

# Clean security artifacts
safe_remove "*.p12" "certificate files"
safe_remove "entitlements.plist" "entitlements file"

# Package cache cleanup
if [ "$KEEP_CACHE" = "false" ]; then
    echo "  🧹 Clearing package caches..."
    python3 -m pip cache purge 2>/dev/null || true
    command -v brew >/dev/null && brew cleanup 2>/dev/null || true
fi

# Count files after cleanup and show summary
echo "  📈 Calculating cleanup results..."
AFTER_COUNT=$(find . -type f 2>/dev/null | wc -l | tr -d ' ')
REMOVED_COUNT=$((BEFORE_COUNT - AFTER_COUNT))
if [ $REMOVED_COUNT -gt 0 ]; then
    # Estimate size saved (rough approximation)
    ESTIMATED_SIZE=$(echo "scale=1; $REMOVED_COUNT * 0.1" | bc 2>/dev/null || echo "${REMOVED_COUNT}")
    echo "Files removed: $REMOVED_COUNT (~${ESTIMATED_SIZE} MB estimated)"
else
    echo "Files removed: 0"
fi

echo "✅ Environment cleanup completed!"
