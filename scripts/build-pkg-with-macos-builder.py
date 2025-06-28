#!/usr/bin/env python3
"""
build-pkg-with-macos-builder.py - Build PKG using macOS-Pkg-Builder Python library
Usage: python3 scripts/build-pkg-with-macos-builder.py --app-path <path> --pkg-name <n> [options]
"""

import sys
import os
import argparse
import json
import time
import atexit
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
    """Load Apple signing credentials - simplified for macos-pkg-builder"""
    log_step("Loading Signing Credentials")
    
    # Check if we're in GitHub Actions
    if os.getenv("GITHUB_ACTIONS"):
        log_info("GitHub Actions environment detected")
        
        # Check for required environment variables
        required_vars = ["APPLE_ID", "APPLE_ID_PASSWORD", "APPLE_TEAM_ID"]
        missing_vars = [var for var in required_vars if not os.getenv(var)]
        
        if missing_vars:
            log_warning(f"Missing environment variables: {', '.join(missing_vars)}")
            log_info("Signing and notarization will be skipped")
            return None
        
        # Check for certificate environment variables
        cert_vars = ["APPLE_DEVELOPER_ID_APPLICATION_CERT", "APPLE_DEVELOPER_ID_INSTALLER_CERT", "APPLE_CERT_PASSWORD"]
        missing_cert_vars = [var for var in cert_vars if not os.getenv(var)]
        
        if missing_cert_vars:
            log_warning(f"Missing certificate variables: {', '.join(missing_cert_vars)}")
            log_info("Signing will be skipped, but notarization may still work")
            
            return {
                "apple_id": os.getenv("APPLE_ID"),
                "apple_password": os.getenv("APPLE_ID_PASSWORD"),
                "team_id": os.getenv("APPLE_TEAM_ID"),
                "signing_identity": None,
                "installer_identity": None
            }
        
        # All credentials available
        log_success("All GitHub Actions credentials available")
        return {
            "apple_id": os.getenv("APPLE_ID"),
            "apple_password": os.getenv("APPLE_ID_PASSWORD"),
            "team_id": os.getenv("APPLE_TEAM_ID"),
            "signing_identity": "from_github_secrets",  # Will be resolved later
            "installer_identity": "from_github_secrets"
        }
    
    else:
        log_info("Local environment detected")
        
        # For local builds, try to find certificates in keychain
        try:
            import subprocess
            
            # Check for local certificates
            app_identity = subprocess.run(
                ["security", "find-identity", "-v", "-p", "codesigning"],
                capture_output=True, text=True
            )
            
            if "Developer ID Application" in app_identity.stdout:
                log_success("Found local Developer ID Application certificate")
                
                # Extract identity name
                import re
                match = re.search(r'"([^"]*Developer ID Application[^"]*)"', app_identity.stdout)
                app_cert_name = match.group(1) if match else None
                
                # Check for installer certificate
                installer_cert_name = None
                if "Developer ID Installer" in app_identity.stdout:
                    match = re.search(r'"([^"]*Developer ID Installer[^"]*)"', app_identity.stdout)
                    installer_cert_name = match.group(1) if match else None
                
                return {
                    "apple_id": os.getenv("APPLE_ID"),
                    "apple_password": os.getenv("APPLE_ID_PASSWORD"),
                    "team_id": os.getenv("APPLE_TEAM_ID"),
                    "signing_identity": app_cert_name,
                    "installer_identity": installer_cert_name
                }
            else:
                log_warning("No Developer ID certificates found in local keychain")
                return None
                
        except Exception as e:
            log_error(f"Failed to check local certificates: {e}")
            return None

