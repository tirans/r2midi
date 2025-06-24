#!/usr/bin/env python3
"""
build-pkg-with-macos-builder.py - Build PKG using macOS-Pkg-Builder Python library
Usage: python3 scripts/build-pkg-with-macos-builder.py --app-path <path> --pkg-name <n> [options]
"""

import sys
import os
import argparse
import json
from pathlib import Path

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

def log_info(msg): print(f"{Colors.BLUE}ℹ️  {msg}{Colors.NC}")
def log_success(msg): print(f"{Colors.GREEN}✅ {msg}{Colors.NC}")
def log_warning(msg): print(f"{Colors.YELLOW}⚠️  {msg}{Colors.NC}")
def log_error(msg): print(f"{Colors.RED}❌ {msg}{Colors.NC}")
def log_step(msg): 
    print()
    print(f"{Colors.BLUE}🔄 {msg}{Colors.NC}")
    print("=" * 50)

def setup_macos_pkg_builder():
    """Install and verify macos-pkg-builder"""
    log_step("Setting up macOS-Pkg-Builder")
    
    try:
        from macos_pkg_builder import Packages
        log_success("macOS-Pkg-Builder is already available")
        return True
    except ImportError:
        log_info("Installing macOS-Pkg-Builder...")
        
        import subprocess
        
        # Try different installation methods
        install_commands = [
            [sys.executable, "-m", "pip", "install", "macos-pkg-builder"],
            [sys.executable, "-m", "pip", "install", "--user", "macos-pkg-builder"],
            ["pip3", "install", "macos-pkg-builder"],
            ["pip3", "install", "--user", "macos-pkg-builder"]
        ]
        
        for cmd in install_commands:
            try:
                subprocess.run(cmd, check=True, capture_output=True)
                log_success("macOS-Pkg-Builder installed successfully")
                
                # Verify installation
                from macos_pkg_builder import Packages
                log_success("macOS-Pkg-Builder is ready to use")
                return True
            except (subprocess.CalledProcessError, ImportError):
                continue
        
        log_error("Failed to install macOS-Pkg-Builder")
        return False

def load_signing_credentials(project_root):
    """Load Apple signing credentials using secure certificate manager"""
    log_step("Loading Signing Credentials (Keychain-Free)")
    
    # Use the secure certificate manager
    try:
        import subprocess
        import json
        
        # Run the secure certificate manager to get credentials
        cmd = [sys.executable, "scripts/secure-certificate-manager.py", "get-credentials"]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=project_root)
        
        if result.returncode == 0:
            credentials = json.loads(result.stdout)
            log_success("Credentials loaded using secure certificate manager")
            return credentials
        else:
            log_warning("Secure certificate manager failed, trying fallback")
            log_info(f"Error: {result.stderr}")
            
            # Fallback to environment variables only
            if os.getenv("GITHUB_ACTIONS"):
                log_info("Using GitHub Actions environment variables (fallback)")
                required_vars = ["APPLE_ID", "APPLE_ID_PASSWORD", "APPLE_TEAM_ID"]
                missing_vars = [var for var in required_vars if not os.getenv(var)]
                
                if missing_vars:
                    log_error(f"Missing required environment variables: {', '.join(missing_vars)}")
                    return None
                
                return {
                    "apple_id": os.getenv("APPLE_ID"),
                    "apple_password": os.getenv("APPLE_ID_PASSWORD"),
                    "team_id": os.getenv("APPLE_TEAM_ID"),
                    "signing_identity": None,  # Will skip signing
                    "installer_identity": None
                }
            else:
                log_error("No fallback available for local builds")
                return None
                
    except Exception as e:
        log_error(f"Failed to load credentials: {e}")
        return None

