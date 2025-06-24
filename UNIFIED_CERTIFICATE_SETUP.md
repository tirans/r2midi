# Unified Certificate Setup for R2MIDI Builds

## Overview

The R2MIDI build system now uses a unified certificate loading and validation approach for all macOS builds. This ensures consistent certificate handling across both client and server builds.

## Key Features

1. **Common Certificate Loading**: All builds use the same certificate discovery and loading logic
2. **Automatic Certificate Discovery**: The system automatically finds and loads certificates from:
   - Existing keychain certificates
   - P12 files in `apple_credentials/certificates/`
3. **Build Summary with Certificate Info**: All builds now show certificate status in the summary
4. **Graceful Fallback**: If no certificates are found, builds continue unsigned with clear messaging

## File Structure

```
r2midi/
├── scripts/
│   └── common-certificate-setup.sh    # Common certificate functions
├── build-client-local.sh              # Client build (uses common setup)
├── build-server-local.sh              # Server build (uses common setup)
└── apple_credentials/
    └── certificates/
        ├── app_cert.p12               # Application signing certificate
        └── installer_cert.p12         # Installer signing certificate
```

## Usage

### Building with Signing

```bash
# Build client with signing
./build-client-local.sh

# Build server with signing
./build-server-local.sh
```

### Building without Signing

```bash
# Build client without signing
./build-client-local.sh --no-sign

# Build server without signing
./build-server-local.sh --no-sign
```

## Certificate Loading Process

1. **Environment Detection**: Determines if running locally or in GitHub Actions
2. **Existing Certificate Check**: Looks for valid Developer ID certificates in keychain
3. **P12 Loading** (if needed): Loads certificates from P12 files with password
4. **Validation**: Validates certificate expiry and capabilities
5. **Summary**: Reports certificate status in build summary

## Build Summary

All builds now include a certificate summary section:

```
═══════════════════════════════════════════════════════
📊 Build Summary: R2MIDI Client
═══════════════════════════════════════════════════════
  • Build Status: ✅ Success
  • Signing: ✅ Enabled
  • Certificate: Developer ID Application: Your Name (TEAMID)
  • Team ID: TEAMID
═══════════════════════════════════════════════════════
```

## Certificate Functions

The `common-certificate-setup.sh` script provides these functions:

- `setup_certificates [skip_signing]` - Main certificate setup function
- `cleanup_certificates` - Cleanup temporary keychains
- `get_certificate_summary` - Get detailed certificate info
- `print_build_summary` - Print build summary with certificate status

## Testing

Run the test script to verify certificate setup:

```bash
./test-certificate-setup.sh
```

## Troubleshooting

### No Certificates Found

If you see "No certificates available - unsigned build":

1. Check that P12 files exist in `apple_credentials/certificates/`
2. Verify P12 password is correct (default: `x2G2srk2RHtp`)
3. Run `security find-identity -v -p codesigning` to check keychain

### Certificate Loading Failed

If certificate loading fails:

1. Check system keychain access: `security list-keychains`
2. Verify P12 file integrity: `openssl pkcs12 -info -in app_cert.p12`
3. Check console logs for detailed error messages

### Build Failures

Build failures now show certificate status to help diagnose issues:

```
📊 Build Summary: R2MIDI Client
  • Build Status: ❌ Failed
  • Signing: ⚠️ Disabled
  • Reason: No certificates available - unsigned build
```

## GitHub Actions Integration

The certificate setup automatically detects GitHub Actions environment and expects certificates to be pre-loaded by the workflow. No changes needed to existing workflows.

## Security Notes

- P12 files should never be committed to the repository
- The `apple_credentials/certificates/` directory is gitignored
- Temporary keychains are created with unique names and cleaned up after use
- Certificate passwords are not logged or displayed

## Future Improvements

- [ ] Support for multiple certificate profiles
- [ ] Certificate expiry warnings
- [ ] Automatic certificate renewal reminders
- [ ] Integration with Apple's notarization service