def build_pkg(app_path, pkg_name, version, build_type, skip_notarization, output_dir, credentials):
    """Build PKG using macOS-Pkg-Builder with GitHub Actions certificate support"""
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
    
    # Setup certificates if needed for GitHub Actions
    signing_identity = None
    if build_type != "dev" and credentials and credentials.get("signing_identity") == "from_github_secrets":
        log_info("Setting up certificates from GitHub secrets...")
        if setup_github_certificates():
            # Get the actual signing identity from keychain
            signing_identity = get_signing_identity_from_keychain()
        else:
            log_warning("Failed to setup certificates from GitHub secrets")
    elif credentials and credentials.get("signing_identity"):
        signing_identity = credentials["signing_identity"]
    
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
    
    # Add signing if available
    if signing_identity and build_type != "dev":
        log_info(f"Adding signing with identity: {signing_identity}")
        pkg_config["pkg_signing_identity"] = signing_identity
    else:
        log_warning("Skipping signing (dev build or no signing identity)")
    
    try:
        # Create and build package
        log_info(f"Creating package with config:")
        for key, value in pkg_config.items():
            if key != "pkg_file_structure":
                log_info(f"  {key}: {value}")
        
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
                    result = subprocess.run(["pkgutil", "--check-signature", str(output_pkg)], 
                                         capture_output=True, text=True)
                    if result.returncode == 0:
                        log_success("PKG is signed")
                        log_info("Signature details:")
                        for line in result.stdout.split('\n'):
                            if line.strip():
                                log_info(f"  {line.strip()}")
                    else:
                        log_info("PKG is not signed (expected for dev builds)")
                except subprocess.CalledProcessError as e:
                    log_info(f"PKG signature check failed: {e}")
                
                # Handle notarization separately if needed
                if not skip_notarization and build_type != "dev" and credentials:
                    log_info("Starting notarization process...")
                    if handle_notarization(output_pkg, credentials):
                        log_success("Notarization completed successfully")
                    else:
                        log_warning("Notarization failed or skipped")
                else:
                    if skip_notarization:
                        log_info("Notarization skipped (--skip-notarize specified)")
                    elif build_type == "dev":
                        log_info("Notarization skipped (dev build)")
                    else:
                        log_warning("Notarization skipped (no credentials)")
                
                return True
            else:
                log_error("PKG file was not created")
                return False
        else:
            log_error("PKG build failed")
            return False
            
    except Exception as e:
        log_error(f"PKG build failed with exception: {e}")
        import traceback
        log_error(f"Exception details: {traceback.format_exc()}")
        return False

def setup_github_certificates():
    """Setup certificates from GitHub environment variables"""
    try:
        import subprocess
        import tempfile
        
        # Get certificate data from environment
        app_cert_data = os.getenv("APPLE_DEVELOPER_ID_APPLICATION_CERT")
        installer_cert_data = os.getenv("APPLE_DEVELOPER_ID_INSTALLER_CERT")
        cert_password = os.getenv("APPLE_CERT_PASSWORD")
        
        if not all([app_cert_data, installer_cert_data, cert_password]):
            log_error("Missing certificate environment variables")
            return False
        
        # Create temporary directory for certificates
        cert_dir = "/tmp/github_certs"
        os.makedirs(cert_dir, exist_ok=True)
        
        # Decode certificates
        import base64
        with open(f"{cert_dir}/app.p12", "wb") as f:
            f.write(base64.b64decode(app_cert_data))
        
        with open(f"{cert_dir}/installer.p12", "wb") as f:
            f.write(base64.b64decode(installer_cert_data))
        
        # Create temporary keychain
        keychain_name = f"r2midi-github-{int(time.time())}.keychain"
        keychain_password = f"temp-{int(time.time())}-{os.urandom(8).hex()}"
        
        # Create and configure keychain
        subprocess.run(["security", "create-keychain", "-p", keychain_password, keychain_name], check=True)
        subprocess.run(["security", "set-keychain-settings", "-lut", "21600", keychain_name], check=True)
        subprocess.run(["security", "unlock-keychain", "-p", keychain_password, keychain_name], check=True)
        
        # Add to search list
        result = subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True)
        existing_keychains = result.stdout.strip().split('\n')
        existing_keychains = [kc.strip('"') for kc in existing_keychains]
        all_keychains = [keychain_name] + existing_keychains
        subprocess.run(["security", "list-keychains", "-d", "user", "-s"] + all_keychains, check=True)
        
        # Import certificates
        subprocess.run([
            "security", "import", f"{cert_dir}/app.p12",
            "-k", keychain_name, "-P", cert_password,
            "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"
        ], check=True)
        
        subprocess.run([
            "security", "import", f"{cert_dir}/installer.p12",
            "-k", keychain_name, "-P", cert_password,
            "-T", "/usr/bin/productsign", "-T", "/usr/bin/security"
        ], check=True)
        
        # Set partition list
        subprocess.run([
            "security", "set-key-partition-list",
            "-S", "apple-tool:,apple:", "-s", "-k", keychain_password, keychain_name
        ], check=True)
        
        # Store for cleanup
        global temp_keychain_name
        temp_keychain_name = keychain_name
        
        log_success("GitHub certificates setup completed")
        return True
        
    except Exception as e:
        log_error(f"Failed to setup GitHub certificates: {e}")
        return False

