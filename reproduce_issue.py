#!/usr/bin/env python3
"""
Script to reproduce the macOS code signing issue.
This script simulates the briefcase build process that's failing.
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

def main():
    """Reproduce the macOS code signing issue."""
    print("🔍 Reproducing macOS code signing issue...")
    
    # Check if we're on macOS
    if sys.platform != "darwin":
        print("❌ This script must be run on macOS")
        return 1
    
    # Check if briefcase is available
    try:
        subprocess.run(["briefcase", "--version"], capture_output=True, check=True)
        print("✅ Briefcase is available")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ Briefcase is not available. Install with: pip install briefcase")
        return 1
    
    # Check if the server app build directory exists
    server_build_path = Path("build/server/macos/app")
    if server_build_path.exists():
        print(f"✅ Server build directory exists: {server_build_path}")
    else:
        print(f"⚠️ Server build directory does not exist: {server_build_path}")
        print("Running briefcase build to reproduce the issue...")
        
        # Try to build the server app - this should reproduce the error
        result = run_command(["briefcase", "build", "macos", "app", "-a", "server"])
        
        if isinstance(result, subprocess.CalledProcessError):
            print("🎯 Successfully reproduced the code signing error!")
            print("The error occurs during the briefcase build process.")
            return 1
        else:
            print("🤔 Build succeeded unexpectedly. The issue may have been resolved.")
            return 0
    
    # If build directory exists, try to manually reproduce the signing issue
    app_bundle = server_build_path / "R2MIDI Server.app"
    if app_bundle.exists():
        print(f"✅ App bundle exists: {app_bundle}")
        
        # Try ad-hoc signing with entitlements (this should fail)
        entitlements_file = Path("entitlements.plist")
        if entitlements_file.exists():
            print("🔍 Testing ad-hoc signing with entitlements (should fail)...")
            result = run_command([
                "codesign",
                str(app_bundle),
                "--sign", "-",
                "--force",
                "--entitlements", str(entitlements_file)
            ])
            
            if isinstance(result, subprocess.CalledProcessError):
                print("🎯 Successfully reproduced the code signing error!")
                print("Ad-hoc signing fails with the current entitlements.")
                return 1
        else:
            print("❌ entitlements.plist not found")
            return 1
    else:
        print(f"❌ App bundle not found: {app_bundle}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())