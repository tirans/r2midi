# Certificate Setup Report

**Generated:** Sat Jun 28 17:43:01 IDT 2025  
**Apple ID:** tiran@outlook.com  
**Team ID:** 79449BGAM5  

## Certificate Status

- ✅ Application Certificate (developerID_application.p12)
- ✅ Installer Certificate (developerID_installer.p12)
- ✅ Private Key (private_key.p12)

## Environment Setup

- ✅ Configuration loaded from apple_credentials/config/app_config.json
- ✅ Build environment file created (.local_build_env)

## Next Steps

1. Source the environment:
   ```bash
   source .local_build_env
   ```

2. Run the signing script:
   ```bash
   ./.github/scripts/sign-and-notarize-macos.sh --version 1.0.0
   ```

3. Or use with build scripts:
   ```bash
   ./build-server-local.sh --version 1.0.0
   ./build-client-local.sh --version 1.0.0
   ```

## Troubleshooting

If you encounter issues:

1. **Certificate Errors:**
   - Verify certificates are not expired
   - Check p12_password is correct in app_config.json
   - Re-export certificates from Keychain Access if needed

2. **Apple ID Issues:**
   - Check Apple ID has proper permissions
   - Ensure app-specific password is current
   - Verify team ID is correct

3. **Build Issues:**
   - Make sure virtual environments are set up
   - Check that py2app dependencies are installed
   - Verify entitlements are correct for your app type

For more help, check the Apple Developer documentation.

## Certificate Export Instructions

If you need to re-export your certificates:

1. Open Keychain Access
2. Find your "Developer ID Application" certificate
3. Right-click → Export → Save as developerID_application.p12
4. Find your "Developer ID Installer" certificate  
5. Right-click → Export → Save as developerID_installer.p12
6. Place both files in: apple_credentials/certificates/
7. Update the password in app_config.json if needed

