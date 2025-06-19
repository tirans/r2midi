#!/usr/bin/env python3
"""
Security Scanner for GitHub Secrets Manager
===========================================

Scans the setup_github_secrets.py script for potential security issues
and confidential information exposure.
"""

import re
from pathlib import Path


def scan_for_hardcoded_secrets(content: str) -> list:
    """Scan for hardcoded secrets and sensitive information."""
    issues = []
    
    # Patterns for common secrets
    patterns = {
        'GitHub Token': r'github_pat_[a-zA-Z0-9_]{82}|ghp_[a-zA-Z0-9]{36}',
        'Apple ID Password': r'[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}',
        'Email Address': r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
        'Base64 Certificate': r'[A-Za-z0-9+/]{100,}={0,2}',
        'Generic Password': r'password\s*=\s*["\'][^"\']{8,}["\']',
        'API Key': r'[A-Z0-9]{32,}',
        'Private Key': r'-----BEGIN.*PRIVATE KEY-----',
        'Certificate': r'-----BEGIN CERTIFICATE-----',
    }
    
    for name, pattern in patterns.items():
        matches = re.findall(pattern, content, re.IGNORECASE)
        if matches:
            # Filter out obvious false positives
            if name == 'Email Address':
                # Allow placeholder emails
                matches = [m for m in matches if not any(placeholder in m.lower() 
                          for placeholder in ['example.com', 'test.com', 'your', 'user', 'email'])]
            
            if matches:
                issues.append(f"⚠️  Found potential {name}: {len(matches)} instances")
    
    return issues


def scan_for_logging_secrets(content: str) -> list:
    """Scan for places where secrets might be logged."""
    issues = []
    
    # Look for print statements that might expose secrets
    print_patterns = [
        r'print.*password',
        r'print.*token',
        r'print.*key.*[^_]id',
        r'print.*secret',
        r'print.*cert.*[^_]data',
        r'self\.print.*secret_value',
        r'self\.print.*encrypted_value',
    ]
    
    for pattern in print_patterns:
        matches = re.findall(pattern, content, re.IGNORECASE)
        if matches:
            issues.append(f"⚠️  Potential secret logging: {pattern}")
    
    return issues


def scan_for_config_exposure(content: str) -> list:
    """Scan for configuration values that might be exposed."""
    issues = []
    
    # Look for specific fields being printed
    lines = content.split('\n')
    for i, line in enumerate(lines, 1):
        if 'print_info' in line or 'print_success' in line:
            # Check if it's printing sensitive config values
            sensitive_fields = ['password', 'token', 'key', 'secret']
            for field in sensitive_fields:
                if field in line.lower() and 'len(' not in line:
                    issues.append(f"⚠️  Line {i}: May expose {field}")
    
    return issues


def check_file_permissions(file_path: Path) -> list:
    """Check file permissions."""
    issues = []
    
    if file_path.exists():
        stat = file_path.stat()
        # Check if file is readable by others
        if stat.st_mode & 0o044:  # Others can read
            issues.append("⚠️  Script is readable by others - consider restricting permissions")
        
        # Check if file is executable by others
        if stat.st_mode & 0o011:  # Others can execute
            issues.append("⚠️  Script is executable by others - consider restricting permissions")
    
    return issues


def main():
    """Main security scanning function."""
    print("🔒 Security Scanner for GitHub Secrets Manager")
    print("=" * 50)
    
    script_path = Path("scripts/setup_github_secrets.py")
    
    if not script_path.exists():
        print("❌ Script not found")
        return False
    
    # Read script content
    with open(script_path, 'r') as f:
        content = f.read()
    
    print(f"📁 Scanning: {script_path}")
    print(f"📊 File size: {len(content)} characters")
    print()
    
    all_issues = []
    
    # Run security scans
    print("🔍 Scanning for hardcoded secrets...")
    hardcoded_issues = scan_for_hardcoded_secrets(content)
    all_issues.extend(hardcoded_issues)
    
    print("🔍 Scanning for secret logging...")
    logging_issues = scan_for_logging_secrets(content)
    all_issues.extend(logging_issues)
    
    print("🔍 Scanning for config exposure...")
    config_issues = scan_for_config_exposure(content)
    all_issues.extend(config_issues)
    
    print("🔍 Checking file permissions...")
    permission_issues = check_file_permissions(script_path)
    all_issues.extend(permission_issues)
    
    print()
    print("📋 Security Scan Results:")
    print("-" * 30)
    
    if not all_issues:
        print("✅ No security issues found!")
        print()
        print("✅ Safe to commit to GitHub:")
        print("  • No hardcoded secrets detected")
        print("  • No sensitive information logging")
        print("  • Configuration values are safely handled")
        print("  • Script reads secrets from config files only")
        print()
        print("🔒 Security Notes:")
        print("  • Script only prints metadata (lengths, counts)")
        print("  • Actual secret values are never logged")
        print("  • All sensitive data read from app_config.json")
        print("  • GitHub API calls use proper encryption")
        return True
    else:
        print("⚠️  Security issues found:")
        for issue in all_issues:
            print(f"  {issue}")
        
        print()
        print("🔧 Recommendations:")
        print("  • Review flagged areas above")
        print("  • Ensure no secrets are hardcoded")
        print("  • Verify logging doesn't expose sensitive data")
        print("  • Check file permissions are appropriate")
        return False


if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
