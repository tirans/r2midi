#!/usr/bin/env python3
"""
Test GitHub Secrets Manager Configuration
========================================

This script validates your configuration before running the actual secrets manager.
It checks all prerequisites without making any changes to GitHub.

Usage:
    python scripts/test_github_setup.py
"""

import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import requests
    from nacl import public
    DEPENDENCIES_OK = True
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    DEPENDENCIES_OK = False


class Colors:
    GREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    BLUE = "\033[94m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"


def print_success(text: str):
    print(f"{Colors.GREEN}✅ {text}{Colors.ENDC}")


def print_warning(text: str):
    print(f"{Colors.WARNING}⚠️  {text}{Colors.ENDC}")


def print_error(text: str):
    print(f"{Colors.FAIL}❌ {text}{Colors.ENDC}")


def print_info(text: str):
    print(f"{Colors.BLUE}ℹ️  {text}{Colors.ENDC}")


def test_dependencies():
    """Test if all required dependencies are available."""
    print(f"\n{Colors.BOLD}Testing Dependencies{Colors.ENDC}")
    print("-" * 30)
    
    if not DEPENDENCIES_OK:
        print_error("Missing required Python packages")
        print_info("Install with: pip install requests PyNaCl")
        return False
    
    print_success("All Python dependencies available")
    print_info("requests: HTTP client for GitHub API")
    print_info("PyNaCl: Encryption library for GitHub Secrets")
    return True


def test_configuration():
    """Test configuration file."""
    print(f"\n{Colors.BOLD}Testing Configuration{Colors.ENDC}")
    print("-" * 30)
    
    project_root = Path(__file__).parent.parent
    config_file = project_root / "apple_credentials" / "config" / "app_config.json"
    
    if not config_file.exists():
        print_error(f"Configuration file not found: {config_file}")
        return False
    
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        print_success("Configuration file loaded successfully")
        
        # Check required sections
        required_sections = ['apple_developer', 'github']
        for section in required_sections:
            if section not in config:
                print_error(f"Missing section '{section}' in configuration")
                return False
            print_success(f"Section '{section}' found")
        
        # Check Apple Developer configuration
        apple_config = config['apple_developer']
        required_apple_fields = ['apple_id', 'team_id', 'p12_password', 'app_specific_password']
        
        for field in required_apple_fields:
            if field in apple_config and apple_config[field]:
                print_success(f"Apple field '{field}': ✓")
            else:
                print_error(f"Missing or empty Apple field: {field}")
                return False
        
        # Check GitHub configuration
        github_config = config['github']
        if 'repository' in github_config and github_config['repository']:
            print_success(f"Repository: {github_config['repository']}")
        else:
            print_error("Missing GitHub repository")
            return False
        
        if 'personal_access_token' in github_config and github_config['personal_access_token']:
            token = github_config['personal_access_token']
            if token.startswith('github_pat_') or token.startswith('ghp_'):
                print_success("GitHub token format looks valid")
            else:
                print_warning("GitHub token format may be invalid")
        else:
            print_error("Missing GitHub personal access token")
            return False
        
        return True
        
    except json.JSONDecodeError as e:
        print_error(f"Invalid JSON in configuration: {e}")
        return False
    except Exception as e:
        print_error(f"Error reading configuration: {e}")
        return False