def get_signing_identity_from_keychain():
    """Get signing identity from keychain after setup"""
    try:
        import subprocess
        result = subprocess.run(
            ["security", "find-identity", "-v", "-p", "codesigning"],
            capture_output=True, text=True
        )
        
        # Find Developer ID Installer identity first (for PKG signing)
        for line in result.stdout.split('\n'):
            if "Developer ID Installer" in line:
                import re
                match = re.search(r'"([^"]*Developer ID Installer[^"]*)"', line)
                if match:
                    log_info(f"Found installer identity: {match.group(1)}")
                    return match.group(1)
        
        # If no installer identity, look for application identity
        for line in result.stdout.split('\n'):
            if "Developer ID Application" in line:
                import re
                match = re.search(r'"([^"]*Developer ID Application[^"]*)"', line)
                if match:
                    log_warning(f"Using application identity for PKG: {match.group(1)}")
                    return match.group(1)
        
        log_warning("No Developer ID signing identity found")
        return None
        
    except Exception as e:
        log_error(f"Failed to get signing identity: {e}")
        return None

def handle_notarization(pkg_path, credentials):
    """Handle notarization using xcrun notarytool"""
    if not all([credentials.get("apple_id"), credentials.get("apple_password"), credentials.get("team_id")]):
        log_warning("Missing notarization credentials")
        return False
    
    try:
        import subprocess
        import time
        
        # Create temporary profile
        profile_name = f"r2midi-notarization-{int(time.time())}"
        
        subprocess.run([
            "xcrun", "notarytool", "store-credentials", profile_name,
            "--apple-id", credentials["apple_id"],
            "--password", credentials["apple_password"],
            "--team-id", credentials["team_id"]
        ], check=True, capture_output=True)
        
        # Submit and wait
        result = subprocess.run([
            "xcrun", "notarytool", "submit", str(pkg_path),
            "--keychain-profile", profile_name,
            "--wait", "--timeout", "30m"
        ], capture_output=True, text=True)
        
        # Cleanup profile
        subprocess.run([
            "xcrun", "notarytool", "delete-credentials", profile_name
        ], capture_output=True)
        
        if "status: Accepted" in result.stdout:
            log_success("Notarization accepted")
            
            # Staple
            subprocess.run(["xcrun", "stapler", "staple", str(pkg_path)], check=True)
            log_success("Notarization stapled")
            return True
        else:
            log_error(f"Notarization failed: {result.stdout}")
            return False
            
    except Exception as e:
        log_error(f"Notarization failed with exception: {e}")
        return False

# Global variable for cleanup
temp_keychain_name = None

def cleanup():
    """Cleanup temporary keychain and certificates"""
    global temp_keychain_name
    if temp_keychain_name:
        try:
            import subprocess
            subprocess.run(["security", "delete-keychain", temp_keychain_name], capture_output=True)
            log_info(f"Cleaned up temporary keychain: {temp_keychain_name}")
        except:
            pass
    
    # Remove certificate files
    import shutil
    try:
        shutil.rmtree("/tmp/github_certs", ignore_errors=True)
    except:
        pass

import atexit
import time
atexit.register(cleanup)

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