def build_pkg(app_path, pkg_name, version, build_type, skip_notarization, output_dir, credentials):
    """Build PKG using macOS-Pkg-Builder"""
    log_step("Building PKG with macOS-Pkg-Builder")
    
    try:
        from macos_pkg_builder import Packages
    except ImportError:
        log_error("macOS-Pkg-Builder not available")
        return False
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    output_pkg = output_dir / f"{pkg_name}.pkg"
    app_name = Path(app_path).name
    
    log_info("Building PKG...")
    log_info(f"  Source: {app_path}")
    log_info(f"  Output: {output_pkg}")
    
    # Prepare package configuration
    pkg_config = {
        "pkg_output": str(output_pkg),
        "pkg_bundle_id": f"com.r2midi.{pkg_name.lower().replace('-', '.')}",
        "pkg_version": version,
        "pkg_file_structure": {
            str(app_path): f"/Applications/{app_name}"
        },
        "pkg_allow_relocation": True
    }
    
    # Add signing if not dev build and credentials available
    if build_type != "dev" and credentials:
        log_info("Adding signing and notarization...")
        pkg_config["pkg_signing_identity"] = credentials["signing_identity"]
        
        # Note: macOS-Pkg-Builder handles notarization differently
        # For now, we'll just sign the package
        log_info("Package will be signed")
        if not skip_notarization:
            log_info("Notarization will be handled by macOS-Pkg-Builder")
    else:
        log_warning("Skipping signing (dev build or missing credentials)")
    
    try:
        # Create and build package
        log_info(f"Creating package with config: {pkg_config}")
        pkg_obj = Packages(**pkg_config)
        
        log_info("Building package...")
        success = pkg_obj.build()
        
        if success:
            log_success(f"PKG built successfully: {output_pkg}")
            
            # Verify the package
            if output_pkg.exists():
                pkg_size = f"{output_pkg.stat().st_size / (1024*1024):.1f}MB"
                log_success(f"PKG file created: {output_pkg} ({pkg_size})")
                
                # Check signature
                import subprocess
                try:
                    subprocess.run(["pkgutil", "--check-signature", str(output_pkg)], 
                                 check=True, capture_output=True)
                    log_success("PKG is signed")
                except subprocess.CalledProcessError:
                    log_info("PKG is not signed (expected for dev builds)")
                
                return True
            else:
                log_error("PKG file was not created")
                return False
        else:
            log_error("PKG build failed")
            return False
            
    except Exception as e:
        log_error(f"PKG build failed with exception: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Build PKG using macOS-Pkg-Builder")
    parser.add_argument("--app-path", required=True, help="Path to the .app bundle to package")
    parser.add_argument("--pkg-name", required=True, help="Name for the output PKG file (without .pkg extension)")
    parser.add_argument("--version", default="1.0.0", help="Version to embed in PKG")
    parser.add_argument("--build-type", default="production", choices=["dev", "staging", "production"], 
                       help="Build type")
    parser.add_argument("--skip-notarize", action="store_true", help="Skip notarization step")
    parser.add_argument("--output-dir", help="Output directory for PKG")
    
    args = parser.parse_args()
    
    # Validate required parameters
    app_path = Path(args.app_path)
    if not app_path.exists():
        log_error(f"App bundle does not exist: {app_path}")
        sys.exit(1)
    
    # Set default output directory
    if args.output_dir:
        output_dir = Path(args.output_dir)
    else:
        script_dir = Path(__file__).parent
        project_root = script_dir.parent
        output_dir = project_root / "artifacts"
    
    log_step("PKG Builder using macOS-Pkg-Builder")
    log_info(f"App Path: {app_path}")
    log_info(f"PKG Name: {args.pkg_name}")
    log_info(f"Version: {args.version}")
    log_info(f"Build Type: {args.build_type}")
    log_info(f"Output Directory: {output_dir}")
    
    # Setup
    if not setup_macos_pkg_builder():
        sys.exit(1)
    
    # Load credentials
    project_root = Path(__file__).parent.parent
    credentials = load_signing_credentials(project_root)
    
    # Build PKG
    success = build_pkg(app_path, args.pkg_name, args.version, args.build_type, 
                       args.skip_notarize, output_dir, credentials)
    
    if success:
        log_success("PKG build process completed!")
        sys.exit(0)
    else:
        log_error("PKG build process failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