def test_certificates():
    """Test P12 certificate files."""
    print(f"\n{Colors.BOLD}Testing Certificates{Colors.ENDC}")
    print("-" * 30)
    
    project_root = Path(__file__).parent.parent
    
    # Load config to get password
    config_file = project_root / "apple_credentials" / "config" / "app_config.json"
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
        password = config['apple_developer']['p12_password']
    except:
        print_error("Could not load P12 password from configuration")
        return False
    
    # Search for certificates
    search_paths = [
        project_root / "apple_credentials" / "certificates",
        project_root / ".github" / "scripts",
        project_root,
    ]
    
    app_cert = None
    installer_cert = None
    
    for search_path in search_paths:
        if not search_path.exists():
            continue
        
        # Look for app certificate
        for name in ['app_cert.p12', 'application_cert.p12']:
            cert_path = search_path / name
            if cert_path.exists():
                app_cert = cert_path
                break
        
        # Look for installer certificate
        for name in ['installer_cert.p12', 'installer.p12']:
            cert_path = search_path / name
            if cert_path.exists():
                installer_cert = cert_path
                break
        
        if app_cert and installer_cert:
            break
    
    if not app_cert:
        print_error("Application certificate (app_cert.p12) not found")
        return False
    
    if not installer_cert:
        print_error("Installer certificate (installer_cert.p12) not found")
        return False
    
    print_success(f"Application certificate: {app_cert}")
    print_success(f"Installer certificate: {installer_cert}")
    
    # Test certificate validity
    def test_cert(cert_path, cert_type):
        try:
            # Try with legacy flag first
            result = subprocess.run([
                'openssl', 'pkcs12', '-legacy', '-in', str(cert_path),
                '-noout', '-passin', f'pass:{password}'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                print_success(f"{cert_type} certificate validation: ✓")
                return True
            
            # Try without legacy flag
            result = subprocess.run([
                'openssl', 'pkcs12', '-in', str(cert_path),
                '-noout', '-passin', f'pass:{password}'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                print_success(f"{cert_type} certificate validation: ✓")
                return True
            
            print_error(f"{cert_type} certificate validation failed")
            print_info(f"Error: {result.stderr.strip()}")
            return False
            
        except Exception as e:
            print_error(f"Error testing {cert_type} certificate: {e}")
            return False
    
    app_valid = test_cert(app_cert, "Application")
    installer_valid = test_cert(installer_cert, "Installer")
    
    return app_valid and installer_valid


def test_github_access():
    """Test GitHub API access."""
    print(f"\n{Colors.BOLD}Testing GitHub Access{Colors.ENDC}")
    print("-" * 30)
    
    if not DEPENDENCIES_OK:
        print_error("Cannot test GitHub access - missing dependencies")
        return False
    
    project_root = Path(__file__).parent.parent
    config_file = project_root / "apple_credentials" / "config" / "app_config.json"
    
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        github_config = config['github']
        repository = github_config['repository']
        token = github_config['personal_access_token']
        
        session = requests.Session()
        session.headers.update({
            'Authorization': f"Bearer {token}",
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28'
        })
        
        # Test repository access
        response = session.get(f"https://api.github.com/repos/{repository}")
        
        if response.status_code == 200:
            repo_data = response.json()
            print_success(f"Repository access: {repo_data['full_name']}")
            
            permissions = repo_data.get('permissions', {})
            if permissions.get('admin', False):
                print_success("Admin permissions confirmed")
            else:
                print_warning("Admin permissions not detected")
                print_info("You may not be able to manage repository secrets")
            
            # Test public key endpoint (needed for secrets encryption)
            pub_key_response = session.get(f"https://api.github.com/repos/{repository}/actions/secrets/public-key")
            if pub_key_response.status_code == 200:
                print_success("Repository public key accessible")
                pub_key_data = pub_key_response.json()
                print_info(f"Public key ID: {pub_key_data['key_id']}")
            else:
                print_warning("Could not access repository public key")
                print_info("This may indicate insufficient permissions for secrets management")
            
            return True
        elif response.status_code == 404:
            print_error(f"Repository not found: {repository}")
            return False
        elif response.status_code == 401:
            print_error("GitHub token authentication failed")
            print_info("Check if your personal access token is valid and has repo scope")
            return False
        else:
            print_error(f"GitHub API error: {response.status_code}")
            return False
        
    except Exception as e:
        print_error(f"Error testing GitHub access: {e}")
        return False


def main():
    """Main test function."""
    print(f"{Colors.BOLD}R2MIDI GitHub Secrets Configuration Test{Colors.ENDC}")
    print("=" * 50)
    
    tests = [
        ("Dependencies", test_dependencies),
        ("Configuration", test_configuration),
        ("Certificates", test_certificates),
        ("GitHub Access", test_github_access),
    ]
    
    all_passed = True
    
    for test_name, test_func in tests:
        try:
            if not test_func():
                all_passed = False
        except Exception as e:
            print_error(f"Test '{test_name}' failed with exception: {e}")
            all_passed = False
    
    print(f"\n{Colors.BOLD}Test Summary{Colors.ENDC}")
    print("=" * 30)
    
    if all_passed:
        print_success("All tests passed! Ready to run setup_github_secrets.py")
        print("")
        print_info("Run the secrets manager with:")
        print_info("  python scripts/setup_github_secrets.py")
        print_info("Or use the complete setup script:")
        print_info("  ./scripts/setup_complete_github_secrets.sh")
        print("")
        print_info("For force update mode:")
        print_info("  python scripts/setup_github_secrets.py --force")
        return True
    else:
        print_error("Some tests failed. Fix the issues above before proceeding.")
        print("")
        print_info("Common fixes:")
        print_info("  - Install dependencies: pip install requests PyNaCl")
        print_info("  - Check app_config.json configuration")
        print_info("  - Verify P12 certificates exist and password is correct")
        print_info("  - Ensure GitHub token has proper permissions")
        return False


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
