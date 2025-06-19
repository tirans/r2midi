# macOS Code Signing and Notarization Setup

This guide covers the complete setup for macOS code signing and notarization for R2MIDI applications for **distribution outside the Mac App Store**.

## Overview

The R2MIDI project uses Apple's Developer ID signing and notarization to ensure applications can run on macOS without security warnings. This process involves:

1. **Code Signing**: Using Apple Developer ID certificates to sign applications
2. **Notarization**: Submitting signed applications to Apple for security scanning
3. **Stapling**: Attaching notarization tickets to applications for offline verification

## Prerequisites

- **Apple Developer Program membership** ($99/year)
- **macOS development machine** with Xcode command line tools
- **GitHub repository** with Actions enabled

## Required Certificates

For distributing macOS applications **outside the Mac App Store**, you need these specific certificates from the Apple Developer Portal:

### 🎯 Developer ID Application
- **Purpose**: "This certificate is used to code sign your app for distribution outside of the Mac App Store Connect."
- **Usage**: Signs .app bundles and DMG files
- **Required**: Yes

### 🎯 Developer ID Installer  
- **Purpose**: "This certificate is used to sign your app's Installer Package for distribution outside of the Mac App Store Connect."
- **Usage**: Signs PKG installer packages
- **Required**: Yes (for PKG installers)

### ❌ Do NOT Use These Certificates

- **Apple Development** - For development only
- **Apple Distribution** - For App Store distribution
- **Mac App Distribution** - For Mac App Store submission
- **Mac Installer Distribution** - For Mac App Store submission

## Quick Setup

Run the interactive setup script:

```bash
cd .github/scripts
chmod +x setup-macos-signing.sh
./setup-macos-signing.sh
```

This comprehensive script will guide you through:
1. Apple Developer Program verification
2. Certificate creation in Apple Developer Portal
3. Certificate export from Keychain Access
4. App-specific password creation
5. GitHub secrets generation
6. Security cleanup

## Manual Setup (Step by Step)

### Step 1: Access Apple Developer Portal

