#!/usr/bin/env python3
"""
secure-certificate-manager.py - Secure certificate handling without keychain prompts
Usage: python3 scripts/secure-certificate-manager.py [action] [options]
"""

import sys
import os
import argparse
import json
import tempfile
import subprocess
import base64
from pathlib import Path

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

class SecureCertificateManager:
    def __init__(self):
        self.temp_dir = None
        self.cert_files = {}
        self.signing_identity = None
        self.installer_identity = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.cleanup()

    def cleanup(self):
        """Clean up temporary files"""
        if self.temp_dir and self.temp_dir.exists():
            import shutil
            shutil.rmtree(self.temp_dir, ignore_errors=True)
            log_info("Cleaned up temporary certificate files")

    def setup_github_actions(self):
        """Setup certificates for GitHub Actions without keychain"""
        log_info("Setting up certificates for GitHub Actions (keychain-free)")

        required_vars = [
            "APPLE_DEVELOPER_ID_APPLICATION_CERT",
            "APPLE_DEVELOPER_ID_INSTALLER_CERT"
        ]

        missing_vars = [var for var in required_vars if not os.getenv(var)]
        if missing_vars:
            log_error(f"Missing environment variables: {', '.join(missing_vars)}")
            return False

        # Create temporary directory
        self.temp_dir = Path(tempfile.mkdtemp(prefix="r2midi_certs_"))
        log_info(f"Created temporary certificate directory: {self.temp_dir}")

        # Decode and save certificates
        app_cert_data = base64.b64decode(os.getenv("APPLE_DEVELOPER_ID_APPLICATION_CERT"))
        installer_cert_data = base64.b64decode(os.getenv("APPLE_DEVELOPER_ID_INSTALLER_CERT"))

        self.cert_files["app"] = self.temp_dir / "developerID_application.cer"
        self.cert_files["installer"] = self.temp_dir / "developerID_installer.cer"

        self.cert_files["app"].write_bytes(app_cert_data)
        self.cert_files["installer"].write_bytes(installer_cert_data)

        log_success("Certificates decoded and saved securely")

        # Extract identities without keychain
        self.signing_identity = self._extract_identity_from_cert(
            self.cert_files["app"], "Application"
        )
        self.installer_identity = self._extract_identity_from_cert(
            self.cert_files["installer"], "Installer"
        )

        if self.signing_identity and self.installer_identity:
            log_success("Certificate identities extracted successfully")
            return True
        else:
            log_error("Failed to extract certificate identities")
            return False

    def setup_local(self, config_file_path):
        """Setup certificates for local development"""
        log_info("Setting up certificates for local development (keychain-free)")

        if not config_file_path.exists():
            log_error(f"Configuration file not found: {config_file_path}")
            return False

        try:
            with open(config_file_path) as f:
                config = json.load(f)

            # Check if certificates exist
            cert_path = Path("apple_credentials/certificates")
            app_cert = cert_path / "developerID_application.cer"
            installer_cert = cert_path / "developerID_installer.cer"

            if not app_cert.exists() or not installer_cert.exists():
                log_error("Certificate files not found in certificates directory")
                return False

            # Create temporary directory and copy certificates
            self.temp_dir = Path(tempfile.mkdtemp(prefix="r2midi_certs_"))

            self.cert_files["app"] = self.temp_dir / "developerID_application.cer"
            self.cert_files["installer"] = self.temp_dir / "developerID_installer.cer"

            # Copy certificates to temp location
            import shutil
            shutil.copy2(app_cert, self.cert_files["app"])
            shutil.copy2(installer_cert, self.cert_files["installer"])

            log_success("Certificates copied to secure temporary location")

            # Extract identities
            self.signing_identity = self._extract_identity_from_cert(
                self.cert_files["app"], "Application"
            )
            self.installer_identity = self._extract_identity_from_cert(
                self.cert_files["installer"], "Installer"
            )

            if self.signing_identity and self.installer_identity:
                log_success("Certificate identities extracted successfully")
                return True
            else:
                log_error("Failed to extract certificate identities")
                return False

        except (json.JSONDecodeError, KeyError) as e:
            log_error(f"Failed to load configuration: {e}")
            return False

    def setup_self_hosted(self):
        """Setup certificates for self-hosted runner"""
        log_info("Setting up certificates for self-hosted runner")

        # For self-hosted, try GitHub Actions method first, then local
        if all(os.getenv(var) for var in ["APPLE_DEVELOPER_ID_APPLICATION_CERT", 
                                          "APPLE_DEVELOPER_ID_INSTALLER_CERT"]):
            log_info("Using environment variables (GitHub Actions style)")
            return self.setup_github_actions()
        else:
            log_info("Using local configuration file")
            config_file = Path("apple_credentials/config/app_config.json")
            return self.setup_local(config_file)

    def _extract_identity_from_cert(self, cert_file, cert_type):
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

    def sign_app(self, app_path, entitlements_file=None):
        """Sign application without keychain interaction"""
        if not self.signing_identity:
            log_error("No signing identity available")
            return False

        log_info(f"Signing app: {app_path}")

        # Create temporary entitlements if not provided
        if not entitlements_file:
            entitlements_file = self.temp_dir / "entitlements.plist"
            entitlements_content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>"""
            entitlements_file.write_text(entitlements_content)

        try:
            # Use codesign with the extracted identity
            cmd = [
                "codesign", "--force", "--options", "runtime",
                "--entitlements", str(entitlements_file),
                "--deep", "--timestamp",
                "--sign", self.signing_identity,
                str(app_path)
            ]

            # Set environment to avoid keychain prompts
            env = os.environ.copy()
            env["CODESIGN_ALLOCATE"] = "/usr/bin/codesign_allocate"

            result = subprocess.run(cmd, capture_output=True, text=True, env=env)

            if result.returncode == 0:
                log_success(f"Successfully signed: {app_path}")
                return True
            else:
                log_error(f"Signing failed: {result.stderr}")
                return False

        except Exception as e:
            log_error(f"Error during signing: {e}")
            return False

    def get_credentials(self):
        """Get credentials for PKG builder"""
        if not os.getenv("GITHUB_ACTIONS"):
            # Local credentials
            config_file = Path("apple_credentials/config/app_config.json")
            if config_file.exists():
                with open(config_file) as f:
                    config = json.load(f)
                apple_dev = config["apple_developer"]
                return {
                    "apple_id": apple_dev["apple_id"],
                    "apple_password": apple_dev["app_specific_password"],
                    "team_id": apple_dev["team_id"],
                    "signing_identity": self.signing_identity,
                    "installer_identity": self.installer_identity
                }
        else:
            # GitHub Actions credentials
            return {
                "apple_id": os.getenv("APPLE_ID"),
                "apple_password": os.getenv("APPLE_ID_PASSWORD"),
                "team_id": os.getenv("APPLE_TEAM_ID"),
                "signing_identity": self.signing_identity,
                "installer_identity": self.installer_identity
            }

        return None

def main():
    parser = argparse.ArgumentParser(description="Secure certificate manager")
    parser.add_argument("action", choices=["setup", "sign", "get-credentials"],
                       help="Action to perform")
    parser.add_argument("--app-path", help="Path to app bundle to sign")
    parser.add_argument("--output-credentials", help="Output file for credentials JSON")

    args = parser.parse_args()

    with SecureCertificateManager() as cert_manager:
        if args.action == "setup":
            # Determine environment and setup accordingly
            if os.getenv("GITHUB_ACTIONS"):
                if "self-hosted" in os.getenv("RUNNER_NAME", "").lower():
                    success = cert_manager.setup_self_hosted()
                else:
                    success = cert_manager.setup_github_actions()
            else:
                config_file = Path("apple_credentials/config/app_config.json")
                success = cert_manager.setup_local(config_file)

            if success:
                log_success("Certificate setup completed successfully")
                sys.exit(0)
            else:
                log_error("Certificate setup failed")
                sys.exit(1)

        elif args.action == "sign":
            if not args.app_path:
                log_error("--app-path required for sign action")
                sys.exit(1)

            # Setup first
            if os.getenv("GITHUB_ACTIONS"):
                if "self-hosted" in os.getenv("RUNNER_NAME", "").lower():
                    success = cert_manager.setup_self_hosted()
                else:
                    success = cert_manager.setup_github_actions()
            else:
                config_file = Path("apple_credentials/config/app_config.json")
                success = cert_manager.setup_local(config_file)

            if not success:
                log_error("Certificate setup failed")
                sys.exit(1)

            # Sign the app
            if cert_manager.sign_app(args.app_path):
                log_success("App signing completed successfully")
                sys.exit(0)
            else:
                log_error("App signing failed")
                sys.exit(1)

        elif args.action == "get-credentials":
            # Setup first
            if os.getenv("GITHUB_ACTIONS"):
                if "self-hosted" in os.getenv("RUNNER_NAME", "").lower():
                    success = cert_manager.setup_self_hosted()
                else:
                    success = cert_manager.setup_github_actions()
            else:
                config_file = Path("apple_credentials/config/app_config.json")
                success = cert_manager.setup_local(config_file)

            if not success:
                log_error("Certificate setup failed")
                sys.exit(1)

            credentials = cert_manager.get_credentials()
            if credentials:
                if args.output_credentials:
                    with open(args.output_credentials, 'w') as f:
                        json.dump(credentials, f, indent=2)
                    log_success(f"Credentials saved to: {args.output_credentials}")
                else:
                    print(json.dumps(credentials, indent=2))
                sys.exit(0)
            else:
                log_error("Failed to get credentials")
                sys.exit(1)

if __name__ == "__main__":
    main()
