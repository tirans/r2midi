#!/usr/bin/env python3
"""
Dynamic entitlements selection script for macOS builds.

This script determines which entitlements file to use based on the availability
of proper code signing certificates. It helps resolve the issue where briefcase
falls back to ad-hoc signing but tries to use entitlements that require proper
certificates.
"""

import subprocess
import sys
import os
import shutil
from pathlib import Path

def check_signing_identity_available():
    """Check if a valid Developer ID Application certificate is available."""
    try:
        # Check for Developer ID Application certificates in the keychain
        result = subprocess.run([
            "security", "find-identity", "-v", "-p", "codesigning"
        ], capture_output=True, text=True, check=True)
        
        # Look for Developer ID Application certificates
        if "Developer ID Application" in result.stdout:
            print("✅ Developer ID Application certificate found")
            return True
        else:
            print("⚠️ No Developer ID Application certificate found")
            return False
            
    except subprocess.CalledProcessError as e:
        print(f"❌ Error checking signing identities: {e}")
        return False

def select_entitlements_file():
    """Select the appropriate entitlements file based on certificate availability."""
    project_root = Path(__file__).parent.parent
    
    # Define entitlements files
    full_entitlements = project_root / "entitlements.plist"
    adhoc_entitlements = project_root / "entitlements_adhoc.plist"
    
    # Check if files exist
    if not full_entitlements.exists():
        print(f"❌ Full entitlements file not found: {full_entitlements}")
        return None
        
    if not adhoc_entitlements.exists():
        print(f"❌ Ad-hoc entitlements file not found: {adhoc_entitlements}")
        return None
    
    # Check if proper signing certificates are available
    if check_signing_identity_available():
        print(f"🔐 Using full entitlements: {full_entitlements}")
        return str(full_entitlements)
    else:
        print(f"🔓 Using ad-hoc compatible entitlements: {adhoc_entitlements}")
        return str(adhoc_entitlements)

def update_pyproject_entitlements(entitlements_file):
    """Update pyproject.toml to use the selected entitlements file."""
    project_root = Path(__file__).parent.parent
    pyproject_file = project_root / "pyproject.toml"
    
    if not pyproject_file.exists():
        print(f"❌ pyproject.toml not found: {pyproject_file}")
        return False
    
    # Read the current content
    with open(pyproject_file, 'r') as f:
        content = f.read()
    
    # Get the relative path for the entitlements file
    entitlements_path = Path(entitlements_file)
    relative_path = entitlements_path.name
    
    # Replace entitlements_file references
    import re
    
    # Pattern to match entitlements_file lines in macOS sections
    pattern = r'(entitlements_file\s*=\s*")[^"]*(")'
    replacement = f'\\1{relative_path}\\2'
    
    new_content = re.sub(pattern, replacement, content)
    
    if new_content != content:
        # Write the updated content
        with open(pyproject_file, 'w') as f:
            f.write(new_content)
        print(f"✅ Updated pyproject.toml to use: {relative_path}")
        return True
    else:
        print("ℹ️ No changes needed in pyproject.toml")
        return True

def main():
    """Main function to select and configure entitlements."""
    print("🔍 Selecting appropriate entitlements file for macOS build...")
    
    # Check if we're on macOS
    if sys.platform != "darwin":
        print("⚠️ This script is designed for macOS builds")
        return 0
    
    # Select the appropriate entitlements file
    selected_entitlements = select_entitlements_file()
    
    if not selected_entitlements:
        print("❌ Failed to select entitlements file")
        return 1
    
    # Update pyproject.toml with the selected entitlements
    if update_pyproject_entitlements(selected_entitlements):
        print("✅ Entitlements configuration updated successfully")
        return 0
    else:
        print("❌ Failed to update entitlements configuration")
        return 1

if __name__ == "__main__":
    sys.exit(main())