Go to [Apple Developer Portal Certificates](https://developer.apple.com/account/resources/certificates/list)

### Step 2: Create Certificate Signing Request (CSR)

1. Open **Keychain Access**
2. Menu: **Keychain Access** → **Certificate Assistant** → **Request a Certificate From a Certificate Authority**
3. Fill in:
   - **User Email Address**: Your Apple ID email
   - **Common Name**: Your name or organization name
   - **CA Email Address**: Leave blank
   - **Request is**: ☑️ **Saved to disk**
4. Click **Continue** and save as `CertificateSigningRequest.certSigningRequest`

### Step 3: Create Developer ID Application Certificate

1. In Apple Developer Portal, click **"+"** to create new certificate
2. Under **Software** section, select:
   - ☑️ **Developer ID Application**
   - Description: "This certificate is used to code sign your app for distribution outside of the Mac App Store Connect."
3. Click **Continue**
4. Upload your CSR file
5. Click **Continue** → **Download**
6. **Double-click** the downloaded certificate to install in Keychain Access

### Step 4: Create Developer ID Installer Certificate

1. Click **"+"** again for second certificate
2. Under **Software** section, select:
   - ☑️ **Developer ID Installer**  
   - Description: "This certificate is used to sign your app's Installer Package for distribution outside of the Mac App Store Connect."
3. Click **Continue**
4. Upload the **same CSR file**
5. Download and install this certificate too

### Step 5: Verify Certificates in Keychain

Open **Keychain Access** and verify you have:
- ✅ **Developer ID Application: [Your Name] ([Team ID])**
- ✅ **Developer ID Installer: [Your Name] ([Team ID])**
- ✅ Both certificates should have private keys (expandable with arrow)

### Step 6: Export Certificates

**For Developer ID Application:**
1. In Keychain Access, find "Developer ID Application: [Your Name]"
2. Expand to show certificate + private key
3. Select **both items** (Cmd+click)
4. Right-click → **Export 2 items...**
5. Format: **Personal Information Exchange (.p12)**
6. Save as: `app_cert.p12`
7. Set a strong password

**For Developer ID Installer:**
1. Find "Developer ID Installer: [Your Name]"
2. Export both certificate + private key as `installer_cert.p12`
3. Use the **same password**

### Step 7: Convert to Base64

```bash
base64 -i app_cert.p12 > app_cert_base64.txt
base64 -i installer_cert.p12 > installer_cert_base64.txt
```

### Step 8: Create App-Specific Password

1. Go to [Apple ID Account](https://appleid.apple.com/)
2. Sign in → **Security** section
3. **App-Specific Passwords** → **Generate Password...**
4. Label: "R2MIDI macOS Notarization"
5. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

### Step 9: Find Your Team ID

1. Go to [Apple Developer Membership](https://developer.apple.com/account/#!/membership/)
2. Find **Team ID** (10-character alphanumeric string like `ABC123DEFG`)

### Step 10: Setup GitHub Secrets

Add these secrets to your repository (**Settings** → **Secrets and variables** → **Actions**):

| Secret Name | Description | Value |
|-------------|-------------|-------|
| `APPLE_DEVELOPER_ID_APPLICATION_CERT` | Base64 content of app_cert.p12 | `[base64 string]` |
| `APPLE_DEVELOPER_ID_INSTALLER_CERT` | Base64 content of installer_cert.p12 | `[base64 string]` |
| `APPLE_CERT_PASSWORD` | Password for both P12 certificates | `[your password]` |
| `APPLE_ID` | Your Apple ID email | `[your email]` |
| `APPLE_ID_PASSWORD` | App-specific password | `[xxxx-xxxx-xxxx-xxxx]` |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID | `[ABC123DEFG]` |

## Scripts Overview

### setup-certificates.sh

Handles certificate import and keychain setup:
- ✅ Supports both individual certificates and combined P12 format  
- ✅ Validates certificates before import
- ✅ Creates temporary keychain for CI/CD
- ✅ Exports signing identities for other scripts

### sign-and-notarize-macos.sh

Performs signing and notarization:
- ✅ Inside-out signing approach (libraries → frameworks → apps)
- ✅ Creates both DMG and PKG installers
- ✅ Submits to Apple Notary Service with xcrun notarytool
- ✅ Staples notarization tickets
- ✅ Comprehensive verification and Gatekeeper testing

### package-macos-apps.sh

Organizes final distribution packages:
- ✅ Verifies signed and notarized packages
- ✅ Creates universal distribution bundles
- ✅ Generates checksums and manifests
- ✅ Creates installation documentation

## GitHub Actions Workflow

The updated workflow (`build-macos.yml`) supports both certificate formats and includes proper validation:

```yaml
- name: Setup Apple Developer certificates
  env:
    APPLE_DEVELOPER_ID_APPLICATION_CERT: ${{ secrets.APPLE_DEVELOPER_ID_APPLICATION_CERT }}
    APPLE_DEVELOPER_ID_INSTALLER_CERT: ${{ secrets.APPLE_DEVELOPER_ID_INSTALLER_CERT }}
    APPLE_CERT_PASSWORD: ${{ secrets.APPLE_CERT_PASSWORD }}
  run: ./.github/scripts/setup-certificates.sh

- name: Sign and notarize applications
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: |
    ./.github/scripts/sign-and-notarize-macos.sh \
      "${{ steps.version.outputs.version }}" \
      "${{ inputs.build-type }}" \
      "${{ secrets.APPLE_ID }}" \
      "${{ secrets.APPLE_ID_PASSWORD }}" \
      "${{ secrets.APPLE_TEAM_ID }}"
```

## Troubleshooting

### "SecKeychainItemImport: One or more parameters passed to a function were not valid"

**Cause**: Certificate environment variables are empty or certificates are invalid.

**Solutions**:
1. Verify all 6 GitHub secrets are set correctly
2. Check certificate files are not corrupted (re-export if needed)
3. Ensure certificate password matches the P12 files
4. Confirm base64 encoding has no extra whitespace

### Certificate Import Failures

**Cause**: Issues with P12 format or keychain access.

**Solutions**:
1. Re-export certificates ensuring both certificate + private key are selected
2. Use the same password for both P12 files
3. Verify certificates are "Developer ID" type (not Apple Development/Distribution)

### Notarization Failures

**Common causes**:
- Invalid entitlements for hardened runtime
- Incorrect Apple ID credentials
- Missing or expired app-specific password
- App contains prohibited content

**Solutions**:
1. Check entitlements match app requirements
2. Regenerate app-specific password
3. Verify Apple ID and Team ID are correct
4. Review notarization logs for specific issues

### Gatekeeper Assessment Failed

**Cause**: App not properly signed/notarized or Gatekeeper policies.

**Solutions**:
1. Ensure Developer ID certificates (not development certificates)
2. Verify notarization completed successfully
3. Check notarization ticket is stapled
4. Test on clean macOS system

## Security Best Practices

1. **Certificate Security**:
   - Use strong passwords for P12 exports
   - Delete P12 files after GitHub setup
   - Store certificates only in trusted keychains

2. **Credential Management**:
   - Rotate app-specific passwords regularly
   - Use unique passwords for each project
   - Monitor certificate expiration dates

3. **Repository Security**:
   - Limit repository access to trusted collaborators
   - Use branch protection rules
   - Review changes to signing scripts

## File Structure

```
.github/scripts/
├── setup-certificates.sh       # Certificate import and keychain setup
├── sign-and-notarize-macos.sh  # Main signing and notarization
├── package-macos-apps.sh       # Final packaging and organization
├── setup-macos-signing.sh      # Interactive setup helper
└── README.md                   # This documentation
```

## Expected Output

After successful setup, your builds will produce:

### DMG Files (Drag-and-Drop Installers)
- `R2MIDI-Server-[version].dmg` - Signed and notarized
- `R2MIDI-Client-[version].dmg` - Signed and notarized

### PKG Files (Automated Installers)
- `R2MIDI-Server-[version].pkg` - Signed and notarized
- `R2MIDI-Client-[version].pkg` - Signed and notarized

### Distribution Bundle
- `R2MIDI-Complete-[version]-macOS.zip` - Complete package with documentation

### Verification Files
- `CHECKSUMS.txt` - SHA256 checksums
- `SIGNING_REPORT.txt` - Detailed signing information
- `PACKAGE_MANIFEST.txt` - Package details and verification

## Verification Commands

Test your setup locally:

```bash
# Check available certificates
security find-identity -v -p codesigning

# Verify app signature
codesign --verify --deep --strict --verbose=2 YourApp.app

# Check Gatekeeper compatibility
spctl --assess --type exec --verbose YourApp.app

# Verify notarization and stapling
xcrun stapler validate YourApp.dmg
spctl --assess --type install --verbose YourApp.dmg
```

## Support

If you encounter issues:

1. **Run the interactive setup script** - it handles most common problems
2. **Check GitHub Actions logs** for detailed error messages
3. **Verify all secrets** are set correctly in repository settings
4. **Test certificates locally** using verification commands
5. **Review Apple's documentation** for certificate and notarization requirements

## Apple Documentation References

- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Developer ID Certificates](https://developer.apple.com/support/certificates/)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Gatekeeper and App Notarization](https://developer.apple.com/documentation/security/gatekeeper)

---

**🎯 Remember**: These certificates are specifically for **distribution outside the Mac App Store**. If you later want to distribute through the Mac App Store, you'll need different certificates (Mac App Distribution and Mac Installer Distribution).
