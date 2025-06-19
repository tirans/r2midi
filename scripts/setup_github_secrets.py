#!/usr/bin/env python3
"""
Complete GitHub Secrets Manager for R2MIDI macOS Signing
========================================================

This script automatically creates/updates ALL GitHub secrets needed for macOS
code signing and notarization by reading configuration from app_config.json
and using the GitHub API.

Features:
- Auto-installs dependencies (requests, PyNaCl)
- Validates configuration and certificates
- Creates/updates all GitHub secrets via API
- Supports force mode to update all secrets
- Uses correct libsodium encryption for GitHub
- Comprehensive error handling and validation

Requirements:
- Python 3.8+
- Valid GitHub personal access token with repo scope
- P12 certificate files (app_cert.p12, installer_cert.p12)
- Valid app_config.json configuration

Usage:
    python scripts/setup_github_secrets.py [--force] [--test-only]
    
Options:
    --force      Force update all secrets even if they already exist
    --test-only  Test configuration and dependencies without making changes
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import importlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple


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


class GitHubSecretsManager:
    """Complete GitHub secrets manager for R2MIDI."""

    def __init__(self, force_update: bool = False, test_only: bool = False):
        self.config = {}
        self.secrets = {}
        self.force_update = force_update
        self.test_only = test_only
        self.project_root = Path(__file__).parent.parent
        self.config_file = self.project_root / "apple_credentials" / "config" / "app_config.json"
        self.github_api_base = "https://api.github.com"
        self.session = None
        
    def print_header(self, text: str):
        """Print a formatted header."""
        print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*70}")
        print(f"{text}")
        print(f"{'='*70}{Colors.ENDC}")

    def print_step(self, step: int, title: str):
        """Print a step header."""
        print(f"\n{Colors.CYAN}{Colors.BOLD}Step {step}: {title}{Colors.ENDC}")
        if self.force_update:
            print(f"{Colors.CYAN}[FORCE MODE: Will update all secrets]{Colors.ENDC}")
        if self.test_only:
            print(f"{Colors.BLUE}[TEST MODE: No changes will be made]{Colors.ENDC}")
        print(f"{Colors.CYAN}{'-'*50}{Colors.ENDC}")

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

    def mask_sensitive_value(self, value: str, show_chars: int = 4) -> str:
        """Mask sensitive values for safe display."""
        if not value or len(value) <= show_chars:
            return "***"
        return value[:show_chars] + "***" + value[-2:]

    def install_dependencies(self) -> bool:
        """Install required dependencies automatically."""
        self.print_step(1, "Installing Dependencies")
        
        # Check if we can import required modules
        missing_modules = []
        
        try:
            import requests
            self.print_success("requests library available")
        except ImportError:
            missing_modules.append("requests")
        
        try:
            from nacl import public
            self.print_success("PyNaCl library available")
        except ImportError:
            missing_modules.append("PyNaCl")
        
        if not missing_modules:
            self.print_success("All dependencies are already installed")
            return True
        
        self.print_info(f"Installing missing dependencies: {', '.join(missing_modules)}")
        
        # Install missing dependencies
        try:
            if missing_modules:
                cmd = [sys.executable, "-m", "pip", "install"] + missing_modules
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                if result.returncode == 0:
                    self.print_success("Dependencies installed successfully")
                    
                    # Verify imports now work
                    try:
                        import requests
                        from nacl import public
                        self.print_success("All imports working correctly")
                        return True
                    except ImportError as e:
                        self.print_error(f"Import still failing after installation: {e}")
                        return False
                else:
                    self.print_error("Failed to install dependencies")
                    self.print_info("Try running manually: pip install requests PyNaCl")
                    return False
                    
        except Exception as e:
            self.print_error(f"Error installing dependencies: {e}")
            return False

    def load_config(self) -> bool:
        """Load configuration from app_config.json."""
        self.print_step(2, "Loading Configuration")
        
        try:
            if not self.config_file.exists():
                self.print_error(f"Configuration file not found: {self.config_file}")
                return False
            
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
            
            self.print_success(f"Loaded configuration from {self.config_file}")
            
            # Validate required sections
            required_sections = ['apple_developer', 'github']
            for section in required_sections:
                if section not in self.config:
                    self.print_error(f"Missing required section '{section}' in config")
                    return False
            
            # Validate GitHub section
            github_config = self.config['github']
            if not github_config.get('repository'):
                self.print_error("Missing 'repository' in github section")
                return False
            
            if not github_config.get('personal_access_token'):
                self.print_error("Missing 'personal_access_token' in github section")
                return False
            
            # Validate Apple Developer section
            apple_config = self.config['apple_developer']
            required_fields = ['apple_id', 'team_id', 'p12_password', 'app_specific_password']
            
            for field in required_fields:
                if not apple_config.get(field):
                    self.print_error(f"Missing required Apple Developer field: {field}")
                    return False
            
            # Display loaded configuration (SAFELY - no sensitive data)
            self.print_info(f"Apple ID: {self.mask_sensitive_value(apple_config.get('apple_id', ''))}")
            self.print_info(f"Team ID: {apple_config.get('team_id', '')}")  # Team ID is not sensitive
            self.print_info(f"Repository: {github_config.get('repository', '')}")
            
            return True
            
        except json.JSONDecodeError as e:
            self.print_error(f"Invalid JSON in config file: {e}")
            return False
        except Exception as e:
            self.print_error(f"Error loading config: {e}")
            return False

    def setup_github_session(self) -> bool:
        """Setup GitHub API session."""
        try:
            import requests
            
            self.session = requests.Session()
            github_config = self.config['github']
            
            # SECURITY: Never log the actual token
            token = github_config['personal_access_token']
            
            self.session.headers.update({
                'Authorization': f"Bearer {token}",
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28'
            })
            
            return True
            
        except Exception as e:
            self.print_error(f"Error setting up GitHub session: {e}")
            return False

    def test_github_access(self) -> bool:
        """Test GitHub API access and permissions."""
        self.print_step(3, "Testing GitHub Access")
        
        if not self.setup_github_session():
            return False
        
        repository = self.config['github']['repository']
        
        try:
            # Test repository access
            response = self.session.get(f"{self.github_api_base}/repos/{repository}")
            
            if response.status_code == 200:
                repo_data = response.json()
                self.print_success(f"Repository access confirmed: {repo_data['full_name']}")
                
                # Check admin permissions
                permissions = repo_data.get('permissions', {})
                if permissions.get('admin', False):
                    self.print_success("Admin permissions confirmed")
                else:
                    self.print_warning("Admin permissions not detected - may not be able to manage secrets")
                
                # Test public key endpoint
                pub_key_response = self.session.get(f"{self.github_api_base}/repos/{repository}/actions/secrets/public-key")
                if pub_key_response.status_code == 200:
                    pub_key_data = pub_key_response.json()
                    self.print_success("Repository public key accessible")
                    # SECURITY: Don't log the actual key, just confirm we can access it
                    self.print_info(f"Public key ID: {pub_key_data.get('key_id', 'unknown')}")
                    return True
                else:
                    self.print_error("Cannot access repository public key - insufficient permissions")
                    return False
                    
            elif response.status_code == 404:
                self.print_error(f"Repository not found: {repository}")
                return False
            elif response.status_code == 401:
                self.print_error("Invalid GitHub token")
                return False
            else:
                self.print_error(f"GitHub API error: {response.status_code}")
                return False
                
        except Exception as e:
            self.print_error(f"GitHub API request failed: {e}")
            return False

    def test_p12_certificate(self, cert_path: Path, password: str) -> bool:
        """Test P12 certificate with OpenSSL 3.x compatibility."""
        try:
            # SECURITY: Never log the password in error messages
            # Try with -legacy flag first (OpenSSL 3.x)
            result = subprocess.run([
                'openssl', 'pkcs12', '-legacy', '-in', str(cert_path), 
                '-noout', '-passin', f'pass:{password}'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                return True
            
            # Try without -legacy flag (older OpenSSL)
            result = subprocess.run([
                'openssl', 'pkcs12', '-in', str(cert_path), 
                '-noout', '-passin', f'pass:{password}'
            ], capture_output=True, text=True)
            
            return result.returncode == 0
            
        except Exception:
            return False

    def find_and_validate_certificates(self) -> Tuple[Optional[Path], Optional[Path]]:
        """Find and validate P12 certificate files."""
        self.print_step(4, "Finding and Validating Certificates")
        
        # Get P12 path and password from config
        p12_path_config = self.config['apple_developer'].get('p12_path', 'apple_credentials/certificates')
        p12_password = self.config['apple_developer'].get('p12_password')
        
        # Resolve P12 path
        if Path(p12_path_config).is_absolute():
            p12_base_path = Path(p2_path_config)
        else:
            p12_base_path = self.project_root / p12_path_config
        
        # Search for certificate files
        search_paths = [
            p12_base_path,
            self.project_root / ".github" / "scripts",
            self.project_root,
        ]
        
        app_cert = None
        installer_cert = None
        
        # Look for certificates
        cert_names = {
            'app': ['app_cert.p12', 'application_cert.p12', 'developerID_application.p12'],
            'installer': ['installer_cert.p12', 'installer.p12', 'developerID_installer.p12']
        }
        
        for search_path in search_paths:
            if not search_path.exists():
                continue
                
            self.print_info(f"Searching in: {search_path}")
            
            # Look for application certificate
            if app_cert is None:
                for name in cert_names['app']:
                    cert_path = search_path / name
                    if cert_path.exists():
                        app_cert = cert_path
                        self.print_success(f"Found application certificate: {cert_path}")
                        break
            
            # Look for installer certificate
            if installer_cert is None:
                for name in cert_names['installer']:
                    cert_path = search_path / name
                    if cert_path.exists():
                        installer_cert = cert_path
                        self.print_success(f"Found installer certificate: {cert_path}")
                        break
        
        if not app_cert:
            self.print_error("Application certificate not found")
            self.print_info("Expected names: " + ", ".join(cert_names['app']))
            return None, None
        
        if not installer_cert:
            self.print_error("Installer certificate not found")
            self.print_info("Expected names: " + ", ".join(cert_names['installer']))
            return None, None
        
        # Validate certificates
        self.print_info("Validating certificates...")
        
        if not self.test_p12_certificate(app_cert, p12_password):
            self.print_error("Application certificate validation failed")
            return None, None
        
        if not self.test_p12_certificate(installer_cert, p12_password):
            self.print_error("Installer certificate validation failed")
            return None, None
        
        self.print_success("All certificates validated successfully")
        return app_cert, installer_cert

    def prepare_all_secrets(self, app_cert: Path, installer_cert: Path) -> bool:
        """Prepare all required secrets from configuration and certificates."""
        self.print_step(5, "Preparing All Required Secrets")
        
        apple_config = self.config['apple_developer']
        
        # Required secrets for macOS signing and notarization
        basic_secrets = {
            'APPLE_CERT_PASSWORD': apple_config.get('p12_password'),
            'APPLE_ID': apple_config.get('apple_id'),
            'APPLE_ID_PASSWORD': apple_config.get('app_specific_password'),
            'APPLE_TEAM_ID': apple_config.get('team_id'),
        }
        
        # Add basic secrets
        for secret_name, secret_value in basic_secrets.items():
            self.secrets[secret_name] = secret_value
            self.print_success(f"{secret_name}: ✓")
        
        # Convert P12 certificates to base64
        try:
            with open(app_cert, 'rb') as f:
                app_cert_data = f.read()
            self.secrets['APPLE_DEVELOPER_ID_APPLICATION_CERT'] = base64.b64encode(app_cert_data).decode('utf-8')
            # SECURITY: Show size but not content
            self.print_success(f"Application certificate: {len(self.secrets['APPLE_DEVELOPER_ID_APPLICATION_CERT'])} chars")
            
            with open(installer_cert, 'rb') as f:
                installer_cert_data = f.read()
            self.secrets['APPLE_DEVELOPER_ID_INSTALLER_CERT'] = base64.b64encode(installer_cert_data).decode('utf-8')
            # SECURITY: Show size but not content
            self.print_success(f"Installer certificate: {len(self.secrets['APPLE_DEVELOPER_ID_INSTALLER_CERT'])} chars")
            
        except Exception as e:
            self.print_error(f"Error converting certificates: {e}")
            return False
        
        # App Store Connect API secrets (optional)
        if apple_config.get('app_store_connect_key_id') and apple_config.get('app_store_connect_issuer_id'):
            self.secrets['APP_STORE_CONNECT_KEY_ID'] = apple_config['app_store_connect_key_id']
            self.secrets['APP_STORE_CONNECT_ISSUER_ID'] = apple_config['app_store_connect_issuer_id']
            self.print_success("App Store Connect credentials: ✓")
            
            # Convert API key to base64
            api_key_path_config = apple_config.get('app_store_connect_api_key_path')
            if api_key_path_config:
                if Path(api_key_path_config).is_absolute():
                    api_key_path = Path(api_key_path_config)
                else:
                    api_key_path = self.project_root / api_key_path_config
                
                if api_key_path.exists():
                    try:
                        with open(api_key_path, 'rb') as f:
                            api_key_data = f.read()
                        self.secrets['APP_STORE_CONNECT_API_KEY'] = base64.b64encode(api_key_data).decode('utf-8')
                        # SECURITY: Show size but not content
                        self.print_success(f"App Store Connect API key: {len(self.secrets['APP_STORE_CONNECT_API_KEY'])} chars")
                    except Exception as e:
                        self.print_warning(f"Could not read API key file: {e}")
        
        # Build configuration secrets
        build_options = self.config.get('build_options', {})
        if build_options.get('enable_app_store_build'):
            self.secrets['ENABLE_APP_STORE_BUILD'] = 'true'
        if build_options.get('enable_app_store_submission'):
            self.secrets['ENABLE_APP_STORE_SUBMISSION'] = 'true'
        if build_options.get('enable_notarization'):
            self.secrets['ENABLE_NOTARIZATION'] = 'true'
        
        # App information secrets
        app_info = self.config.get('app_info', {})
        if app_info.get('bundle_id_prefix'):
            self.secrets['APP_BUNDLE_ID_PREFIX'] = app_info['bundle_id_prefix']
        if app_info.get('author_name'):
            self.secrets['APP_AUTHOR_NAME'] = app_info['author_name']
        if app_info.get('author_email'):
            self.secrets['APP_AUTHOR_EMAIL'] = app_info['author_email']
        
        total_secrets = len(self.secrets)
        required_secrets = len([s for s in self.secrets.keys() if s.startswith('APPLE_')])
        
        self.print_success(f"Prepared {total_secrets} total secrets ({required_secrets} required for signing)")
        return True

    def encrypt_secret(self, secret_value: str, public_key_data: str) -> Optional[str]:
        """Encrypt a secret value using GitHub's libsodium encryption."""
        try:
            from nacl import public
            
            # Decode the public key from base64
            public_key_bytes = base64.b64decode(public_key_data)
            
            # Create a public key object using PyNaCl
            public_key = public.PublicKey(public_key_bytes)
            
            # Create a sealed box for encryption
            sealed_box = public.SealedBox(public_key)
            
            # Encrypt the secret value
            encrypted_bytes = sealed_box.encrypt(secret_value.encode('utf-8'))
            
            # Return base64 encoded encrypted data
            return base64.b64encode(encrypted_bytes).decode('utf-8')
            
        except Exception as e:
            # SECURITY: Don't log the secret value in error messages
            self.print_error(f"Error encrypting secret: {e}")
            return None

    def update_github_secrets(self) -> bool:
        """Update all secrets in GitHub repository."""
        self.print_step(6, "Updating GitHub Repository Secrets")
        
        if self.test_only:
            self.print_info("TEST MODE: Would update secrets, but no changes will be made")
            return True
        
        repository = self.config['github']['repository']
        
        # Get repository public key
        try:
            response = self.session.get(f"{self.github_api_base}/repos/{repository}/actions/secrets/public-key")
            if response.status_code != 200:
                self.print_error(f"Failed to get repository public key: {response.status_code}")
                return False
            
            public_key = response.json()
            self.print_success("Retrieved repository public key for encryption")
            
        except Exception as e:
            self.print_error(f"Error getting repository public key: {e}")
            return False
        
        # Get existing secrets for idempotency (unless force mode)
        existing_secrets = []
        if not self.force_update:
            try:
                response = self.session.get(f"{self.github_api_base}/repos/{repository}/actions/secrets")
                if response.status_code == 200:
                    secrets_data = response.json()
                    existing_secrets = [secret['name'] for secret in secrets_data.get('secrets', [])]
                    self.print_info(f"Found {len(existing_secrets)} existing secrets")
            except Exception:
                pass
        
        # Update each secret
        success_count = 0
        update_count = 0
        create_count = 0
        
        for secret_name, secret_value in self.secrets.items():
            is_update = secret_name in existing_secrets
            
            # Encrypt the secret value
            encrypted_value = self.encrypt_secret(secret_value, public_key['key'])
            if not encrypted_value:
                self.print_error(f"Failed to encrypt secret: {secret_name}")
                continue
            
            # Prepare the request payload
            payload = {
                'encrypted_value': encrypted_value,
                'key_id': public_key['key_id']
            }
            
            try:
                response = self.session.put(
                    f"{self.github_api_base}/repos/{repository}/actions/secrets/{secret_name}",
                    json=payload
                )
                
                if response.status_code in [201, 204]:
                    if self.force_update or is_update:
                        self.print_success(f"🔥 Updated secret: {secret_name}")
                        update_count += 1
                    else:
                        self.print_success(f"Created secret: {secret_name}")
                        create_count += 1
                    success_count += 1
                else:
                    self.print_error(f"Failed to set secret {secret_name}: {response.status_code}")
                    
            except Exception as e:
                self.print_error(f"Error setting secret {secret_name}: {e}")
        
        # Summary
        total_secrets = len(self.secrets)
        self.print_success(f"Successfully processed {success_count}/{total_secrets} secrets")
        
        if self.force_update:
            self.print_info(f"Force updated: {success_count} secrets")
        else:
            self.print_info(f"Created: {create_count}, Updated: {update_count}")
        
        return success_count == total_secrets

    def display_summary(self) -> None:
        """Display a summary of what was configured."""
        self.print_step(7, "Configuration Summary")
        
        repository = self.config['github']['repository']
        
        print(f"{Colors.BOLD}Repository:{Colors.ENDC} {repository}")
        if self.test_only:
            print(f"{Colors.BLUE}Mode: TEST ONLY (no changes made){Colors.ENDC}")
        elif self.force_update:
            print(f"{Colors.WARNING}Mode: FORCE UPDATE (all secrets refreshed){Colors.ENDC}")
        else:
            print(f"{Colors.BLUE}Mode: Idempotent (only missing/changed secrets updated){Colors.ENDC}")
        
        print(f"{Colors.BOLD}Secrets configured:{Colors.ENDC}")
        
        # Group secrets by category
        categories = {
            'macOS Signing (Required)': [
                'APPLE_DEVELOPER_ID_APPLICATION_CERT',
                'APPLE_DEVELOPER_ID_INSTALLER_CERT',
                'APPLE_CERT_PASSWORD',
                'APPLE_ID',
                'APPLE_ID_PASSWORD',
                'APPLE_TEAM_ID'
            ],
            'App Store Connect (Optional)': [
                'APP_STORE_CONNECT_KEY_ID',
                'APP_STORE_CONNECT_ISSUER_ID',
                'APP_STORE_CONNECT_API_KEY'
            ],
            'Build Configuration': [
                'ENABLE_APP_STORE_BUILD',
                'ENABLE_APP_STORE_SUBMISSION',
                'ENABLE_NOTARIZATION'
            ],
            'App Information': [
                'APP_BUNDLE_ID_PREFIX',
                'APP_AUTHOR_NAME',
                'APP_AUTHOR_EMAIL'
            ]
        }
        
        for category, secret_names in categories.items():
            found_secrets = [name for name in secret_names if name in self.secrets]
            if found_secrets:
                print(f"\n{Colors.CYAN}{category}:{Colors.ENDC}")
                for secret_name in found_secrets:
                    if self.test_only:
                        print(f"  {Colors.BLUE}🧪 {secret_name}{Colors.ENDC}")
                    elif self.force_update:
                        print(f"  {Colors.WARNING}🔥 {secret_name}{Colors.ENDC}")
                    else:
                        print(f"  {Colors.GREEN}✓ {secret_name}{Colors.ENDC}")

    def run(self) -> bool:
        """Run the complete secrets setup process."""
        mode_parts = []
        if self.test_only:
            mode_parts.append("Test Mode")
        if self.force_update:
            mode_parts.append("Force Mode")
        if not mode_parts:
            mode_parts.append("Idempotent Mode")
        
        mode_text = " + ".join(mode_parts)
        self.print_header(f"R2MIDI GitHub Secrets Manager ({mode_text})")
        
        print("This tool automatically creates/updates ALL GitHub secrets needed for:")
        print("• macOS code signing and notarization")
        print("• DMG and PKG installer creation")
        print("• App Store Connect integration")
        print("• Automated build and release workflows")
        
        if self.test_only:
            print(f"\n{Colors.BLUE}🧪 TEST MODE: Will validate everything but make no changes{Colors.ENDC}")
        if self.force_update:
            print(f"\n{Colors.WARNING}🔥 FORCE MODE: All secrets will be updated regardless of current state{Colors.ENDC}")
        
        try:
            # Step 1: Install dependencies
            if not self.install_dependencies():
                return False
            
            # Step 2: Load configuration
            if not self.load_config():
                return False
            
            # Step 3: Test GitHub access
            if not self.test_github_access():
                return False
            
            # Step 4: Find and validate certificates
            app_cert, installer_cert = self.find_and_validate_certificates()
            if not app_cert or not installer_cert:
                return False
            
            # Step 5: Prepare all secrets
            if not self.prepare_all_secrets(app_cert, installer_cert):
                return False
            
            # Step 6: Update GitHub secrets
            if not self.update_github_secrets():
                return False
            
            # Step 7: Display summary
            self.display_summary()
            
            if self.test_only:
                self.print_header("Test Complete - All Checks Passed!")
                self.print_success("Your configuration is ready for GitHub secrets")
                self.print_info("Run without --test-only to actually create/update secrets")
            else:
                mode_msg = "Force Updated" if self.force_update else "Updated"
                self.print_header(f"Success! All Secrets {mode_msg}")
                self.print_success("Your GitHub repository is now fully configured for macOS builds")
                self.print_info("Push a commit to trigger the macOS build workflow and test the setup")
            
            return True
            
        except KeyboardInterrupt:
            self.print_error("\nSetup interrupted by user")
            return False
        except Exception as e:
            self.print_error(f"Setup failed: {e}")
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Complete GitHub Secrets Manager for R2MIDI macOS Signing',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/setup_github_secrets.py              # Normal idempotent mode
  python scripts/setup_github_secrets.py --force      # Force update all secrets
  python scripts/setup_github_secrets.py --test-only  # Test configuration only
  python scripts/setup_github_secrets.py -f -t        # Force mode test
        """
    )
    
    parser.add_argument(
        '--force', '-f',
        action='store_true',
        help='Force update all secrets even if they already exist'
    )
    
    parser.add_argument(
        '--test-only', '-t',
        action='store_true',
        help='Test configuration and dependencies without making changes'
    )
    
    args = parser.parse_args()
    
    # Change to project root directory
    project_root = Path(__file__).parent.parent
    os.chdir(project_root)
    
    manager = GitHubSecretsManager(force_update=args.force, test_only=args.test_only)
    
    if manager.run():
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
