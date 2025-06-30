#!/usr/bin/env python3
"""
Simple R2MIDI Package Builder using macOS-Pkg-Builder correctly
No manual app bundle creation - let the library handle everything
"""

import os
import sys
import json
import argparse
import tempfile
import subprocess
import shutil
import time
import base64
import logging
from pathlib import Path

# Enable debug logging to see macOS-Pkg-Builder errors
logging.basicConfig(level=logging.DEBUG, format='%(levelname)s: %(message)s')

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
    print("=" * 60)

def get_version():
    """Extract version from server/version.py"""
    try:
        sys.path.insert(0, 'server')
        from version import __version__
        return __version__
    except ImportError:
        log_warning("Could not import version from server/version.py, using default")
        return "1.0.0"

def extract_identity_from_cert(cert_file, cert_type):
    """Extract certificate identity from .cer file without importing to keychain"""
    try:
        # Use openssl to extract certificate info without keychain
        cmd = [
            "openssl", "x509", "-in", str(cert_file), "-inform", "DER", "-subject", "-noout"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            log_error(f"Failed to extract {cert_type} certificate info")
            return None

        subject_line = result.stdout.strip()
        # Extract CN (Common Name) from subject
        if "CN=" in subject_line:
            cn_part = subject_line.split("CN=")[1].split(",")[0].strip()
            log_success(f"Extracted {cert_type} identity: {cn_part}")
            return cn_part
        else:
            log_error(f"Could not extract CN from {cert_type} certificate")
            return None

    except Exception as e:
        log_error(f"Error extracting {cert_type} identity: {e}")
        return None

def setup_github_certificates(app_cert_b64, installer_cert_b64, cert_password, apple_id, apple_password, team_id, asc_key_id=None, asc_issuer_id=None, asc_api_key=None):
    """Setup certificates from GitHub Actions environment variables"""
    log_info("Setting up certificates from GitHub Actions environment")

    # Create temporary directory for certificates
    cert_dir = Path("/tmp/github_certs")
    cert_dir.mkdir(exist_ok=True)

    try:
        # Decode and save certificates
        app_cert_path = cert_dir / "app_cert.p12"
        installer_cert_path = cert_dir / "installer_cert.p12"

        # Decode base64 certificates
        with open(app_cert_path, "wb") as f:
            f.write(base64.b64decode(app_cert_b64))
        with open(installer_cert_path, "wb") as f:
            f.write(base64.b64decode(installer_cert_b64))

        log_success("Decoded GitHub certificates")

        # Use login keychain for GitHub Actions
        keychain_name = "login.keychain-db"

        # Install Apple certificate chain
        install_apple_cert_chain()

        # Import certificates to keychain
        log_info("Importing application certificate to login keychain...")
        app_import_cmd = [
            "security", "import", str(app_cert_path),
            "-k", keychain_name,
            "-P", cert_password,
            "-T", "/usr/bin/codesign",
            "-T", "/usr/bin/security"
        ]
        subprocess.run(app_import_cmd, check=True, capture_output=True)
        log_success("Application certificate imported")

        log_info("Importing installer certificate to login keychain...")
        installer_import_cmd = [
            "security", "import", str(installer_cert_path),
            "-k", keychain_name,
            "-P", cert_password,
            "-T", "/usr/bin/productsign",
            "-T", "/usr/bin/security"
        ]
        subprocess.run(installer_import_cmd, check=True, capture_output=True)
        log_success("Installer certificate imported")

        # Set keychain access permissions
        subprocess.run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", cert_password, keychain_name], 
                      capture_output=True)

        # Create config object for notarization
        cert_config = {
            "apple_id": apple_id,
            "apple_password": apple_password,
            "team_id": team_id
        }

        # Add App Store Connect API credentials if available (preferred method)
        if asc_key_id and asc_issuer_id and asc_api_key:
            # Save API key to temporary file with proper formatting
            api_key_path = cert_dir / "app_store_connect_api_key.p8"
            
            # Ensure proper PEM format for the API key
            api_key_content = asc_api_key.strip()
            
            # If the key doesn't have PEM headers, it might be base64 encoded
            if not api_key_content.startswith("-----BEGIN"):
                try:
                    # Try to decode as base64
                    import base64
                    decoded_key = base64.b64decode(api_key_content).decode('utf-8')
                    if decoded_key.startswith("-----BEGIN"):
                        api_key_content = decoded_key
                    else:
                        log_warning("API key doesn't appear to be in proper PEM format")
                except Exception:
                    log_warning("Could not decode API key as base64, using as-is")
            
            with open(api_key_path, "w") as f:
                f.write(api_key_content)

            cert_config.update({
                "app_store_connect_key_id": asc_key_id,
                "app_store_connect_issuer_id": asc_issuer_id,
                "app_store_connect_api_key_path": str(api_key_path)
            })
            log_info("App Store Connect API credentials configured for notarization")

        log_success("GitHub certificates setup complete")
        return cert_config

    except Exception as e:
        log_error(f"Failed to setup GitHub certificates: {e}")
        return None
    # Note: Certificate cleanup moved to main() finally block to preserve files for notarization

def install_apple_cert_chain():
    """Install Apple certificate chain needed for signing"""
    log_info("Ensuring Apple certificate chain is properly installed...")

    # Download and install Apple Root CA G3 if needed
    try:
        apple_root_cmd = ["curl", "-s", "-o", "/tmp/AppleRootCA-G3.cer", 
                         "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer"]
        subprocess.run(apple_root_cmd, check=False)

        dev_id_cmd = ["curl", "-s", "-o", "/tmp/DeveloperIDG2CA.cer",
                     "https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"]
        subprocess.run(dev_id_cmd, check=False)

        # Install certificates
        subprocess.run(["security", "add-trusted-cert", "-d", "-r", "trustRoot", 
                       "-k", "/Library/Keychains/System.keychain", "/tmp/AppleRootCA-G3.cer"], 
                      capture_output=True)
        subprocess.run(["security", "add-trusted-cert", "-d", "-r", "trustAsRoot",
                       "-k", "/Library/Keychains/System.keychain", "/tmp/DeveloperIDG2CA.cer"],
                      capture_output=True)

        log_success("Apple certificate chain verified")
    except Exception as e:
        log_warning(f"Could not install Apple certificate chain: {e}")

