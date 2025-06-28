# GitHub Secrets Guide for R2MIDI

This document explains which GitHub secrets are required for different operations in the R2MIDI project.

## Important Note About Certificate Formats

When setting up macOS signing for R2MIDI, you'll download certificates from the Apple Developer Portal in `.cer` format. These `.cer` files are not password protected. However, for GitHub Actions workflows, these certificates need to be in `.p12` format with a password.

The conversion from `.cer` to `.p12` with password protection is handled automatically by the `scripts/setup_apple_store.py` script. This script:
1. Installs the `.cer` certificates to your local Keychain
2. Exports them as `.p12` files with randomly generated passwords
3. Sets up the appropriate GitHub secrets with these generated passwords

This is why the GitHub secrets for certificate passwords are required, even though your original `.cer` files don't have passwords.

## Required Secrets for macOS Signing

### App Store Signing (for App Store submissions)
These secrets are used in the `.github/workflows/app-store.yml` workflow:

| Secret Name | Description | Purpose |
|-------------|-------------|---------|
| `APPLE_APP_STORE_CERTIFICATE_P12` | Base64-encoded App Store certificate (.p12 file) | Used to sign applications for App Store submission |
| `APPLE_APP_STORE_CERTIFICATE_PASSWORD` | Password for the App Store certificate (.p12 file) | Required to unlock the certificate for signing (Note: While original .cer files are not password protected, they are converted to .p12 format with a generated password by the setup script) |
| `APP_STORE_CONNECT_API_KEY` | Base64-encoded API key for App Store Connect | Used for authentication with App Store Connect API |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID for App Store Connect | Used for authentication with App Store Connect API |
| `APP_STORE_CONNECT_KEY_ID` | Key ID for App Store Connect | Used for authentication with App Store Connect API |

### Developer ID Signing (for distribution outside the App Store)
These secrets are used in the `.github/actions/setup-macos-signing/action.yml` action:

| Secret Name | Description | Purpose |
|-------------|-------------|---------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded Developer ID certificate (.p12 file) | Used to sign applications for distribution outside the App Store |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the Developer ID certificate (.p12 file) | Required to unlock the certificate for signing (Note: While original .cer files are not password protected, they are converted to .p12 format with a generated password by the setup script) |
| `APPLE_ID` | Apple ID email address | Used for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for the Apple ID | Used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID | Used for notarization and code signing |

## Required Secrets for PyPI Publishing

These secrets are used in the `.github/workflows/release.yml` workflow:

| Secret Name | Description | Purpose |
|-------------|-------------|---------|
| `PYPI_API_TOKEN` | API token for PyPI | Used to authenticate with PyPI when publishing packages |
| `GITHUB_TOKEN` | GitHub token | Used for creating GitHub releases and accessing the repository |

## Other Required Secrets

These secrets are used for various purposes in the build workflows:

| Secret Name | Description | Purpose |
|-------------|-------------|---------|
| `WINDOWS_CERTIFICATE_P12` | Base64-encoded Windows certificate (.p12 file) | Used to sign Windows applications |
| `WINDOWS_CERTIFICATE_PASSWORD` | Password for the Windows certificate | Required to unlock the certificate for signing |
| `APP_BUNDLE_ID_PREFIX` | Bundle ID prefix (e.g., "com.example") | Used for application bundle identifiers |
| `APP_DISPLAY_NAME_SERVER` | Display name for the server application | Used in application metadata |
| `APP_DISPLAY_NAME_CLIENT` | Display name for the client application | Used in application metadata |
| `APP_AUTHOR_NAME` | Author name | Used in application metadata |
| `APP_AUTHOR_EMAIL` | Author email | Used in application metadata |

## How to Set Up GitHub Secrets

1. Go to your GitHub repository
2. Navigate to Settings > Secrets and variables > Actions
3. Click on "New repository secret"
4. Enter the secret name and value
5. Click "Add secret"

For certificates and API keys that need to be base64-encoded, you can use the following command:
```bash
cat certificate.p12 | base64 | pbcopy  # macOS (copies to clipboard)
cat certificate.p12 | base64  # Linux/Unix (prints to terminal)
```

## Obtaining the Required Secrets

### Apple Certificates and IDs
- App Store and Developer ID certificates can be created in the Apple Developer Portal
- Team ID can be found in the Apple Developer Portal under Membership
- App-specific passwords can be created at appleid.apple.com
- **Important Note**: The certificates downloaded from the Apple Developer Portal are in .cer format and are not password protected. However, for GitHub Actions, these certificates need to be converted to .p12 format with a password. This conversion is handled automatically by the `scripts/setup_apple_store.py` script, which generates random passwords for the .p12 files.

### PyPI API Token
- Log in to PyPI
- Go to Account Settings > API tokens
- Create a new API token with appropriate permissions

### Windows Certificates
- Windows code signing certificates can be purchased from certificate authorities
- Self-signed certificates can be created for testing purposes
