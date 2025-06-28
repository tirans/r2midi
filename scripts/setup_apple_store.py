#!/usr/bin/env python3
"""
R2MIDI Apple Store Setup - Two-Phase Automated Script
====================================================

Phase 1: Setup Instructions and Local Folder Creation
Phase 2: Automated Processing and GitHub Secrets Creation/Update

This script separates manual setup from automated processing, keeping
sensitive files local and automatically creating or updating GitHub secrets via API.
If secrets already exist, they will be updated with new values.

Requirements:
- macOS (for certificate management)
- Active Apple Developer Account
- GitHub Personal Access Token with repo permissions
- Python 3.8+

Usage:
    python scripts/setup_apple_store.py phase1    # Setup instructions and folder structure
    python scripts/setup_apple_store.py phase2    # Automated processing and GitHub integration
"""

import base64
import getpass
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import requests


class Colors:
    """ANSI color codes for terminal output."""

    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"


class AppleStoreSetup:
    """Two-phase Apple Store setup manager."""

    def __init__(self):
        self.repo_root = Path(__file__).parent.parent
        self.credentials_dir = self.repo_root / "apple_credentials"
        self.github_repo = None
        self.secrets = {}

    def print_header(self, text: str):
        """Print a formatted header."""
        print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*70}")
        print(f"{text}")
        print(f"{'='*70}{Colors.ENDC}")

    def print_phase(self, phase: int, title: str):
        """Print a phase header."""
        print(f"\n{Colors.CYAN}{Colors.BOLD}Phase {phase}: {title}{Colors.ENDC}")
        print(f"{Colors.CYAN}{'-'*50}{Colors.ENDC}")

    def print_step(self, step: str):
        """Print a step header."""
        print(f"\n{Colors.BLUE}{Colors.BOLD}{step}{Colors.ENDC}")
        print(f"{Colors.BLUE}{'-'*30}{Colors.ENDC}")

    def print_success(self, text: str):
        """Print success message."""
        print(f"{Colors.GREEN}✅ {text}{Colors.ENDC}")

    def print_warning(self, text: str):
        """Print warning message."""
        print(f"{Colors.WARNING}⚠️  {text}{Colors.ENDC}")

    def print_error(self, text: str):
        """Print error message."""
        print(f"{Colors.FAIL}❌ {text}{Colors.ENDC}")

    def print_info(self, text: str):
        """Print info message."""
        print(f"{Colors.BLUE}ℹ️  {text}{Colors.ENDC}")

    def create_credentials_folder_structure(self):
        """Create the local credentials folder structure."""
        self.print_step("Creating Local Credentials Folder Structure")

        # Create main credentials directory
        self.credentials_dir.mkdir(exist_ok=True)

        # Create subdirectories
        subdirs = ["certificates", "app_store_connect", "config", "temp"]

        for subdir in subdirs:
            (self.credentials_dir / subdir).mkdir(exist_ok=True)
            self.print_success(f"Created: {self.credentials_dir / subdir}")

        # Create .gitignore for the credentials directory
        gitignore_content = """# Apple Developer Credentials - NEVER COMMIT THESE FILES
*
!.gitignore
!README.md

# This folder contains sensitive Apple Developer certificates,
# API keys, and credentials that should NEVER be committed to git.
# The automated script will process these files locally.
"""

        gitignore_path = self.credentials_dir / ".gitignore"
        with open(gitignore_path, "w") as f:
            f.write(gitignore_content)
        self.print_success(f"Created: {gitignore_path}")

        # Update main .gitignore to ensure credentials folder is ignored
        main_gitignore = self.repo_root / ".gitignore"
        gitignore_entry = (
            "\n# Apple Developer Credentials (local only)\napple_credentials/\n"
        )

        if main_gitignore.exists():
            with open(main_gitignore, "r") as f:
                content = f.read()
            if "apple_credentials/" not in content:
                with open(main_gitignore, "a") as f:
                    f.write(gitignore_entry)
                self.print_success("Updated main .gitignore")
        else:
            with open(main_gitignore, "w") as f:
                f.write(gitignore_entry)
            self.print_success("Created main .gitignore")

    def create_config_template(self):
        """Create configuration template file."""
        self.print_step("Creating Configuration Template")

        config_template = {
            "app_info": {
                "bundle_id_prefix": "com.yourcompany",
                "server_display_name": "R2MIDI Server",
                "client_display_name": "R2MIDI Client",
                "author_name": "Your Name",
                "author_email": "your.email@domain.com",
            },
            "apple_developer": {
                "apple_id": "your.apple.id@domain.com",
                "team_id": "YOUR_TEAM_ID",
                "app_specific_password": "your-app-specific-password",
                "app_store_connect_key_id": "YOUR_KEY_ID",
                "app_store_connect_issuer_id": "YOUR_ISSUER_ID",
                "app_store_connect_api_key_path": "/path/to/AuthKey_KEYID.p8",
            },
            "build_options": {
                "enable_app_store_build": True,
                "enable_app_store_submission": True,
                "enable_notarization": True,
            },
            "github": {
                "repository": "tirans/r2midi",
                "personal_access_token": "ghp_your_token_here",
            },
        }

        config_path = self.credentials_dir / "config" / "app_config.json"
        with open(config_path, "w") as f:
            json.dump(config_template, f, indent=2)

        self.print_success(f"Created: {config_path}")

    def create_setup_instructions(self):
        """Create detailed setup instructions."""
        self.print_step("Creating Setup Instructions")

        instructions = """# R2MIDI Apple Store Setup Instructions

## 📋 Prerequisites Completed
✅ Local credentials folder structure created
✅ Configuration template generated
✅ .gitignore files configured

## 🍎 PHASE 1: Manual Setup Tasks

### Task 1: Apple Developer Account
1. Join Apple Developer Program: https://developer.apple.com/programs/ ($99/year)
2. Get your Team ID from: https://developer.apple.com/account/
3. Create app-specific password at: https://appleid.apple.com/

### Task 2: Download Certificates
Go to: https://developer.apple.com/account/resources/certificates/list

Create and download these certificates:
1. **Developer ID Application** (for direct distribution)
2. **3rd Party Mac Developer Application** (for App Store)
3. **3rd Party Mac Developer Installer** (for App Store packages)

**How to create certificates:**
1. Click "+" to create new certificate
2. Select certificate type
3. Create CSR in Keychain Access:
   - Keychain Access → Certificate Assistant → Request Certificate from CA
   - Save to Desktop
4. Upload CSR file
5. Download .cer file
6. **PLACE .cer files in: `apple_credentials/certificates/`**

### Task 3: App Store Connect API Key
1. Go to: https://appstoreconnect.apple.com/access/api
2. Create new API key with "Developer" role
3. Download .p8 file immediately (can't download again!)
4. Note the Key ID and Issuer ID
5. **PLACE .p8 file in: `apple_credentials/app_store_connect/`**

### Task 4: GitHub Personal Access Token
1. Go to: https://github.com/settings/tokens
2. Create new token (classic)
3. Select scopes: `repo` (full control)
4. Copy the token

### Task 5: Update Configuration
Edit: `apple_credentials/config/app_config.json`
- Fill in all your information
- Use the Team ID from Apple Developer
- Use the app-specific password you created
- Add your GitHub token

## 📁 Expected File Structure After Setup

```
apple_credentials/
├── certificates/
│   ├── DeveloperIDApplication.cer
│   ├── MacDeveloperApplication.cer
│   └── MacDeveloperInstaller.cer
├── app_store_connect/
│   └── AuthKey_XXXXXXXXXX.p8
├── config/
│   └── app_config.json (filled with your info)
└── temp/ (used by automation)
```

## ✅ When Ready
Run: `python scripts/setup_apple_store.py phase2`

This will:
- Install certificates to Keychain
- Export and encode certificates
- Create all GitHub secrets automatically
- Test the configuration
"""

        readme_path = self.credentials_dir / "README.md"
        with open(readme_path, "w") as f:
            f.write(instructions)

        self.print_success(f"Created: {readme_path}")

    def phase1_setup(self):
        """Phase 1: Create folder structure and instructions."""
        self.print_header("R2MIDI Apple Store Setup - Phase 1")

        print("This phase creates the local folder structure and provides")
        print("detailed instructions for the manual setup tasks.")

        self.create_credentials_folder_structure()
        self.create_config_template()
        self.create_setup_instructions()

        self.print_header("Phase 1 Complete!")

        print(f"\n{Colors.GREEN}✅ Local setup structure created{Colors.ENDC}")
        print(f"\n📋 Next steps:")
        print(
            f"1. Read the instructions: {Colors.CYAN}{self.credentials_dir}/README.md{Colors.ENDC}"
        )
        print(
            f"2. Download certificates to: {Colors.CYAN}{self.credentials_dir}/certificates/{Colors.ENDC}"
        )
        print(
            f"3. Download App Store Connect API key to: {Colors.CYAN}{self.credentials_dir}/app_store_connect/{Colors.ENDC}"
        )
        print(
            f"4. Edit configuration: {Colors.CYAN}{self.credentials_dir}/config/app_config.json{Colors.ENDC}"
        )
        print(
            f"5. Run: {Colors.BOLD}python scripts/setup_apple_store.py phase2{Colors.ENDC}"
        )

        # Open the credentials folder in Finder
        if sys.platform == "darwin":
            try:
                subprocess.run(["open", str(self.credentials_dir)], check=True)
                self.print_success("Opened credentials folder in Finder")
            except:
                pass

    def load_config(self) -> dict:
        """Load configuration from the local config file."""
        config_path = self.credentials_dir / "config" / "app_config.json"

        if not config_path.exists():
            self.print_error("Configuration file not found. Run phase1 first.")
            sys.exit(1)

        try:
            with open(config_path, "r") as f:
                config = json.load(f)
            return config
        except Exception as e:
            self.print_error(f"Failed to load configuration: {e}")
            sys.exit(1)

    def verify_files(self, config: dict) -> bool:
        """Verify all required files are present."""
        self.print_step("Verifying Required Files")

        errors = []

        # Check certificates
        cert_dir = self.credentials_dir / "certificates"
        cert_files = list(cert_dir.glob("*.cer"))

        if len(cert_files) < 2:
            errors.append("Need at least 2 .cer certificate files")
        else:
            self.print_success(f"Found {len(cert_files)} certificate files")

        # Check App Store Connect API key
        api_dir = self.credentials_dir / "app_store_connect"
        p8_files = list(api_dir.glob("*.p8"))

        if len(p8_files) < 1:
            errors.append("Need at least 1 .p8 API key file")
        else:
            self.print_success(f"Found {len(p8_files)} API key files")

        # Check config completeness
        required_fields = [
            ("app_info", "bundle_id_prefix"),
            ("apple_developer", "apple_id"),
            ("apple_developer", "team_id"),
            ("github", "personal_access_token"),
        ]

        # Check for App Store Connect API key fields
        api_key_fields = [
            ("apple_developer", "app_store_connect_key_id"),
            ("apple_developer", "app_store_connect_issuer_id"),
            ("apple_developer", "app_store_connect_api_key_path"),
        ]

        missing_api_key_fields = []
        for section, field in api_key_fields:
            value = config.get(section, {}).get(field, "")
            if not value or value.startswith(("your", "YOUR", "/path/to")):
                missing_api_key_fields.append(f"{section}.{field}")

        if missing_api_key_fields:
            self.print_warning("App Store Connect API key fields not filled:")
            for field in missing_api_key_fields:
                self.print_warning(f"  - {field}")
            self.print_warning(
                "Apple ID authentication may fail with 401 error in CI/CD environments."
            )
            self.print_warning(
                "See docs/apple_auth_troubleshooting.md for instructions on setting up API key authentication."
            )

        for section, field in required_fields:
            value = config.get(section, {}).get(field, "")
            if not value or value.startswith("your"):
                errors.append(f"Configuration field {section}.{field} not filled")

        if errors:
            for error in errors:
                self.print_error(error)
            return False

        self.print_success("All required files and configuration present")
        return True

    def install_certificates(self):
        """Install certificates from .cer files to Keychain."""
        self.print_step("Installing Certificates to Keychain")

        cert_dir = self.credentials_dir / "certificates"
        cert_files = list(cert_dir.glob("*.cer"))

        for cert_file in cert_files:
            try:
                subprocess.run(
                    ["security", "import", str(cert_file), "-k", "login.keychain"],
                    check=True,
                    capture_output=True,
                )
                self.print_success(f"Installed: {cert_file.name}")
            except subprocess.CalledProcessError as e:
                self.print_warning(
                    f"Certificate {cert_file.name} might already be installed"
                )

    def export_certificates(self) -> dict:
        """Export certificates from Keychain as base64 encoded P12."""
        self.print_step("Exporting Certificates from Keychain")

        exports = {}

        # Find available certificates
        try:
            result = subprocess.run(
                ["security", "find-identity", "-v", "-p", "codesigning"],
                capture_output=True,
                text=True,
                check=True,
            )

            certificates = {}
            for line in result.stdout.split("\n"):
                if "Developer ID Application:" in line:
                    match = re.search(r'"([^"]*Developer ID Application[^"]*)"', line)
                    if match:
                        certificates["developer_id"] = match.group(1)

                elif "3rd Party Mac Developer Application:" in line:
                    match = re.search(
                        r'"([^"]*3rd Party Mac Developer Application[^"]*)"', line
                    )
                    if match:
                        certificates["app_store"] = match.group(1)

        except subprocess.CalledProcessError:
            self.print_error("Failed to find certificates in keychain")
            return {}

        # Export certificates
        temp_dir = self.credentials_dir / "temp"

        for cert_type, cert_name in certificates.items():
            self.print_info(f"Exporting {cert_type} certificate...")

            # Generate a random password for export instead of using a hardcoded one
            import random
            import string

            export_password = "".join(
                random.choice(string.ascii_letters + string.digits) for _ in range(24)
            )
            temp_file = temp_dir / f"{cert_type}_cert.p12"

            try:
                result = subprocess.run(
                    [
                        "security",
                        "export",
                        "-k",
                        "login.keychain",
                        "-t",
                        "identities",
                        "-f",
                        "pkcs12",
                        "-o",
                        str(temp_file),
                        "-P",
                        export_password,
                    ],
                    input=f'"{cert_name}"\n',
                    text=True,
                    capture_output=True,
                )

                if result.returncode == 0:
                    with open(temp_file, "rb") as f:
                        cert_data = f.read()

                    encoded_cert = base64.b64encode(cert_data).decode("utf-8")

                    if cert_type == "developer_id":
                        exports["APPLE_CERTIFICATE_P12"] = encoded_cert
                        exports["APPLE_CERTIFICATE_PASSWORD"] = export_password
                    elif cert_type == "app_store":
                        exports["APPLE_APP_STORE_CERTIFICATE_P12"] = encoded_cert
                        exports["APPLE_APP_STORE_CERTIFICATE_PASSWORD"] = (
                            export_password
                        )

                    temp_file.unlink()  # Clean up
                    self.print_success(f"Exported {cert_type} certificate")
                else:
                    self.print_error(f"Failed to export {cert_type} certificate")

            except Exception as e:
                self.print_error(f"Error exporting {cert_type} certificate: {e}")

        return exports

    def process_app_store_connect_api_key(self, config=None) -> dict:
        """Process App Store Connect API key.

        Args:
            config: Optional configuration dictionary containing API key information

        Returns:
            Dictionary with API key and key ID
        """
        self.print_step("Processing App Store Connect API Key")

        # Check if config has API key information
        if config and "apple_developer" in config:
            apple_dev = config["apple_developer"]
            key_id = apple_dev.get("app_store_connect_key_id")
            api_key_path = apple_dev.get("app_store_connect_api_key_path")

            if key_id and api_key_path and os.path.exists(api_key_path):
                self.print_info(f"Using API key from config: {api_key_path}")
                try:
                    with open(api_key_path, "rb") as f:
                        api_key_data = f.read()

                    encoded_key = base64.b64encode(api_key_data).decode("utf-8")
                    self.print_success(f"Processed API key: {key_id}")

                    return {
                        "APP_STORE_CONNECT_API_KEY": encoded_key,
                        "APP_STORE_CONNECT_KEY_ID": key_id,
                    }
                except Exception as e:
                    self.print_error(f"Failed to process API key from config: {e}")
                    # Continue to try finding API key in the default location

        # Fallback to finding API key in the default location
        api_dir = self.credentials_dir / "app_store_connect"
        p8_files = list(api_dir.glob("*.p8"))

        if not p8_files:
            self.print_error("No .p8 API key files found")
            return {}

        p8_file = p8_files[0]

        # Extract Key ID from filename (AuthKey_XXXXXXXXXX.p8)
        key_id_match = re.search(r"AuthKey_([^.]+)\.p8", p8_file.name)
        if not key_id_match:
            self.print_error("Could not extract Key ID from filename")
            return {}

        key_id = key_id_match.group(1)

        # Read and encode the API key
        try:
            with open(p8_file, "rb") as f:
                api_key_data = f.read()

            encoded_key = base64.b64encode(api_key_data).decode("utf-8")

            self.print_success(f"Processed API key: {key_id}")

            return {
                "APP_STORE_CONNECT_API_KEY": encoded_key,
                "APP_STORE_CONNECT_KEY_ID": key_id,
            }

        except Exception as e:
            self.print_error(f"Failed to process API key: {e}")
            return {}

    def create_github_secrets(self, secrets: dict, github_token: str) -> bool:
        """Create new GitHub secrets or update existing ones via the GitHub API.

        This method checks if each secret already exists in the repository and either
        creates a new secret or updates the existing one. It provides detailed feedback
        about which secrets were created and which were updated.

        Args:
            secrets: Dictionary of secret names and values to create or update
            github_token: GitHub personal access token with repo permissions

        Returns:
            bool: True if all secrets were successfully created or updated, False otherwise
        """
        self.print_step("Creating/Updating GitHub Secrets via API")

        headers = {
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
        }

        # Get repository public key for encryption
        public_key_url = f"https://api.github.com/repos/{self.github_repo}/actions/secrets/public-key"

        try:
            response = requests.get(public_key_url, headers=headers)
            response.raise_for_status()
            public_key_data = response.json()

            public_key = public_key_data["key"]
            key_id = public_key_data["key_id"]

        except Exception as e:
            self.print_error(f"Failed to get repository public key: {e}")
            return False

        # Encrypt secrets using PyNaCl
        try:
            from nacl import encoding, public
        except ImportError:
            self.print_error("PyNaCl not installed. Run: pip install PyNaCl")
            return False

        def encrypt_secret(secret_value: str) -> str:
            """Encrypt a secret using the repository's public key."""
            public_key_obj = public.PublicKey(
                public_key.encode("utf-8"), encoding.Base64Encoder()
            )
            sealed_box = public.SealedBox(public_key_obj)
            encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
            return base64.b64encode(encrypted).decode("utf-8")

        # Define secrets URL
        secrets_url = f"https://api.github.com/repos/{self.github_repo}/actions/secrets"

        # Check which secrets already exist
        existing_secrets = {}
        try:
            response = requests.get(secrets_url, headers=headers)
            if response.status_code == 200:
                secrets_data = response.json()
                for secret in secrets_data.get("secrets", []):
                    existing_secrets[secret["name"]] = True
        except Exception as e:
            self.print_warning(f"Could not retrieve existing secrets: {e}")
            # Continue anyway, we'll determine if secrets exist based on response codes

        created_count = 0
        updated_count = 0

        for secret_name, secret_value in secrets.items():
            try:
                encrypted_value = encrypt_secret(str(secret_value))

                secret_data = {"encrypted_value": encrypted_value, "key_id": key_id}

                # Check if secret already exists before making the API call
                secret_exists = secret_name in existing_secrets
                operation = "Updating" if secret_exists else "Creating"
                self.print_info(f"{operation} secret: {secret_name}...")

                response = requests.put(
                    f"{secrets_url}/{secret_name}", headers=headers, json=secret_data
                )

                if response.status_code == 201:
                    self.print_success(f"Created new secret: {secret_name}")
                    created_count += 1
                elif response.status_code == 204:
                    self.print_success(f"Updated existing secret: {secret_name}")
                    updated_count += 1
                else:
                    self.print_error(
                        f"Failed to {operation.lower()} secret {secret_name}: {response.status_code}"
                    )

            except Exception as e:
                self.print_error(f"Error creating/updating secret {secret_name}: {e}")

        success_count = created_count + updated_count
        if success_count == len(secrets):
            self.print_success(
                f"All secrets processed successfully! Created: {created_count}, Updated: {updated_count}"
            )
            return True
        else:
            self.print_warning(
                f"Processed {success_count}/{len(secrets)} secrets. Created: {created_count}, Updated: {updated_count}"
            )
            return False

    def cleanup_temp_files(self):
        """Clean up temporary files."""
        temp_dir = self.credentials_dir / "temp"
        if temp_dir.exists():
            for file in temp_dir.glob("*"):
                if file.is_file():
                    file.unlink()
            self.print_success("Cleaned up temporary files")

    def phase2_processing(self):
        """Phase 2: Automated processing and GitHub integration."""
        self.print_header("R2MIDI Apple Store Setup - Phase 2")

        print("This phase processes your local credentials and automatically")
        print("creates GitHub secrets for the signing workflow.")

        # Load configuration
        config = self.load_config()

        # Set GitHub repository from config
        self.github_repo = config["github"]["repository"]

        # Verify all files are present
        if not self.verify_files(config):
            self.print_error(
                "Missing required files or configuration. Check phase1 setup."
            )
            sys.exit(1)

        # Install certificates
        self.install_certificates()

        # Build secrets dictionary from configuration
        app_info = config["app_info"]
        apple_dev = config["apple_developer"]
        build_opts = config["build_options"]

        secrets = {
            # App information
            "APP_BUNDLE_ID_PREFIX": app_info["bundle_id_prefix"],
            "APP_DISPLAY_NAME_SERVER": app_info["server_display_name"],
            "APP_DISPLAY_NAME_CLIENT": app_info["client_display_name"],
            "APP_AUTHOR_NAME": app_info["author_name"],
            "APP_AUTHOR_EMAIL": app_info["author_email"],
            # Apple Developer
            "APPLE_ID": apple_dev["apple_id"],
            "APPLE_TEAM_ID": apple_dev["team_id"],
            "APPLE_ID_PASSWORD": apple_dev["app_specific_password"],
            # Build options
            "ENABLE_APP_STORE_BUILD": str(build_opts["enable_app_store_build"]).lower(),
            "ENABLE_APP_STORE_SUBMISSION": str(
                build_opts["enable_app_store_submission"]
            ).lower(),
            "ENABLE_NOTARIZATION": str(build_opts["enable_notarization"]).lower(),
        }

        # Add Issuer ID if provided in config
        if "app_store_connect_issuer_id" in config.get("apple_developer", {}):
            secrets["APP_STORE_CONNECT_ISSUER_ID"] = apple_dev[
                "app_store_connect_issuer_id"
            ]

        # Export certificates
        cert_secrets = self.export_certificates()
        secrets.update(cert_secrets)

        # Process App Store Connect API key
        api_secrets = self.process_app_store_connect_api_key(config)
        secrets.update(api_secrets)

        # Get GitHub token
        github_token = config["github"]["personal_access_token"]

        if github_token.startswith("github"):
            # Create or update GitHub secrets
            if self.create_github_secrets(secrets, github_token):
                self.cleanup_temp_files()

                self.print_header("Phase 2 Complete!")

                print(
                    f"\n{Colors.GREEN}✅ All GitHub secrets created or updated successfully!{Colors.ENDC}"
                )
                print(f"\n🚀 Next steps:")
                print(f"1. Test the workflow: Push to master branch")
                print(
                    f"2. Check GitHub Actions: https://github.com/{self.github_repo}/actions"
                )
                print(
                    f"3. Look for signed releases in: https://github.com/{self.github_repo}/releases"
                )

                print(f"\n🔒 Security reminder:")
                print(
                    f"- Local credentials remain in: {Colors.CYAN}{self.credentials_dir}{Colors.ENDC}"
                )
                print(f"- These files are git-ignored and stay on your machine")
                print(f"- GitHub secrets are encrypted and secure")
            else:
                self.print_error("Failed to create some GitHub secrets")
                sys.exit(1)
        else:
            self.print_error("Invalid GitHub token. Must start with 'ghp_'")
            sys.exit(1)

    def run(self, phase: str):
        """Run the specified phase."""
        if phase == "phase1":
            self.phase1_setup()
        elif phase == "phase2":
            self.phase2_processing()
        else:
            print("Usage: python scripts/setup_apple_store.py [phase1|phase2]")
            print("\nphase1: Create folder structure and setup instructions")
            print("phase2: Process credentials and create GitHub secrets")
            sys.exit(1)


def main():
    """Main entry point."""
    if len(sys.argv) != 2:
        print("Usage: python scripts/setup_apple_store.py [phase1|phase2]")
        sys.exit(1)

    phase = sys.argv[1].lower()
    setup = AppleStoreSetup()

    try:
        setup.run(phase)
    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Setup interrupted by user{Colors.ENDC}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.FAIL}Setup failed: {e}{Colors.ENDC}")
        sys.exit(1)


if __name__ == "__main__":
    main()
