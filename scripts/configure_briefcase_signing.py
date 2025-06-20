#!/usr/bin/env python3
"""
Configure briefcase signing identity for macOS builds.

This script ensures that briefcase can find and use the correct signing identity
by setting up the environment and configuration properly.
"""

import subprocess
import sys
import os
import re
from pathlib import Path

def get_available_signing_identities():
    """Get all available signing identities from the keychain."""
    try:
        # Check for signing identities in all keychains
        result = subprocess.run([
            "security", "find-identity", "-v", "-p", "codesigning"
        ], capture_output=True, text=True, check=True)
        
        identities = []
        for line in result.stdout.split('\n'):
            if 'Developer ID Application' in line:
                # Extract the identity name from the line
                # Format: "  1) ABC123... "Developer ID Application: Name (TEAM_ID)"
                match = re.search(r'"([^"]*)"', line)
                if match:
                    identities.append(match.group(1))
        
        return identities
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error getting signing identities: {e}")
        return []

def update_pyproject_signing_identity(identity):
    """Update pyproject.toml with the specific signing identity."""
    project_root = Path(__file__).parent.parent
    pyproject_file = project_root / "pyproject.toml"
    
    if not pyproject_file.exists():
        print(f"❌ pyproject.toml not found: {pyproject_file}")
        return False
    
    # Read the current content
    with open(pyproject_file, 'r') as f:
        content = f.read()
    
    # Replace codesign_identity with the specific identity
    # Pattern to match codesign_identity lines in macOS sections
    pattern = r'(codesign_identity\s*=\s*")[^"]*(")'
    replacement = f'\\1{identity}\\2'
    
    new_content = re.sub(pattern, replacement, content)
    
    if new_content != content:
        # Write the updated content
        with open(pyproject_file, 'w') as f:
            f.write(new_content)
        print(f"✅ Updated pyproject.toml with signing identity: {identity}")
        return True
    else:
        print("ℹ️ No changes needed in pyproject.toml")
        return True

def setup_briefcase_environment():
    """Set up environment variables for briefcase signing."""
    identities = get_available_signing_identities()
    
    if not identities:
        print("⚠️ No Developer ID Application certificates found")
        print("Briefcase will use ad-hoc signing")
        return False
    
    # Use the first available identity
    identity = identities[0]
    print(f"🔐 Found signing identity: {identity}")
    
    # Update pyproject.toml with the specific identity
    if update_pyproject_signing_identity(identity):
        print("✅ Briefcase signing configuration updated")
        return True
    else:
        print("❌ Failed to update briefcase signing configuration")
        return False

def main():
    """Main function to configure briefcase signing."""
    print("🔧 Configuring briefcase signing for macOS...")
    
    # Check if we're on macOS
    if sys.platform != "darwin":
        print("⚠️ This script is designed for macOS builds")
        return 0
    
    # Set up briefcase signing environment
    if setup_briefcase_environment():
        print("✅ Briefcase signing configuration completed successfully")
        return 0
    else:
        print("⚠️ Briefcase will use ad-hoc signing (may require compatible entitlements)")
        return 0

if __name__ == "__main__":
    sys.exit(main())