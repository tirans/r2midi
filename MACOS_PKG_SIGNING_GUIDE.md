# macOS PKG Signing and Notarization Guide

**Last Updated:** June 23, 2025  
**Version:** 2.0 (Keychain-Free Implementation)

## Overview

This guide provides comprehensive, up-to-date instructions for creating signed and notarized macOS PKG installers for the R2MIDI project. The implementation uses a modern, keychain-free approach that avoids password prompts and works reliably in both local development and CI/CD environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Development Setup](#local-development-setup)
3. [Quick Start](#quick-start)
4. [GitHub Actions Setup](#github-actions-setup)
5. [Manual PKG Creation](#manual-pkg-creation)
6. [Troubleshooting](#troubleshooting)
7. [Technical Details](#technical-details)

## Prerequisites

### Required Tools

Ensure you have the following tools installed on macOS:

```bash
# Check if tools are available
command -v security >/dev/null && echo "✅ security" || echo "❌ security"
command -v pkgbuild >/dev/null && echo "✅ pkgbuild" || echo "❌ pkgbuild"
command -v productsign >/dev/null && echo "✅ productsign" || echo "❌ productsign"
command -v xcrun >/dev/null && echo "✅ xcrun" || echo "❌ xcrun"
command -v python3 >/dev/null && echo "✅ python3" || echo "❌ python3"
```

### Apple Developer Requirements

1. **Apple Developer Account** ($99/year)
2. **Developer ID Installer Certificate** - Required for PKG signing
3. **Apple ID with App-Specific Password** - Required for notarization
4. **Team ID** - From your Apple Developer account

### Certificate Files

You need the following certificate files in P12 format:
- `apple_credentials/certificates/installer_cert.p12` - Developer ID Installer certificate
- `apple_credentials/certificates/app_cert.p12` - Developer ID Application certificate (for app signing)

## Local Development Setup

### 1. Configure Credentials

Edit `apple_credentials/config/app_config.json`:

```json
{
  "app_info": {
    "bundle_id_prefix": "com.yourcompany.r2midi",
    "server_display_name": "R2MIDI Server",
    "client_display_name": "R2MIDI Client",
    "author_name": "Your Name",
    "author_email": "your.email@example.com"
  },
  "apple_developer": {
    "apple_id": "your.apple.id@example.com",
    "team_id": "YOUR_TEAM_ID",
    "p12_path": "apple_credentials/certificates",
    "p12_password": "your_p12_password",
    "app_specific_password": "your-app-specific-password",
    "app_store_connect_key_id": "YOUR_KEY_ID",
    "app_store_connect_issuer_id": "your-issuer-id",
    "app_store_connect_api_key_path": "apple_credentials/app_store_connect/AuthKey_YOUR_KEY_ID.p8"
  },
  "build_options": {
    "enable_app_store_build": true,
    "enable_app_store_submission": true,
    "enable_notarization": true
  }
}
```

### 2. Export Certificates

Export your certificates from Keychain Access:

1. Open **Keychain Access**
2. Find your **"Developer ID Installer"** certificate
3. Right-click → **Export** → Save as `installer_cert.p12`
4. Find your **"Developer ID Application"** certificate
5. Right-click → **Export** → Save as `app_cert.p12`
6. Place both files in `apple_credentials/certificates/`
7. Use the same password for both certificates and update `p12_password` in config

### 3. Verify Setup

Run the certificate verification script:

```bash
./setup-local-certificates.sh --verify-only
```

This will verify:
- ✅ Configuration file is valid
- ✅ Certificate files exist and passwords work
- ✅ Apple ID credentials are functional
- ✅ All required tools are available

## Quick Start

### Build Everything with PKG Signing

The easiest way to create signed, notarized PKGs:

```bash
# Build both server and client with signed PKGs
./build-all-local.sh --version 1.0.0

# Development build (faster, skip notarization)
./build-all-local.sh --version 1.0.0-dev --dev --no-notarize

# Production build with full verification
./build-all-local.sh --version 1.0.0 --staging
```

### Build Individual Components

```bash
# Build server with signed PKG
./build-server-local.sh --version 1.0.0

# Build client with signed PKG
./build-client-local.sh --version 1.0.0

# Skip signing (unsigned PKG)
./build-client-local.sh --version 1.0.0 --no-sign
```

### Test PKG Signing

Verify the PKG signing infrastructure:

```bash
./test-pkg-signing.sh
```

## GitHub Actions Setup

### Required Secrets

Configure these secrets in your GitHub repository:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `APPLE_DEVELOPER_ID_INSTALLER_CERT` | Base64-encoded installer certificate | `MIIK...` |
| `APPLE_DEVELOPER_ID_APPLICATION_CERT` | Base64-encoded application certificate | `MIIK...` |
| `APPLE_CERT_PASSWORD` | Password for both certificates | `your_password` |
| `APPLE_ID` | Your Apple ID email | `your.email@example.com` |
| `APPLE_ID_PASSWORD` | App-specific password | `abcd-efgh-ijkl-mnop` |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID | `ABC123DEF4` |

### Encode Certificates for GitHub

```bash
# Encode installer certificate
base64 -i apple_credentials/certificates/installer_cert.p12 | pbcopy

# Encode application certificate  
base64 -i apple_credentials/certificates/app_cert.p12 | pbcopy
```

### Workflow Usage

The GitHub Actions workflow automatically handles PKG signing:

```yaml
- name: Build applications
  env:
    APPLE_DEVELOPER_ID_INSTALLER_CERT: ${{ secrets.APPLE_DEVELOPER_ID_INSTALLER_CERT }}
    APPLE_CERT_PASSWORD: ${{ secrets.APPLE_CERT_PASSWORD }}
    # ... other secrets
  run: |
    ./build-all-local.sh --version ${{ inputs.version }}
```

## Manual PKG Creation

### Create Unsigned PKG

```bash
# Create basic PKG structure
pkgbuild --identifier "com.yourcompany.r2midi.client" \
         --version "1.0.0" \
         --install-location "/Applications" \
         --component "build_client/dist/R2MIDI Client.app" \
         "R2MIDI-Client-1.0.0.pkg"
```

### Sign and Notarize PKG

```bash
# Sign and notarize using the dedicated script
./.github/scripts/sign-pkg.sh --pkg "R2MIDI-Client-1.0.0.pkg"

# Skip notarization (faster for testing)
./.github/scripts/sign-pkg.sh --pkg "R2MIDI-Client-1.0.0.pkg" --skip-notarize
```

### Verify PKG

```bash
# Check signature
pkgutil --check-signature "R2MIDI-Client-1.0.0.pkg"

# Check notarization
spctl --assess --type install "R2MIDI-Client-1.0.0.pkg"

# Install for testing
sudo installer -pkg "R2MIDI-Client-1.0.0.pkg" -target /
```

## Troubleshooting

### Common Issues

#### 1. Certificate Import Fails

**Error**: "Failed to find installer identity in keychain"

**Solution**:
```bash
# Check certificate validity
openssl pkcs12 -in apple_credentials/certificates/installer_cert.p12 -passin "pass:YOUR_PASSWORD" -noout -legacy

# Verify certificate details
./setup-local-certificates.sh --verify-only
```

#### 2. Notarization Fails

**Error**: "Missing Apple ID, password, or team ID for notarization"

**Solution**:
1. Verify Apple ID credentials in `app_config.json`
2. Ensure app-specific password is current
3. Check team ID is correct
4. Test credentials manually:
   ```bash
   xcrun notarytool history --apple-id "your.email@example.com" --password "your-app-password" --team-id "YOUR_TEAM_ID"
   ```

#### 3. PKG Signature Verification Fails

**Error**: "package is not signed"

**Solution**:
1. Ensure Developer ID Installer certificate is valid
2. Check certificate hasn't expired
3. Verify certificate password is correct
4. Re-export certificate from Keychain Access if needed

#### 4. Permission Errors

**Error**: "Operation not permitted"

**Solution**:
```bash
# Fix file permissions
sudo chown -R $(whoami) apple_credentials/
chmod 600 apple_credentials/certificates/*.p12
```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Enable debug logging
export LOG_LEVEL=0

# Run with detailed output
./build-all-local.sh --version 1.0.0-debug
```

### Manual Certificate Testing

Test certificates without keychain:

```bash
# Test installer certificate
openssl pkcs12 -in apple_credentials/certificates/installer_cert.p12 \
  -passin "pass:YOUR_PASSWORD" -nokeys -legacy | \
  openssl x509 -noout -subject

# Test application certificate  
openssl pkcs12 -in apple_credentials/certificates/app_cert.p12 \
  -passin "pass:YOUR_PASSWORD" -nokeys -legacy | \
  openssl x509 -noout -subject
```

## Technical Details

### PKG Signing Process

1. **Certificate Import**: Certificates are imported to the login keychain without password prompts
2. **PKG Creation**: `pkgbuild` creates the initial unsigned PKG
3. **PKG Signing**: `productsign` signs the PKG with the Developer ID Installer certificate
4. **Signature Verification**: `pkgutil --check-signature` verifies the signature
5. **Notarization**: `xcrun notarytool` submits the PKG to Apple for notarization
6. **Stapling**: `xcrun stapler` attaches the notarization ticket to the PKG

### Keychain-Free Implementation

The current implementation avoids keychain password prompts by:
- Using the `-A` flag with `security import` to allow access without prompts
- Importing certificates to the login keychain with appropriate trust settings
- Using the `-T` flag to specify which tools can access the certificates

### File Locations

- **Build Scripts**: `build-client-local.sh`, `build-server-local.sh`, `build-all-local.sh`
- **PKG Signing Script**: `.github/scripts/sign-pkg.sh`
- **Certificate Setup**: `setup-local-certificates.sh`
- **Configuration**: `apple_credentials/config/app_config.json`
- **Certificates**: `apple_credentials/certificates/`
- **Output PKGs**: `artifacts/`

### Integration Points

The PKG signing is integrated into:
- Individual build scripts (automatic PKG creation and signing)
- Main build script (`build-all-local.sh`)
- GitHub Actions workflows
- CI/CD pipelines

## Best Practices

1. **Use staging builds** for testing: `./build-all-local.sh --staging`
2. **Skip notarization during development**: `--no-notarize` flag
3. **Verify certificates regularly**: Run `./setup-local-certificates.sh --verify-only`
4. **Keep app-specific passwords current**: They expire periodically
5. **Test PKGs before distribution**: Install and verify functionality
6. **Use version tags**: Always specify `--version` for reproducible builds

## Support

For additional help:
- Check the build logs in `logs/` directory
- Review the build reports in `artifacts/`
- Run the test script: `./test-pkg-signing.sh`
- Consult Apple's notarization documentation
- Check the project's GitHub Issues for known problems

---

**Note**: This guide reflects the current implementation as of June 2025. The keychain-free approach eliminates password prompts and provides reliable signing in both local and CI environments.