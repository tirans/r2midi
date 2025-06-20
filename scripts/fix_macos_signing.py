#!/usr/bin/env python3
"""
Comprehensive fix for macOS code signing issues with PyQt6 frameworks.

This script addresses the extended attributes issue that prevents PyQt6 frameworks
from being signed properly during the briefcase build process.
"""

import subprocess
import sys
import os
from pathlib import Path

def run_command(cmd, cwd=None):
    """Run a command and return the result."""
    print(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True)
        print(f"✅ Success: {result.returncode}")
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed: {e.returncode}")
        print(f"stdout: {e.stdout}")
        print(f"stderr: {e.stderr}")
        return e

def clean_extended_attributes(path):
    """Clean extended attributes from files and directories."""
    print(f"🧹 Cleaning extended attributes from: {path}")
    
    if not Path(path).exists():
        print(f"⚠️ Path does not exist: {path}")
        return False
    
    # Use xattr to remove all extended attributes recursively
    result = run_command(["xattr", "-cr", str(path)])
    
    if isinstance(result, subprocess.CalledProcessError):
        print(f"❌ Failed to clean extended attributes from: {path}")
        return False
    else:
        print(f"✅ Cleaned extended attributes from: {path}")
        return True

def fix_pyqt6_signing_issues():
    """Fix PyQt6 signing issues by cleaning extended attributes."""
    print("🔧 Fixing PyQt6 signing issues...")
    
    # Define paths to clean
    server_pyqt6_path = Path("build/server/macos/app/R2MIDI Server.app/Contents/Resources/app_packages/PyQt6")
    client_pyqt6_path = Path("build/r2midi-client/macos/app/R2MIDI Client.app/Contents/Resources/app_packages/PyQt6")
    
    paths_to_clean = []
    
    if server_pyqt6_path.exists():
        paths_to_clean.append(server_pyqt6_path)
        print(f"📦 Found server PyQt6 path: {server_pyqt6_path}")
    
    if client_pyqt6_path.exists():
        paths_to_clean.append(client_pyqt6_path)
        print(f"📦 Found client PyQt6 path: {client_pyqt6_path}")
    
    if not paths_to_clean:
        print("⚠️ No PyQt6 paths found to clean")
        return False
    
    # Clean extended attributes from all PyQt6 paths
    success = True
    for path in paths_to_clean:
        if not clean_extended_attributes(path):
            success = False
    
    return success

def test_framework_signing():
    """Test signing a PyQt6 framework to verify the fix."""
    print("🧪 Testing PyQt6 framework signing...")
    
    # Find a PyQt6 framework to test
    server_app_path = Path("build/server/macos/app/R2MIDI Server.app")
    if not server_app_path.exists():
        print("⚠️ Server app not found, cannot test framework signing")
        return False
    
    # Find QtCore framework (should always be present)
    qtcore_framework = server_app_path / "Contents/Resources/app_packages/PyQt6/Qt6/lib/QtCore.framework"
    
    if not qtcore_framework.exists():
        print("⚠️ QtCore framework not found, cannot test signing")
        return False
    
    # Test signing the framework
    entitlements_file = Path("build/server/macos/app/Entitlements.plist")
    
    print(f"🔍 Testing signing of: {qtcore_framework}")
    result = run_command([
        "codesign",
        "--sign", "-",
        "--force",
        "--entitlements", str(entitlements_file),
        str(qtcore_framework)
    ])
    
    if isinstance(result, subprocess.CalledProcessError):
        print("❌ Framework signing test failed")
        return False
    else:
        print("✅ Framework signing test successful")
        return True

def main():
    """Main function to fix macOS signing issues."""
    print("🔧 Comprehensive macOS signing fix...")
    
    # Check if we're on macOS
    if sys.platform != "darwin":
        print("⚠️ This script is designed for macOS builds")
        return 0
    
    # Fix PyQt6 signing issues
    if fix_pyqt6_signing_issues():
        print("✅ PyQt6 extended attributes cleaned successfully")
    else:
        print("❌ Failed to clean PyQt6 extended attributes")
        return 1
    
    # Test framework signing
    if test_framework_signing():
        print("✅ Framework signing test passed")
        print("")
        print("🎯 Solution Summary:")
        print("   1. Extended attributes have been cleaned from PyQt6 frameworks")
        print("   2. Framework signing test passed")
        print("   3. You can now run: briefcase build macos app -a server")
        print("")
        print("💡 If the build still fails, run this script again after the failure")
        print("   to clean up any newly created extended attributes.")
        return 0
    else:
        print("❌ Framework signing test failed")
        print("   The extended attributes issue may persist or there may be other issues.")
        return 1

if __name__ == "__main__":
    sys.exit(main())