def setup_certificates():
    """Setup certificates for signing using P12 files or GitHub Actions environment"""
    log_step("Setting up Certificates")

    # Check for GitHub Actions environment variables first
    github_app_cert = os.environ.get("APPLE_DEVELOPER_ID_APPLICATION_CERT")
    github_installer_cert = os.environ.get("APPLE_DEVELOPER_ID_INSTALLER_CERT")
    github_cert_password = os.environ.get("APPLE_CERT_PASSWORD")
    github_apple_id = os.environ.get("APPLE_ID")
    github_apple_password = os.environ.get("APPLE_ID_PASSWORD") 
    github_team_id = os.environ.get("APPLE_TEAM_ID")

    # App Store Connect API credentials (preferred for GitHub Actions)
    github_asc_key_id = os.environ.get("APP_STORE_CONNECT_KEY_ID")
    github_asc_issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID")
    github_asc_api_key = os.environ.get("APP_STORE_CONNECT_API_KEY")

    if github_app_cert and github_installer_cert and github_cert_password:
        log_info("Detected GitHub Actions environment, using environment variables")
        return setup_github_certificates(
            github_app_cert, github_installer_cert, github_cert_password,
            github_apple_id, github_apple_password, github_team_id,
            github_asc_key_id, github_asc_issuer_id, github_asc_api_key
        )

    # Fall back to local configuration file
    config_path = Path("apple_credentials/config/app_config.json")
    if not config_path.exists():
        log_warning("Configuration file not found, building unsigned")
        return None

    try:
        with open(config_path) as f:
            config = json.load(f)
            apple_config = config.get("apple_developer", {})
    except Exception as e:
        log_error(f"Failed to read config: {e}")
        return None

    # Check for P12 files
    p12_path = apple_config.get("p12_path", "apple_credentials/certificates")
    p12_password = apple_config.get("p12_password")

    app_p12_path = Path(p12_path) / "developerID_application.p12"
    installer_p12_path = Path(p12_path) / "developerID_installer.p12"
    private_key_path = Path(p12_path) / "private_key.p12"

    if not app_p12_path.exists() or not installer_p12_path.exists():
        log_warning("P12 certificate files not found, building unsigned")
        return None

    if not private_key_path.exists():
        log_warning("Private key P12 file not found, building unsigned")
        return None

    if not p12_password:
        log_warning("P12 password not found in config, building unsigned")
        return None

    # Use login keychain for signing - temporary keychains cause private key access issues
    keychain_name = "login.keychain-db"

    # Install Apple certificate chain
    install_apple_cert_chain()

    try:
        # Import P12 certificates to login keychain with private keys accessible
        log_info("Importing application certificate to login keychain...")
        app_result = subprocess.run([
            "security", "import", str(app_p12_path), "-k", keychain_name, 
            "-P", p12_password, "-A", "-T", "/usr/bin/codesign", "-T", "/usr/bin/productsign"
        ], capture_output=True, text=True)

        log_info("Importing installer certificate with private key to login keychain...")
        installer_result = subprocess.run([
            "security", "import", str(installer_p12_path), "-k", keychain_name,
            "-P", p12_password, "-A", "-T", "/usr/bin/codesign", "-T", "/usr/bin/productsign"
        ], capture_output=True, text=True)

        # The installer P12 should contain both certificate and private key
        # If there's a separate private key file, we still import it for completeness
        if private_key_path.exists():
            log_info("Importing additional private key to login keychain...")
            private_key_result = subprocess.run([
                "security", "import", str(private_key_path), "-k", keychain_name,
                "-P", p12_password, "-A", "-T", "/usr/bin/codesign", "-T", "/usr/bin/productsign"
            ], capture_output=True, text=True)
        else:
            private_key_result = None

        # Check results
        app_imported = "1 identity imported" in app_result.stderr or app_result.returncode == 0
        installer_imported = "1 identity imported" in installer_result.stderr or installer_result.returncode == 0
        private_key_imported = True  # Default to true since it's optional

        if private_key_result:
            private_key_imported = "imported" in private_key_result.stderr or private_key_result.returncode == 0

        if app_imported:
            log_success("Application certificate imported")
        else:
            log_warning(f"Application certificate import issue: {app_result.stderr}")

        if installer_imported:
            log_success("Installer certificate imported") 
        else:
            log_warning(f"Installer certificate import issue: {installer_result.stderr}")

        if private_key_result:
            if private_key_imported:
                log_success("Additional private key imported")
            else:
                log_warning(f"Additional private key import issue: {private_key_result.stderr}")

        # List available signing identities
        codesign_result = subprocess.run([
            "security", "find-identity", "-v", "-p", "codesigning"
        ], capture_output=True, text=True)

        log_info("Available code signing identities:")
        for line in codesign_result.stdout.split('\n'):
            if "Developer ID" in line and "valid" in line:
                log_info(f"  {line.strip()}")

        # Also check for installer identities specifically
        installer_check = subprocess.run([
            "security", "find-identity", "-v"
        ], capture_output=True, text=True)

        log_info("Available installer identities:")
        for line in installer_check.stdout.split('\n'):
            if "Developer ID Installer" in line and "valid" in line:
                log_info(f"  {line.strip()}")

        return {
            "keychain_name": keychain_name,
            "apple_id": apple_config.get("apple_id"),
            "apple_password": apple_config.get("app_specific_password"),
            "team_id": apple_config.get("team_id"),
            "app_store_connect_key_id": apple_config.get("app_store_connect_key_id"),
            "app_store_connect_issuer_id": apple_config.get("app_store_connect_issuer_id"),
            "app_store_connect_api_key_path": apple_config.get("app_store_connect_api_key_path"),
            "certificates_imported": True
        }

    except subprocess.CalledProcessError as e:
        log_error(f"Failed to setup certificates: {e}")
        return None

