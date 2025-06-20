#!/usr/bin/env python3
"""
Final fix for briefcase macOS code signing issue.

This script addresses the root cause: briefcase falling back to ad-hoc signing
despite having proper certificates configured. The fix ensures briefcase can
find and use the correct signing identity.
"""

import subprocess
import sys
import os
import re
from pathlib import Path

def get_keychain_list():
    """Get the list of keychains in the search path."""
    try:
        result = subprocess.run([
            "security", "list-keychains", "-d", "user"
        ], capture_output=True, text=True, check=True)
        
        keychains = []
        for line in result.stdout.split('\n'):
            line = line.strip()
            if line and line.startswith('"') and line.endswith('"'):
                keychain = line[1:-1]  # Remove quotes
                keychains.append(keychain)
        
        return keychains
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error getting keychain list: {e}")
        return []

def find_signing_identity_in_keychain(keychain_path=None):
    """Find Developer ID Application identity in a specific keychain or all keychains."""
    try:
        cmd = ["security", "find-identity", "-v", "-p", "codesigning"]
        if keychain_path:
            cmd.append(keychain_path)
            
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        for line in result.stdout.split('\n'):
            if 'Developer ID Application' in line:
                # Extract the identity name from the line
                # Format: "  1) ABC123... "Developer ID Application: Name (TEAM_ID)"
                match = re.search(r'"([^"]*)"', line)
                if match:
                    identity = match.group(1)
                    print(f"✅ Found identity: {identity}")
                    if keychain_path:
                        print(f"   In keychain: {keychain_path}")
                    return identity
        
        return None
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error finding signing identity: {e}")
        return None

def ensure_keychain_in_search_path():
    """Ensure the temporary keychain is in the search path."""
    keychains = get_keychain_list()
    temp_keychain = "build.keychain"
    
    # Check if temp keychain is in the list
    temp_keychain_found = False
    for keychain in keychains:
        if temp_keychain in keychain:
            temp_keychain_found = True
            print(f"✅ Temporary keychain found in search path: {keychain}")
            break
    
    if not temp_keychain_found:
        print("⚠️ Temporary keychain not found in search path")
        print("Available keychains:")
        for keychain in keychains:
            print(f"  - {keychain}")
    
    return temp_keychain_found

def update_pyproject_with_simple_identity():
    """Update pyproject.toml to use a simpler identity format that briefcase can recognize."""
    project_root = Path(__file__).parent
    pyproject_file = project_root / "pyproject.toml"
    
    if not pyproject_file.exists():
        print(f"❌ pyproject.toml not found: {pyproject_file}")
        return False
    
    # Read the current content
    with open(pyproject_file, 'r') as f:
        content = f.read()
    
    # Try different identity formats that briefcase might recognize better
    identity_formats = [
        "Developer ID Application",  # Generic format
        "-",  # Ad-hoc signing with compatible entitlements
    ]
    
    # Check if we have proper certificates available
    signing_identity = find_signing_identity_in_keychain()
    
    if signing_identity:
        print(f"🔐 Using proper signing identity: {signing_identity}")
        # Use the full identity name
        selected_identity = signing_identity
        selected_entitlements = "entitlements.plist"
    else:
        print("⚠️ No proper signing identity found, using ad-hoc signing")
        selected_identity = "-"
        selected_entitlements = "entitlements_adhoc.plist"
    
    # Update both identity and entitlements
    # Replace codesign_identity
    pattern1 = r'(codesign_identity\s*=\s*")[^"]*(")'
    replacement1 = f'\\1{selected_identity}\\2'
    new_content = re.sub(pattern1, replacement1, content)
    
    # Replace entitlements_file
    pattern2 = r'(entitlements_file\s*=\s*")[^"]*(")'
    replacement2 = f'\\1{selected_entitlements}\\2'
    new_content = re.sub(pattern2, replacement2, new_content)
    
    if new_content != content:
        # Write the updated content
        with open(pyproject_file, 'w') as f:
            f.write(new_content)
        print(f"✅ Updated pyproject.toml:")
        print(f"   - codesign_identity: {selected_identity}")
        print(f"   - entitlements_file: {selected_entitlements}")
        return True
    else:
        print("ℹ️ No changes needed in pyproject.toml")
        return True

def main():
    """Main function to fix briefcase signing."""
    print("🔧 Applying final fix for briefcase macOS code signing...")
    
    # Check if we're on macOS
    if sys.platform != "darwin":
        print("⚠️ This script is designed for macOS builds")
        return 0
    
    # Check keychain setup
    print("🔍 Checking keychain configuration...")
    ensure_keychain_in_search_path()
    
    # Find available signing identities
    print("🔍 Checking for signing identities...")
    identity = find_signing_identity_in_keychain()
    
    # Update pyproject.toml with the appropriate configuration
    if update_pyproject_with_simple_identity():
        print("✅ Briefcase signing configuration fixed")
        
        if identity:
            print("🔐 Briefcase should now use proper code signing")
        else:
            print("🔓 Briefcase will use ad-hoc signing with compatible entitlements")
        
        return 0
    else:
        print("❌ Failed to fix briefcase signing configuration")
        return 1

if __name__ == "__main__":
    sys.exit(main())