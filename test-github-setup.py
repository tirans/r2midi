#!/usr/bin/env python3
"""
Test script to validate GitHub Actions setup for R2MIDI build system
"""

import os
import sys
from pathlib import Path

def test_github_environment():
    """Test if GitHub Actions environment is detected correctly"""
    print("🔍 Testing GitHub Actions Environment Detection")
    print("=" * 50)
    
    # Required environment variables for GitHub Actions
    required_vars = [
        "APPLE_DEVELOPER_ID_APPLICATION_CERT",
        "APPLE_DEVELOPER_ID_INSTALLER_CERT", 
        "APPLE_CERT_PASSWORD",
        "APPLE_ID",
        "APPLE_ID_PASSWORD",
        "APPLE_TEAM_ID"
    ]
    
    # Optional App Store Connect API variables
    optional_vars = [
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_API_KEY"
    ]
    
    # Check required variables
    missing_required = []
    for var in required_vars:
        if os.environ.get(var):
            print(f"✅ {var} is set")
        else:
            print(f"❌ {var} is missing")
            missing_required.append(var)
    
    # Check optional variables
    print("\nOptional App Store Connect API variables:")
    asc_available = True
    for var in optional_vars:
        if os.environ.get(var):
            print(f"✅ {var} is set")
        else:
            print(f"ℹ️  {var} is not set")
            asc_available = False
    
    print("\n📋 Summary:")
    if missing_required:
        print(f"❌ Missing required variables: {', '.join(missing_required)}")
        print("💡 Set these environment variables to enable GitHub Actions builds")
        return False
    else:
        print("✅ All required variables are set")
        
        if asc_available:
            print("✅ App Store Connect API credentials are available (preferred for notarization)")
        else:
            print("ℹ️  App Store Connect API not configured, will use Apple ID authentication")
        
        print("🎉 GitHub Actions environment is ready!")
        return True

def test_build_system():
    """Test if the build system files are present"""
    print("\n🔍 Testing Build System Files")
    print("=" * 50)
    
    required_files = [
        "build-pkg.py",
        "build-all-local.sh", 
        ".github/workflows/build-macos.yml"
    ]
    
    missing_files = []
    for file_path in required_files:
        if Path(file_path).exists():
            print(f"✅ {file_path} exists")
        else:
            print(f"❌ {file_path} is missing")
            missing_files.append(file_path)
    
    if missing_files:
        print(f"❌ Missing files: {', '.join(missing_files)}")
        return False
    else:
        print("✅ All build system files are present")
        return True

if __name__ == "__main__":
    print("🚀 R2MIDI GitHub Actions Compatibility Test")
    print("=" * 50)
    
    env_ok = test_github_environment()
    files_ok = test_build_system()
    
    print("\n" + "=" * 50)
    if env_ok and files_ok:
        print("🎉 SUCCESS: GitHub Actions setup is complete and ready!")
        sys.exit(0)
    else:
        print("❌ FAILED: GitHub Actions setup needs attention")
        sys.exit(1)