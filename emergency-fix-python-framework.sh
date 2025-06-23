#!/bin/bash
set -euo pipefail

# emergency-fix-python-framework.sh - Quick fix for Python.framework issues

echo "🚨 Emergency Python.framework Fix"
echo "================================"
echo ""
echo "This script removes problematic files from Python.framework"
echo "that commonly cause code signing failures."
echo ""

# Function to clean Python.framework
clean_python_framework() {
    local framework_path="$1"
    
    if [ ! -d "$framework_path" ]; then
        echo "❌ Framework not found: $framework_path"
        return 1
    fi
    
    echo "Cleaning: $framework_path"
    
    # Remove all .pyc files
    echo "  Removing .pyc files..."
    find "$framework_path" -name "*.pyc" -delete 2>/dev/null || true
    find "$framework_path" -name "*.pyo" -delete 2>/dev/null || true
    
    # Remove all __pycache__ directories
    echo "  Removing __pycache__ directories..."
    find "$framework_path" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove .idea directories (from your logs)
    echo "  Removing .idea directories..."
    find "$framework_path" -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove .pytest_cache
    echo "  Removing .pytest_cache..."
    find "$framework_path" -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove .git directories
    echo "  Removing .git directories..."
    find "$framework_path" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove all .DS_Store files
    echo "  Removing .DS_Store files..."
    find "$framework_path" -name ".DS_Store" -delete 2>/dev/null || true
    
    # Remove all ._ files
    echo "  Removing resource fork files..."
    find "$framework_path" -name "._*" -delete 2>/dev/null || true
    
    # Strip all extended attributes using -rc (most effective)
    echo "  Stripping extended attributes..."
    xattr -rc "$framework_path" 2>/dev/null || true
    
    # Also try -cr in case of version differences
    xattr -cr "$framework_path" 2>/dev/null || true
    
    # Additional aggressive xattr removal per file
    find "$framework_path" -type f -exec xattr -c {} \; 2>/dev/null || true
    find "$framework_path" -type d -exec xattr -c {} \; 2>/dev/null || true
    
    echo "✅ Cleaned: $(basename "$framework_path")"
}

# Clean client Python.framework
if [ -d "build_client/dist/R2MIDI Client.app/Contents/Frameworks/Python.framework" ]; then
    echo ""
    echo "Found Client Python.framework"
    clean_python_framework "build_client/dist/R2MIDI Client.app/Contents/Frameworks/Python.framework"
fi

# Clean server Python.framework
if [ -d "build_server/dist/R2MIDI Server.app/Contents/Frameworks/Python.framework" ]; then
    echo ""
    echo "Found Server Python.framework"
    clean_python_framework "build_server/dist/R2MIDI Server.app/Contents/Frameworks/Python.framework"
fi

# Also clean the embedded server directory that appeared in the logs
if [ -d "build_server/dist/R2MIDI Server.app/Contents/Resources/lib/python3.12/server" ]; then
    echo ""
    echo "Found embedded server directory"
    echo "Cleaning embedded files..."
    
    # Remove midi-presets/.idea directory
    rm -rf "build_server/dist/R2MIDI Server.app/Contents/Resources/lib/python3.12/server/midi-presets/.idea" 2>/dev/null || true
    
    # Remove midi-presets/.pytest_cache
    rm -rf "build_server/dist/R2MIDI Server.app/Contents/Resources/lib/python3.12/server/midi-presets/.pytest_cache" 2>/dev/null || true
    
    # Remove .gitignore files
    find "build_server/dist/R2MIDI Server.app/Contents/Resources/lib/python3.12/server" -name ".gitignore" -delete 2>/dev/null || true
    
    echo "✅ Cleaned embedded server files"
fi

echo ""
echo "🧹 Emergency cleanup complete!"
echo ""
echo "Now try signing again with:"
echo "  ./.github/scripts/sign-and-notarize-macos.sh --version 0.1.207"
echo ""
echo "If it still fails, run the full bulletproof clean:"
echo "  ./clean-for-signing.sh"