def check_private_key_available(identity):
    """Check if the private key for the identity is available in the keychain"""
    try:
        # Create a temporary file to test signing
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as temp_file:
            temp_file.write(b"Test signing")
            temp_path = temp_file.name

        # Try to sign the file with the identity
        cmd = ["codesign", "--sign", identity, temp_path]
        result = subprocess.run(cmd, capture_output=True, text=True)

        # Clean up
        os.unlink(temp_path)

        # Check if signing succeeded
        if result.returncode == 0:
            log_success(f"Private key is available for identity: {identity}")
            return True
        else:
            log_warning(f"Private key is not available for identity: {identity}")
            log_warning(f"Error: {result.stderr}")
            return False
    except Exception as e:
        log_error(f"Error checking private key: {e}")
        return False

def get_signing_identity(identity_type="installer", cert_config=None):
    """Get signing identity from keychain"""
    if not cert_config:
        log_warning(f"No certificate config available for {identity_type} signing")
        return None

    try:
        log_info(f"Searching for {identity_type} signing identity...")

        if identity_type == "installer":
            # For installer certificates, use find-certificate to get the full name
            keychain_name = cert_config.get("keychain_name", "login.keychain-db")

            log_info("Searching for installer certificate...")
            cert_cmd = ["security", "find-certificate", "-c", "Developer ID Installer", "-p", keychain_name]
            cert_result = subprocess.run(cert_cmd, capture_output=True, text=True)

            if cert_result.returncode == 0 and cert_result.stdout:
                # Certificate exists, extract the full identity name
                try:
                    import tempfile
                    with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as f:
                        f.write(cert_result.stdout)
                        temp_cert = f.name

                    subject_cmd = ["openssl", "x509", "-in", temp_cert, "-noout", "-subject"]
                    subject_result = subprocess.run(subject_cmd, capture_output=True, text=True)

                    os.unlink(temp_cert)  # Clean up temp file

                    if subject_result.returncode == 0:
                        # Parse subject to extract CN
                        subject = subject_result.stdout.strip()
                        if "CN=" in subject:
                            cn_part = subject.split("CN=")[1].split(",")[0].strip()
                            if "Developer ID Installer" in cn_part:
                                log_success(f"Found installer certificate: {cn_part}")

                                # Certificate found and certificate chain is complete
                                # We'll test actual signing during PKG creation
                                log_success(f"Installer certificate ready for signing: {cn_part}")
                                return cn_part
                except Exception as e:
                    log_warning(f"Error testing certificate: {e}")

            log_warning("No installer certificate found in keychain")
            log_warning("PKG will be created unsigned. To enable signing, obtain a 'Developer ID Installer' certificate.")
            return None

        else:
            # For application certificates, use codesigning policy
            keychain_name = cert_config.get("keychain_name", "login.keychain-db")
            cmd = ["security", "find-identity", "-v", "-p", "codesigning", keychain_name]
            result = subprocess.run(cmd, capture_output=True, text=True)

            log_info("Application identity search results:")
            for line in result.stdout.split('\n'):
                if line.strip():
                    log_info(f"  {line}")

            # Look for application identity and extract the hash
            for line in result.stdout.split('\n'):
                if "Developer ID Application" in line and '"' in line:
                    import re
                    # Extract the certificate hash (SHA-1) from the line
                    hash_match = re.search(r'(\w{40})', line)
                    name_match = re.search(r'"([^"]*)"', line)
                    if hash_match and name_match:
                        cert_hash = hash_match.group(1)
                        identity_name = name_match.group(1)
                        log_success(f"Found application identity: {identity_name}")
                        log_info(f"Using certificate hash for signing: {cert_hash}")
                        return cert_hash  # Return hash instead of name for reliable signing

            log_warning("No application identity found in keychain")
            return None

    except Exception as e:
        log_error(f"Failed to get signing identity from keychain: {e}")
        return None

