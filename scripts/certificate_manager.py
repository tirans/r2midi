#!/usr/bin/env python3
"""
Certificate Manager for R2MIDI
==============================

Helper script for managing Apple Developer certificates for code signing.
This script can check, export, and manage certificates needed for the
GitHub Actions workflow.

Requirements:
- macOS
- Apple Developer account
- Xcode command line tools

Usage:
    python scripts/certificate_manager.py [command]

Commands:
    check       - Check available certificates
    export      - Export certificates for GitHub Actions
    guide       - Show download guide for certificates
"""

import base64
import getpass
import os
import re
import subprocess
import sys
from typing import Dict, List


class CertificateManager:
    """Manages Apple Developer certificates for code signing."""

    def __init__(self):
        self.certificates = {}

    def check_certificates(self) -> Dict[str, List]:
        """Check for available certificates in keychain."""
        print("🔍 Checking keychain for certificates...")

        certificates = {
            "developer_id_app": [],
            "developer_id_installer": [],
            "app_store_app": [],
            "app_store_installer": [],
        }

        try:
            result = subprocess.run(
                ["security", "find-identity", "-v", "-p", "codesigning"],
                capture_output=True,
                text=True,
                check=True,
            )

            for line in result.stdout.split("\n"):
                line = line.strip()
                if not line or "valid identities found" in line:
                    continue

                if '"' in line:
                    cert_match = re.search(r'"([^"]*)"', line)
                    if cert_match:
                        cert_name = cert_match.group(1)

                        if "Developer ID Application:" in cert_name:
                            certificates["developer_id_app"].append(
                                {
                                    "name": cert_name,
                                    "type": "Developer ID Application",
                                    "purpose": "Direct distribution (outside App Store)",
                                }
                            )
                        elif "Developer ID Installer:" in cert_name:
                            certificates["developer_id_installer"].append(
                                {
                                    "name": cert_name,
                                    "type": "Developer ID Installer",
                                    "purpose": "Package installers for direct distribution",
                                }
                            )
                        elif "3rd Party Mac Developer Application:" in cert_name:
                            certificates["app_store_app"].append(
                                {
                                    "name": cert_name,
                                    "type": "Mac App Store Application",
                                    "purpose": "App Store distribution",
                                }
                            )
                        elif "3rd Party Mac Developer Installer:" in cert_name:
                            certificates["app_store_installer"].append(
                                {
                                    "name": cert_name,
                                    "type": "Mac App Store Installer",
                                    "purpose": "App Store package creation",
                                }
                            )

        except subprocess.CalledProcessError as e:
            print(f"❌ Error checking certificates: {e}")
            return {}

        return certificates

    def display_certificates(self, certificates: Dict):
        """Display found certificates in a formatted way."""
        print("\n📜 Certificate Status:")
        print("=" * 60)

        cert_types = [
            ("developer_id_app", "🔵 Developer ID Application"),
            ("developer_id_installer", "🔵 Developer ID Installer"),
            ("app_store_app", "🟢 Mac App Store Application"),
            ("app_store_installer", "🟢 Mac App Store Installer"),
        ]

        for cert_key, cert_title in cert_types:
            print(f"\n{cert_title}:")
            certs = certificates.get(cert_key, [])
            if certs:
                for cert in certs:
                    print(f"  ✅ {cert['name']}")
                    print(f"     Purpose: {cert['purpose']}")
            else:
                print("  ❌ Not found")

        print("\n" + "=" * 60)

        # Summary and recommendations
        has_dev_id = bool(certificates.get("developer_id_app"))
        has_app_store = bool(certificates.get("app_store_app"))

        print("\n📋 Summary:")
        if has_dev_id:
            print("  ✅ Ready for direct distribution (Developer ID)")
        else:
            print("  ⚠️  Missing Developer ID certificates")

        if has_app_store:
            print("  ✅ Ready for App Store distribution")
        else:
            print("  ⚠️  Missing App Store certificates")

        if not has_dev_id and not has_app_store:
            print("\n🚨 No signing certificates found!")
            print(
                "   You need to download and install certificates from Apple Developer Portal"
            )

    def download_guide(self):
        """Provide detailed guide for downloading certificates."""
        print("\n📥 Certificate Download Guide")
        print("=" * 40)

        print("\n1. 🌐 Go to Apple Developer Portal:")
        print("   https://developer.apple.com/account/resources/certificates/list")

        print("\n2. 🔐 Sign in with your Apple Developer account")

        print("\n3. 📜 Create/Download required certificates:")

        print("\n   🔵 For Direct Distribution (recommended):")
        print("   • Certificate Type: 'Developer ID Application'")
        print("   • Used for: Apps distributed outside the App Store")
        print("   • Required for: Notarization, direct download")

        print("\n   🔵 For Direct Distribution Installers:")
        print("   • Certificate Type: 'Developer ID Installer'")
        print("   • Used for: .pkg installers for direct distribution")

        print("\n   🟢 For App Store Distribution (recommended for auto-submission):")
        print("   • Certificate Type: 'Mac App Store'")
        print("   • Used for: Apps submitted to the Mac App Store")
        print("   • Required for: Automatic App Store submission in workflows")

        print("\n   🟢 For App Store Installers:")
        print("   • Certificate Type: 'Mac Installer Distribution'")
        print("   • Used for: .pkg files for App Store submission")
        print("   • Required for: Creating installer packages for App Store")

        print("\n4. 💾 Download Process:")
        print("   • Click '+' to create a new certificate")
        print("   • Select the certificate type")
        print("   • Upload a Certificate Signing Request (CSR)")
        print("   • Download the .cer file")

        print("\n5. 🗝️  Creating a CSR (Certificate Signing Request):")
        print("   • Open 'Keychain Access' on your Mac")
        print(
            "   • Menu: Keychain Access → Certificate Assistant → Request Certificate from CA"
        )
        print("   • Enter your email and name")
        print("   • Select 'Saved to disk'")
        print("   • Upload the generated .certSigningRequest file to Apple")

        print("\n6. 📦 After downloading:")
        print("   • Double-click the .cer files to install in Keychain")
        print("   • Run 'python scripts/certificate_manager.py check' to verify")

        print("\n7. 🏪 For App Store Connect API (automated submission):")
        print("   • Go to https://appstoreconnect.apple.com/access/api")
        print("   • Create a new API key with 'Developer' role or higher")
        print("   • Download the .p8 file and note the Key ID and Issuer ID")
        print("   • These will be needed for automatic App Store submission")

    def export_certificate(self, cert_name: str, output_name: str):
        """Export a certificate from keychain as base64 encoded P12."""
        print(f"\n📤 Exporting certificate: {cert_name}")

        temp_file = f"/tmp/{output_name}_{os.getpid()}.p12"

        try:
            print(f"\nYou need to set a password for the exported certificate.")
            print(
                f"This password will be used by GitHub Actions to import the certificate."
            )

            while True:
                password = getpass.getpass("Enter export password: ")
                confirm_password = getpass.getpass("Confirm password: ")

                if password == confirm_password:
                    break
                print("❌ Passwords don't match. Please try again.")

            print("🔄 Exporting certificate...")

            result = subprocess.run(
                [
                    "security",
                    "export",
                    "-k",
                    "login.keychain-db",
                    "-t",
                    "identities",
                    "-f",
                    "pkcs12",
                    "-o",
                    temp_file,
                    "-P",
                    password,
                ],
                input=f'"{cert_name}"\n',
                text=True,
                capture_output=True,
            )

            if result.returncode != 0:
                print(f"❌ Export failed: {result.stderr}")
                return None

            with open(temp_file, "rb") as f:
                cert_data = f.read()

            encoded_cert = base64.b64encode(cert_data).decode("utf-8")

            print(f"✅ Certificate exported successfully")
            print(f"📊 Size: {len(cert_data)} bytes ({len(encoded_cert)} base64 chars)")

            return encoded_cert, password

        except Exception as e:
            print(f"❌ Error exporting certificate: {e}")
            return None
        finally:
            if os.path.exists(temp_file):
                os.remove(temp_file)

    def export_all_for_github(self):
        """Export all available certificates for GitHub Actions."""
        print("\n🚀 Exporting Certificates for GitHub Actions")
        print("=" * 50)

        certificates = self.check_certificates()
        if not certificates:
            print("❌ No certificates found to export")
            return

        exports = {}

        # Export Developer ID Application certificate
        if certificates.get("developer_id_app"):
            cert = certificates["developer_id_app"][0]
            print(f"\n🔵 Exporting Developer ID Application certificate...")
            result = self.export_certificate(cert["name"], "developer_id")
            if result:
                encoded_cert, password = result
                exports["APPLE_CERTIFICATE_P12"] = encoded_cert
                exports["APPLE_CERTIFICATE_PASSWORD"] = password

        # Export App Store certificate if available
        if certificates.get("app_store_app"):
            cert = certificates["app_store_app"][0]
            print(f"\n🟢 Exporting App Store Application certificate...")
            result = self.export_certificate(cert["name"], "app_store")
            if result:
                encoded_cert, password = result
                exports["APPLE_APP_STORE_CERTIFICATE_P12"] = encoded_cert
                exports["APPLE_APP_STORE_CERTIFICATE_PASSWORD"] = password

        # Also export App Store installer certificate if available
        if certificates.get("app_store_installer"):
            cert = certificates["app_store_installer"][0]
            print(f"\n🟢 Exporting App Store Installer certificate...")
            result = self.export_certificate(cert["name"], "app_store_installer")
            if result:
                encoded_cert, password = result
                exports["APPLE_APP_STORE_INSTALLER_CERTIFICATE_P12"] = encoded_cert
                exports["APPLE_APP_STORE_INSTALLER_CERTIFICATE_PASSWORD"] = password

        if exports:
            # Save to file
            with open("exported_certificates.txt", "w") as f:
                f.write("# Exported Certificates for GitHub Secrets\n")
                f.write("# Add these to your GitHub repository secrets\n\n")
                f.write("# Required for all macOS builds:\n")
                for key, value in exports.items():
                    if "APPLE_CERTIFICATE" in key:
                        if "P12" in key:
                            f.write(f"{key}=<base64_certificate_data>\n")
                        else:
                            f.write(f"{key}=<certificate_password>\n")

                f.write("\n# Required for App Store submission:\n")
                for key, value in exports.items():
                    if "APP_STORE" in key:
                        if "P12" in key:
                            f.write(f"{key}=<base64_certificate_data>\n")
                        else:
                            f.write(f"{key}=<certificate_password>\n")

                f.write("\n# Additional secrets needed for App Store Connect API:\n")
                f.write("# APP_STORE_CONNECT_API_KEY=<base64_encoded_p8_file>\n")
                f.write("# APP_STORE_CONNECT_KEY_ID=<key_id_from_app_store_connect>\n")
                f.write(
                    "# APP_STORE_CONNECT_ISSUER_ID=<issuer_id_from_app_store_connect>\n"
                )
                f.write("# ENABLE_APP_STORE_SUBMISSION=true\n")

            print(f"\n✅ Certificate export completed!")
            print(f"📁 Reference saved to: exported_certificates.txt")
            print(f"\n🔒 Security reminder:")
            print(f"   • Add these values to GitHub repository secrets")
            print(f"   • Delete exported_certificates.txt after use")
            print(f"   • Never commit certificates to your repository")
            print(f"   • Set up App Store Connect API for automatic submission")
            print(f"   • Use 'python scripts/setup_github_secrets.py' for full setup")
        else:
            print("❌ No certificates were exported")


def main():
    """Main entry point."""
    manager = CertificateManager()

    if len(sys.argv) < 2:
        command = "check"
    else:
        command = sys.argv[1].lower()

    if command == "check":
        certificates = manager.check_certificates()
        manager.display_certificates(certificates)
    elif command == "export":
        manager.export_all_for_github()
    elif command == "guide":
        manager.download_guide()
    else:
        print("Unknown command. Available commands: check, export, guide")
        sys.exit(1)


if __name__ == "__main__":
    main()