def notarize_pkg(pkg_path, cert_config):
    """Notarize the PKG using xcrun notarytool with App Store Connect API"""

    # Check for App Store Connect API credentials first (preferred method)
    has_api_creds = all([
        cert_config.get("app_store_connect_key_id"),
        cert_config.get("app_store_connect_issuer_id"), 
        cert_config.get("app_store_connect_api_key_path")
    ])

    # Fall back to app-specific password if API creds not available
    has_password_creds = all([
        cert_config.get("apple_id"),
        cert_config.get("apple_password"),
        cert_config.get("team_id")
    ])

    if not has_api_creds and not has_password_creds:
        log_warning("Missing notarization credentials (need either App Store Connect API or Apple ID + app-specific password)")
        return False

    try:
        log_info("Starting notarization...")
        submission_id = None

        if has_api_creds:
            # Use App Store Connect API (preferred)
            api_key_path = Path(cert_config["app_store_connect_api_key_path"])
            if not api_key_path.exists():
                log_error(f"App Store Connect API key not found: {api_key_path}")
                return False

            log_info("Using App Store Connect API for notarization")

            # Submit directly with API credentials  
            result = subprocess.run([
                "xcrun", "notarytool", "submit", str(pkg_path),
                "--key", str(api_key_path.absolute()),
                "--key-id", cert_config["app_store_connect_key_id"],
                "--issuer", cert_config["app_store_connect_issuer_id"],
                "--wait", "--timeout", "30m"
            ], capture_output=True, text=True)

        else:
            # Use app-specific password (fallback)
            log_info("Using Apple ID + app-specific password for notarization")

            # Create temporary profile
            profile_name = f"r2midi-notarization-{int(time.time())}"

            subprocess.run([
                "xcrun", "notarytool", "store-credentials", profile_name,
                "--apple-id", cert_config["apple_id"],
                "--password", cert_config["apple_password"],
                "--team-id", cert_config["team_id"]
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

        # Parse submission ID from output for log retrieval
        for line in result.stdout.split('\n'):
            if 'id:' in line and len(line.split()) >= 2:
                submission_id = line.split()[1]
                break

        log_info(f"Notarization output:\n{result.stdout}")
        if result.stderr:
            log_warning(f"Notarization stderr:\n{result.stderr}")

        if "status: Accepted" in result.stdout:
            log_success("Notarization accepted")

            # Staple
            staple_result = subprocess.run(["xcrun", "stapler", "staple", str(pkg_path)], 
                                         capture_output=True, text=True)
            if staple_result.returncode == 0:
                log_success("Notarization stapled")
            else:
                log_warning(f"Stapling failed: {staple_result.stderr}")
            return True
        else:
            log_error("Notarization failed")

            # Download logs if we have a submission ID
            if submission_id:
                log_info(f"Downloading notarization logs for submission: {submission_id}")
                download_notarization_logs(submission_id, cert_config)
            else:
                log_warning("Could not extract submission ID for log download")

            return False

    except Exception as e:
        log_error(f"Notarization failed: {e}")
        return False

def download_notarization_logs(submission_id, cert_config):
    """Download notarization logs using submission ID"""
    try:
        log_file = Path("artifacts") / f"notarization_log_{submission_id}.json"
        log_file.parent.mkdir(exist_ok=True)

        # Try App Store Connect API first
        has_api_creds = all([
            cert_config.get("app_store_connect_key_id"),
            cert_config.get("app_store_connect_issuer_id"), 
            cert_config.get("app_store_connect_api_key_path")
        ])

        if has_api_creds:
            api_key_path = Path(cert_config["app_store_connect_api_key_path"])

            log_result = subprocess.run([
                "xcrun", "notarytool", "log", submission_id,
                "--key", str(api_key_path.absolute()),
                "--key-id", cert_config["app_store_connect_key_id"],
                "--issuer", cert_config["app_store_connect_issuer_id"]
            ], capture_output=True, text=True)
        else:
            # Fall back to app-specific password
            profile_name = f"r2midi-notarization-logs-{int(time.time())}"

            subprocess.run([
                "xcrun", "notarytool", "store-credentials", profile_name,
                "--apple-id", cert_config["apple_id"],
                "--password", cert_config["apple_password"],
                "--team-id", cert_config["team_id"]
            ], check=True, capture_output=True)

            log_result = subprocess.run([
                "xcrun", "notarytool", "log", submission_id,
                "--keychain-profile", profile_name
            ], capture_output=True, text=True)

            # Cleanup profile
            subprocess.run([
                "xcrun", "notarytool", "delete-credentials", profile_name
            ], capture_output=True)

        if log_result.returncode == 0:
            # Save logs to file
            with open(log_file, "w") as f:
                f.write(log_result.stdout)

            log_success(f"Notarization logs saved to: {log_file}")

            # Parse and display key issues
            try:
                import json
                logs = json.loads(log_result.stdout)
                if "issues" in logs:
                    log_error("Notarization issues found:")
                    for issue in logs["issues"]:
                        severity = issue.get("severity", "unknown")
                        message = issue.get("message", "no message")
                        log_error(f"  [{severity}] {message}")

                        if "path" in issue:
                            log_error(f"    File: {issue['path']}")
                        if "architecture" in issue:
                            log_error(f"    Architecture: {issue['architecture']}")
                else:
                    log_info("No specific issues found in notarization logs")
                    log_info(f"Full logs content:\n{log_result.stdout}")

            except json.JSONDecodeError:
                log_warning("Could not parse notarization logs as JSON")
                log_info(f"Raw logs:\n{log_result.stdout}")

        else:
            log_error(f"Failed to download notarization logs: {log_result.stderr}")

    except Exception as e:
        log_error(f"Error downloading notarization logs: {e}")

def cleanup_certificates(cert_config):
    """Cleanup any temporary resources"""
    # Clean up temporary certificate files for GitHub Actions
    cert_dir = Path("/tmp/github_certs")
    if cert_dir.exists():
        shutil.rmtree(cert_dir, ignore_errors=True)
    
    if cert_config:
        log_info("Certificate cleanup complete")


def create_component_directory(component, build_dir):
    """Create directory structure for component installation"""
    log_step(f"Creating {component} installation structure")

    # Create Application bundle structure for installation to /Applications
    if component == "server":
        app_name = "R2MIDI Server.app"
    else:  # client
        app_name = "R2MIDI Client.app"

    # Create component directory in build (will become the .app bundle)
    component_dir = build_dir / app_name
    contents_dir = component_dir / "Contents"
    macos_dir = contents_dir / "MacOS"
    resources_dir = contents_dir / "Resources"
    lib_dir = resources_dir / "lib"

    # Clean and recreate directories
    if component_dir.exists():
        shutil.rmtree(component_dir, ignore_errors=True)

    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)
    lib_dir.mkdir(parents=True, exist_ok=True)

    # Copy component source files
    if component == "server":
        source_dir = Path("server")
        dest_dir = lib_dir / "server"
        venv_dir = Path("build_venv_server")
        executable_name = "R2MIDI Server"
    else:  # client
        source_dir = Path("r2midi_client")
        dest_dir = lib_dir / "r2midi_client"
        venv_dir = Path("build_venv_client")
        executable_name = "R2MIDI Client"

    if source_dir.exists():
        # Exclude venv directories and cache files when copying source
        shutil.copytree(source_dir, dest_dir, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'venv', '.venv'), dirs_exist_ok=True)
        log_success(f"Copied {component} source files")
    else:
        log_error(f"Source directory not found: {source_dir}")
        return None

    # Copy virtual environment dependencies
    if venv_dir.exists():
        venv_lib_dir = venv_dir / "lib" / "python3.13" / "site-packages"
        if venv_lib_dir.exists():
            dest_venv_dir = lib_dir / "site-packages"

            # Custom ignore function to exclude problematic packages
            def ignore_problematic_packages(src, names):
                ignored = []
                for name in names:
                    # Exclude packages with compiled extensions for notarization simplicity
                    problematic_packages = ['py2app', 'rtmidi', 'pydantic_core']

                    # For client, only exclude packages that cause notarization issues
                    if component == "client":
                        problematic_packages.extend(['PyQt6', 'pyqt6_sip', 'pyqt6-sip', 'psutil'])
                        # Exclude psutil to avoid notarization issues with unsigned binaries

                    if (name in problematic_packages or 
                        any(pkg in src for pkg in problematic_packages)):
                        ignored.append(name)
                        log_info(f"Excluding problematic package: {name}")
                    elif name.endswith('.pyc') or name == '__pycache__':
                        ignored.append(name)
                return ignored

            shutil.copytree(venv_lib_dir, dest_venv_dir, ignore=ignore_problematic_packages, dirs_exist_ok=True)
            log_success(f"Copied {component} dependencies from virtual environment")
        else:
            log_warning(f"Virtual environment site-packages not found: {venv_lib_dir}")
    else:
        log_warning(f"Virtual environment not found: {venv_dir}")

    # Copy shared resources if they exist
    shared_resources_dir = Path("resources")
    if shared_resources_dir.exists():
        dest_shared_resources = resources_dir / "shared"
        shutil.copytree(shared_resources_dir, dest_shared_resources, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'), dirs_exist_ok=True)
        log_success("Copied shared resources")

    # Create Info.plist for the app bundle
    if component == "server":
        bundle_id = "com.tirans.m2midi.r2midi.server"
        display_name = "R2MIDI Server"
    else:  # client
        bundle_id = "com.tirans.m2midi.r2midi.client"
        display_name = "R2MIDI Client"

    info_plist_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{executable_name}</string>
    <key>CFBundleIdentifier</key>
    <string>{bundle_id}</string>
    <key>CFBundleName</key>
    <string>{display_name}</string>
    <key>CFBundleDisplayName</key>
    <string>{display_name}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>r2midi</string>
</dict>
</plist>'''

    info_plist_path = contents_dir / "Info.plist"
    with open(info_plist_path, "w") as f:
        f.write(info_plist_content)
    log_success("Created Info.plist")

    # Create executable launcher in MacOS directory
    if component == "server":
        launcher_content = f'''#!/bin/bash
# R2MIDI Server Launcher Script

# Get the directory of this script (inside the app bundle)
SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$APP_DIR/Resources"

# Set up environment - include site-packages for dependencies
export PYTHONPATH="$RESOURCES_DIR/lib:$RESOURCES_DIR/lib/site-packages:$PYTHONPATH"

# Create logs directory if it doesn't exist
mkdir -p "$RESOURCES_DIR/lib/server/logs"

# Run the server with proper working directory
cd "$RESOURCES_DIR/lib"
exec python3 -m server.main "$@"
'''
    else:  # client
        launcher_content = f'''#!/bin/bash
# R2MIDI Client Launcher Script

# Get the directory of this script (inside the app bundle)
SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$APP_DIR/Resources"

# Set up environment - include site-packages for dependencies  
export PYTHONPATH="$RESOURCES_DIR/lib:$RESOURCES_DIR/lib/site-packages:$PYTHONPATH"

# Check for PyQt6 availability and add system paths if needed
python3 -c "import PyQt6" 2>/dev/null || {{
    echo "Looking for system PyQt6..."
    # Add common system Python paths for PyQt6
    for pypath in /usr/local/lib/python*/site-packages /opt/homebrew/lib/python*/site-packages ~/.local/lib/python*/site-packages; do
        if [ -d "$pypath/PyQt6" ]; then
            export PYTHONPATH="$pypath:$PYTHONPATH"
            echo "Found PyQt6 at: $pypath"
            break
        fi
    done
}}

# Run the client with proper working directory
cd "$RESOURCES_DIR/lib"
exec python3 -m r2midi_client.main "$@"
'''

    launcher_path = macos_dir / executable_name
    with open(launcher_path, "w") as f:
        f.write(launcher_content)
    launcher_path.chmod(0o755)

    # Copy icon file if it exists
    icon_sources = ["r2midi.icns", "resources/r2midi.icns", "r2midi.iconset/icon_512x512@2x.png"]
    for icon_source in icon_sources:
        icon_path = Path(icon_source)
        if icon_path.exists():
            icon_dest = resources_dir / "r2midi.icns"
            if icon_path.suffix == ".png":
                # If PNG, just copy as icns (macOS will handle it)
                shutil.copy2(icon_path, icon_dest)
            else:
                shutil.copy2(icon_path, icon_dest)
            log_success(f"Copied icon from {icon_source}")
            break

    log_success(f"Created app bundle: {app_name}")
    return component_dir

def sign_all_binaries_in_app(app_bundle_path, cert_config):
    """Sign all executable binaries and shared libraries in the app bundle"""
    if not cert_config:
        log_warning("No certificate config available for binary signing")
        return False

    # Get application signing identity
    app_signing_identity = get_signing_identity("application", cert_config)
    if not app_signing_identity:
        log_warning("No application signing identity found")
        return False

    log_step(f"Signing all binaries in {app_bundle_path.name}")

    # Find all executable files and shared libraries
    files_to_sign = []

    for root, dirs, files in os.walk(app_bundle_path):
        for file in files:
            file_path = Path(root) / file

            # Skip symbolic links
            if file_path.is_symlink():
                continue

            # Skip entire py2app package to avoid notarization issues
            if 'py2app' in str(file_path):
                continue

            # Skip PyQt6 binaries - they're pre-signed by Qt Company and cause certificate chain issues
            if 'PyQt6' in str(file_path):
                continue

            # Check if file should be signed
            should_sign = False

            # Only sign actual Mach-O binaries and shared libraries
            if file.endswith(('.so', '.dylib')):
                should_sign = True
            # For executables, be more strict about what we sign
            elif file_path.is_file() and os.access(file_path, os.X_OK):
                try:
                    # Use file command to check if it's actually a Mach-O binary
                    result = subprocess.run(['file', str(file_path)], 
                                          capture_output=True, text=True)
                    if ('Mach-O' in result.stdout and 
                        ('executable' in result.stdout.lower() or 
                         'dynamically linked' in result.stdout)):
                        should_sign = True

                    # Don't sign Python source files, shell scripts, or other text files
                    if (file.endswith(('.py', '.sh', '.txt', '.md', '.json', '.xml', '.plist')) or
                        'ASCII text' in result.stdout or
                        'Python script' in result.stdout or
                        'shell script' in result.stdout):
                        should_sign = False
                except:
                    pass

            if should_sign:
                files_to_sign.append(file_path)

    # For notarization, we need to sign the app bundle even if no individual binaries are found
    # This is especially important when the main executable is a shell script
    log_info(f"Found {len(files_to_sign)} internal binaries to sign")

    # Sign each binary
    signed_count = 0
    failed_count = 0

    for binary_path in files_to_sign:
        try:
            # Check if this is a Python executable that needs force re-signing
            force_resign = (
                'python' in str(binary_path).lower() or 
                str(binary_path).endswith(('.so', '.dylib'))
            )

            # Sign with hardened runtime for notarization
            cmd = [
                "codesign",
                "--sign", app_signing_identity,
                "--timestamp",
                "--options", "runtime",
                "--verbose"
            ]

            # Force re-signing for Python executables and libraries
            if force_resign:
                cmd.append("--force")

            cmd.append(str(binary_path))

            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                signed_count += 1
                log_info(f"✅ Signed: {binary_path.relative_to(app_bundle_path)}")
            else:
                failed_count += 1
                log_warning(f"❌ Failed to sign: {binary_path.relative_to(app_bundle_path)}")
                log_warning(f"   Error: {result.stderr.strip()}")

        except Exception as e:
            failed_count += 1
            log_warning(f"❌ Exception signing {binary_path.relative_to(app_bundle_path)}: {e}")

    # Sign the main app bundle executable
    main_executable = app_bundle_path / "Contents" / "MacOS"
    for exe_file in main_executable.glob("*"):
        if exe_file.is_file() and not exe_file.is_symlink():
            try:
                cmd = [
                    "codesign",
                    "--sign", app_signing_identity,
                    "--timestamp", 
                    "--options", "runtime",
                    "--verbose",
                    "--force",  # Force re-signing of main executable
                    str(exe_file)
                ]

                result = subprocess.run(cmd, capture_output=True, text=True)

                if result.returncode == 0:
                    signed_count += 1
                    log_success(f"✅ Signed main executable: {exe_file.name}")
                else:
                    failed_count += 1
                    log_warning(f"❌ Failed to sign main executable: {exe_file.name}")
                    log_warning(f"   Error: {result.stderr.strip()}")

            except Exception as e:
                failed_count += 1
                log_warning(f"❌ Exception signing main executable {exe_file.name}: {e}")

    # Finally, sign the entire app bundle
    try:
        cmd = [
            "codesign",
            "--sign", app_signing_identity,
            "--timestamp",
            "--options", "runtime", 
            "--verbose",
            "--force",  # Force re-signing of app bundle
            "--deep",  # Sign nested bundles
            str(app_bundle_path)
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            log_success(f"✅ Signed app bundle: {app_bundle_path.name}")
            signed_count += 1
        else:
            log_warning(f"❌ Failed to sign app bundle: {app_bundle_path.name}")
            log_warning(f"   Error: {result.stderr.strip()}")
            failed_count += 1

    except Exception as e:
        failed_count += 1
        log_warning(f"❌ Exception signing app bundle {app_bundle_path.name}: {e}")

    log_info(f"Binary signing complete: {signed_count} signed, {failed_count} failed")

    if failed_count > 0:
        log_warning("Some binaries failed to sign - notarization may fail")
        return False
    else:
        log_success("All binaries signed successfully")
        return True

def build_component_pkg(component, version, cert_config, args):
    """Build PKG for a component using direct installation without app bundles

    Returns:
        tuple: (success: bool, signed: bool, notarized: bool)
    """
    log_step(f"Building {component.title()} PKG")

    try:
        from macos_pkg_builder import Packages
    except ImportError:
        log_error("macOS-Pkg-Builder not available. Install with: pip install macos-pkg-builder")
        return False, False, False

    # Create build directory - use timestamped to avoid permission issues
    build_dir = Path(f"build_v2_{int(time.time())}")
    build_dir.mkdir(exist_ok=True)

    # Create component directory structure
    component_dir = create_component_directory(component, build_dir)
    if not component_dir:
        log_error(f"Failed to create component directory for {component}")
        return False, False, False

    # Apply proper PyQt6-compatible signing approach for client
    if cert_config and not args.no_sign and component == "client":
        log_info("Applying PyQt6-compatible app bundle signing...")

        # Get application signing identity
        app_signing_identity = get_signing_identity("application", cert_config)
        if app_signing_identity:
            try:
                # Create entitlements file for hardened runtime
                entitlements_path = build_dir / "entitlements.plist"
                entitlements_content = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>'''
                with open(entitlements_path, "w") as f:
                    f.write(entitlements_content)

                # Sign the app bundle with hardened runtime (required for notarization)
                # Following 2024 best practices: avoid --deep, use bottom-up approach
                cmd = [
                    "codesign",
                    "--sign", app_signing_identity,
                    "--timestamp",
                    "--options", "runtime",
                    "--entitlements", str(entitlements_path),
                    "--force",  # Overwrite existing signatures
                    "--verbose",
                    str(component_dir)
                ]

                result = subprocess.run(cmd, capture_output=True, text=True)

                if result.returncode == 0:
                    log_success(f"✅ App bundle signed with PyQt6-compatible approach")
                else:
                    log_warning(f"❌ App bundle signing failed: {result.stderr.strip()}")

            except Exception as e:
                log_warning(f"❌ Exception during app bundle signing: {e}")
        else:
            log_warning("No application signing identity found for app bundle signing")
    else:
        # Skip binary signing for server or when certificates unavailable
        log_info("Skipping binary signing (PKG signing is sufficient for distribution)")

    # Set up component details
    if component == "server":
        bundle_id = "com.tirans.m2midi.r2midi.server"
        app_name = "R2MIDI Server"
    else:  # client
        bundle_id = "com.tirans.m2midi.r2midi.client"
        app_name = "R2MIDI Client"

    # Create PKG output directory
    output_dir = Path("artifacts")
    output_dir.mkdir(exist_ok=True)

    pkg_name = f"R2MIDI-{component.title()}-{version}"
    output_pkg = output_dir / f"{pkg_name}.pkg"

    # Get signing identity for PKG
    signing_identity = None
    signing_required = cert_config and not args.no_sign
    notarization_required = cert_config and not getattr(args, 'no_notarize', True) and not args.no_sign

    if signing_required:
        signing_identity = get_signing_identity("installer", cert_config)

    # Install to /opt/r2midi (requires admin but then symlink to user Applications)
    install_base = "/opt/r2midi"
    app_bundle_name = f"{app_name}.app"

    log_info(f"Building PKG to install {app_bundle_name} to {install_base}")

    # Log signing information
    if signing_identity:
        log_info(f"Will sign PKG with: {signing_identity}")

    # Create postinstall script to create symlinks in user's Applications folder
    scripts_dir = build_dir / "scripts"
    scripts_dir.mkdir(exist_ok=True)

    postinstall_script = scripts_dir / "postinstall"
    if component == "server":
        app_bundle_name = "R2MIDI Server.app"
    else:  # client
        app_bundle_name = "R2MIDI Client.app"

    postinstall_content = f'''#!/bin/bash
# Post-installation script for R2MIDI {component}

# Get the user who invoked the installer (even if run with sudo)
REAL_USER="${{SUDO_USER:-$USER}}"
USER_HOME=$(eval echo "~$REAL_USER")

# Create ~/Applications directory if it doesn't exist
if [ ! -d "$USER_HOME/Applications" ]; then
    mkdir -p "$USER_HOME/Applications"
    chown "$REAL_USER" "$USER_HOME/Applications"
    echo "Created $USER_HOME/Applications directory"
fi

# Install external dependencies for client component
if [ "{component}" = "client" ]; then
    echo "Installing system dependencies (PyQt6)..."

    # Try multiple installation methods
    if command -v pip3 >/dev/null 2>&1; then
        # Install dependencies to system or user location
        pip3 install --break-system-packages PyQt6==6.9.1 pyqt6-sip==13.10.2 2>/dev/null || \\
        pip3 install --user PyQt6==6.9.1 pyqt6-sip==13.10.2 || \\
        echo "Warning: Could not install dependencies. User may need to install manually: pip3 install PyQt6"
    else
        echo "Warning: pip3 not found. Dependencies must be installed manually: pip3 install PyQt6"
    fi
fi

# Fix permissions on the installed app (PKG installs as root)
if [ -d "/opt/r2midi/{app_bundle_name}" ]; then
    echo "Fixing permissions for /opt/r2midi/{app_bundle_name}"
    # Make app readable and executable by all users
    chmod -R a+rX "/opt/r2midi/{app_bundle_name}"
    # Ensure executables are executable
    find "/opt/r2midi/{app_bundle_name}" -name "*.py" -exec chmod a+r {{}} \\;
    find "/opt/r2midi/{app_bundle_name}" -name "*.so" -exec chmod a+rx {{}} \\;
fi

# Create symlink to the installed app
SOURCE_APP="/opt/r2midi/{app_bundle_name}"
TARGET_APP="$USER_HOME/Applications/{app_bundle_name}"

if [ -d "$SOURCE_APP" ]; then
    # Remove existing symlink or app if it exists
    rm -rf "$TARGET_APP"

    # Create symlink
    ln -sf "$SOURCE_APP" "$TARGET_APP"

    # Fix ownership of the symlink
    chown -h "$REAL_USER" "$TARGET_APP"

    echo "Created symlink: $TARGET_APP -> $SOURCE_APP"
    echo "The app is now available in ~/Applications and Launchpad"
else
    echo "Warning: Source app not found at $SOURCE_APP"
fi

exit 0
'''

    with open(postinstall_script, "w") as f:
        f.write(postinstall_content)
    postinstall_script.chmod(0o755)

    log_success(f"Created postinstall script to symlink {app_bundle_name} to ~/Applications")

    try:
        # Use native pkgbuild directly to avoid macOS-Pkg-Builder limitations with large file structures
        log_info(f"Creating PKG using native pkgbuild: {output_pkg}")

        # Build pkgbuild command
        # Create proper install structure: the app bundle should install to /opt/r2midi/
        # So we need a proper directory structure
        install_root_dir = build_dir / "install_root_v2"
        install_root_dir.mkdir(exist_ok=True)

        # Create the target directory structure /opt/r2midi/
        target_opt_dir = install_root_dir / "opt" / "r2midi"
        target_opt_dir.mkdir(parents=True, exist_ok=True)

        # Copy the app bundle to the target location  
        target_app_path = target_opt_dir / component_dir.name
        if target_app_path.exists():
            shutil.rmtree(target_app_path)
        shutil.copytree(component_dir, target_app_path)

        root_dir = install_root_dir
        install_location = "/"

        pkgbuild_cmd = [
            "/usr/bin/pkgbuild",
            "--identifier", bundle_id,
            "--version", version,
            "--root", str(root_dir.absolute()),
            "--install-location", install_location,
        ]

        # Add scripts for user Applications directory setup
        if scripts_dir.exists() and postinstall_script.exists():
            pkgbuild_cmd.extend(["--scripts", str(scripts_dir.absolute())])

        # Don't sign during pkgbuild - we'll use productsign after
        temp_pkg = output_pkg.with_suffix('.temp.pkg')

        # Add output path (temporary unsigned PKG)
        pkgbuild_cmd.append(str(temp_pkg.absolute()))

        log_info(f"Running: {' '.join(pkgbuild_cmd)}")

        # Run pkgbuild (unsigned)
        result = subprocess.run(pkgbuild_cmd, capture_output=True, text=True)

        if result.returncode == 0:
            if temp_pkg.exists():
                sign_result = None
                # Sign the PKG using productsign if signing identity available
                if signing_identity:
                    log_info(f"Signing PKG with productsign using: {signing_identity}")
                    productsign_cmd = [
                        "/usr/bin/productsign",
                        "--sign", signing_identity,
                        str(temp_pkg.absolute()),
                        str(output_pkg.absolute())
                    ]

                    sign_result = subprocess.run(productsign_cmd, capture_output=True, text=True)

                    if sign_result.returncode == 0:
                        log_success("PKG signed successfully with productsign")
                        # Remove temporary unsigned PKG
                        temp_pkg.unlink()
                    else:
                        log_error(f"productsign failed: {sign_result.stderr}")
                        # Move temp PKG to final location (unsigned)
                        temp_pkg.rename(output_pkg)
                        log_warning("Using unsigned PKG due to signing failure")
                else:
                    # No signing - just rename temp to final
                    temp_pkg.rename(output_pkg)

                if output_pkg.exists():
                    pkg_size = f"{output_pkg.stat().st_size / (1024*1024):.1f}MB"
                    log_success(f"PKG created: {pkg_name}.pkg ({pkg_size})")

                    # Track actual signing status
                    actually_signed = signing_identity and sign_result and sign_result.returncode == 0
                    if actually_signed:
                        log_success("PKG is signed")
                    else:
                        log_info("PKG is not signed")
                        # If signing was required but failed, this is an error
                        if signing_required:
                            log_error("Signing was required but failed")

                # Handle notarization if enabled
                notarization_success = True
                if notarization_required:
                    if not actually_signed:
                        log_error("Cannot notarize unsigned PKG")
                        notarization_success = False
                    else:
                        notarization_success = notarize_pkg(output_pkg, cert_config)
                        if notarization_success:
                            log_success("PKG notarized successfully")
                        else:
                            log_error("Notarization failed")

                # Return status: (created, signed, notarized)
                return True, actually_signed, notarization_success
            else:
                log_error("PKG creation succeeded but file not found")
                return False, False, False
        else:
            log_error(f"pkgbuild failed with return code: {result.returncode}")
            log_error(f"stdout: {result.stdout}")
            log_error(f"stderr: {result.stderr}")
            return False, False, False

    except Exception as e:
        log_error(f"PKG build failed: {e}")
        import traceback
        log_error(f"Full traceback: {traceback.format_exc()}")
        return False, False, False

def main():
    parser = argparse.ArgumentParser(description="Build R2MIDI packages using macOS-Pkg-Builder")
    parser.add_argument("--component", choices=["server", "client", "both"], default="both",
                       help="Component to build")
    parser.add_argument("--version", help="Version to embed in packages")
    parser.add_argument("--no-sign", action="store_true", help="Skip code signing (creates unsigned packages)")
    parser.add_argument("--no-notarize", action="store_true", help="Skip notarization (signed but not notarized)")

    args = parser.parse_args()

    log_step("R2MIDI Package Builder (Simple)")

    # Show build requirements clearly
    will_sign = not args.no_sign
    will_notarize = not args.no_notarize and will_sign

    log_info(f"Build target: {'signed + notarized' if will_notarize else 'signed only' if will_sign else 'unsigned'} PKGs")

    # Check if we're on macOS
    if os.uname().sysname != "Darwin":
        log_error("This script requires macOS")
        sys.exit(1)

    # Get version
    version = args.version or get_version()
    log_info(f"Building version: {version}")

    # Check for macOS-Pkg-Builder
    try:
        import macos_pkg_builder
        log_success("macOS-Pkg-Builder is available")
    except ImportError:
        log_error("macOS-Pkg-Builder not found. Install with: pip install macos-pkg-builder")
        sys.exit(1)

    # Setup certificates
    cert_config = None
    if not args.no_sign:
        cert_config = setup_certificates()
        if not cert_config:
            log_error("Certificate setup failed but signing was requested")
            log_error("💡 Use --no-sign to build unsigned packages")
            sys.exit(4)

    try:
        # Build components
        components = ["server", "client"] if args.component == "both" else [args.component]

        # Track build requirements and results
        signing_required = cert_config and not args.no_sign
        notarization_required = cert_config and not getattr(args, 'no_notarize', True) and not args.no_sign

        success_count = 0
        signed_count = 0
        notarized_count = 0
        build_results = []

        for component in components:
            log_info(f"Building {component} component...")

            created, signed, notarized = build_component_pkg(component, version, cert_config, args)

            build_results.append({
                'component': component,
                'created': created,
                'signed': signed,
                'notarized': notarized
            })

            if created:
                success_count += 1
                log_success(f"{component.title()} component PKG created")

                if signed:
                    signed_count += 1

                if notarized:
                    notarized_count += 1
            else:
                log_error(f"{component.title()} component build failed")

        # Summary
        log_step("Build Summary")
        log_info(f"Components built: {success_count}/{len(components)}")

        if signing_required:
            log_info(f"Components signed: {signed_count}/{len(components)}")

        if notarization_required:
            log_info(f"Components notarized: {notarized_count}/{len(components)}")

        # List generated packages with status
        artifacts_dir = Path("artifacts")
        if artifacts_dir.exists():
            pkgs = list(artifacts_dir.glob("*.pkg"))
            if pkgs:
                log_info("Generated packages:")
                for i, pkg in enumerate(pkgs):
                    size = f"{pkg.stat().st_size / (1024*1024):.1f}MB"
                    result = build_results[i] if i < len(build_results) else None

                    status_parts = []
                    if result:
                        if result['signed']:
                            status_parts.append("signed")
                        else:
                            status_parts.append("unsigned")

                        if result['notarized']:
                            status_parts.append("notarized")
                        elif notarization_required:
                            status_parts.append("not notarized")

                    status = f" [{', '.join(status_parts)}]" if status_parts else ""
                    log_success(f"  {pkg.name} ({size}){status}")

        # Determine exit code based on requirements
        exit_code = 0
        issues = []

        # Check basic PKG creation
        if success_count != len(components):
            issues.append("PKG creation failed")
            exit_code = 1

        # Check signing requirements
        if signing_required and signed_count != len(components):
            issues.append("signing required but failed")
            exit_code = 2

        # Check notarization requirements  
        if notarization_required and notarized_count != len(components):
            issues.append("notarization required but failed")
            exit_code = 3

        if exit_code == 0:
            if signing_required and notarization_required:
                log_success("🎉 All components built, signed, and notarized successfully!")
            elif signing_required:
                log_success("🎉 All components built and signed successfully!")
            else:
                log_success("🎉 All components built successfully!")
        else:
            log_error(f"❌ Build failed: {', '.join(issues)}")

            # Provide helpful error messages
            if exit_code == 2:
                log_error("💡 To build unsigned packages, use: --no-sign")
                log_error("💡 To obtain signing certificates, visit Apple Developer portal")
            elif exit_code == 3:
                log_error("💡 To skip notarization, use: --no-notarize")
                log_error("💡 Notarization requires valid signing certificates")

        sys.exit(exit_code)

    finally:
        # Cleanup certificates
        if cert_config:
            cleanup_certificates(cert_config)

if __name__ == "__main__":
    main()
