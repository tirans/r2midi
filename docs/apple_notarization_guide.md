# Apple Notarization Authentication Guide

## Overview

This guide explains how to set up authentication for Apple notarization in the R2MIDI project. Apple has updated their authentication requirements, and using an Apple ID with an app-specific password may no longer be supported for some operations. Instead, it's recommended to use App Store Connect API keys for CI/CD workflows.

## Authentication Methods

There are two methods for authenticating with Apple's notarization service:

### 1. Apple ID with App-Specific Password (Traditional)

This method uses your Apple ID, app-specific password, and Team ID to authenticate. While this method still works in some cases, Apple has started restricting its use for automated workflows, which can result in 401 authentication errors.

**Required credentials:**
- Apple ID (email)
- App-specific password (generated at https://appleid.apple.com)
- Team ID (found in your Apple Developer account)

### 2. App Store Connect API Key (Recommended for CI/CD)

This method uses an App Store Connect API key, which is more secure and reliable for automated workflows. This is now the recommended approach for CI/CD pipelines.

**Required credentials:**
- App Store Connect API Key (.p8 file)
- Key ID
- Issuer ID

## Setting Up App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/access/api)
2. Click "Keys" tab
3. Click "+" to create a new API key
4. Give it a name (e.g., "R2MIDI Notarization")
5. Select "Developer" access role
6. Click "Generate"
7. **Download the .p8 file immediately** (you won't be able to download it again)
8. Note the Key ID displayed on the page
9. Note the Issuer ID (displayed at the top of the page)

## Testing Your Credentials

Use the provided test script to verify your credentials before updating GitHub secrets:

```bash
./test_notarization_creds.sh
```

The script will prompt you to choose between the two authentication methods and guide you through testing your credentials.

## Updating GitHub Secrets

After verifying your credentials, you need to update the GitHub secrets used by the CI/CD workflow:

### For App Store Connect API Key Authentication (Recommended)

Add these secrets to your GitHub repository:

1. `APP_STORE_CONNECT_API_KEY`: Base64-encoded content of your .p8 file
   ```bash
   cat /path/to/your/key.p8 | base64
   ```
2. `APP_STORE_CONNECT_KEY_ID`: Your Key ID
3. `APP_STORE_CONNECT_ISSUER_ID`: Your Issuer ID

### For Apple ID Authentication (Legacy)

If you still want to use Apple ID authentication, ensure these secrets are set:

1. `APPLE_ID`: Your Apple ID email
2. `APPLE_ID_PASSWORD`: Your app-specific password
3. `APPLE_TEAM_ID`: Your Team ID

## Troubleshooting

### 401 Authentication Error

If you encounter a 401 error with the message "The application is not allowed for primary authentication", this indicates that Apple is rejecting the Apple ID authentication method. Switch to the App Store Connect API key method as described above.

### Other Common Issues

1. **Invalid API Key**: Make sure your .p8 file is valid and not corrupted
2. **Incorrect Key ID or Issuer ID**: Double-check these values in App Store Connect
3. **Insufficient Permissions**: Ensure your API key has the "Developer" role assigned
4. **Expired API Key**: API keys expire after 1 year; create a new one if needed

## Further Resources

- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [App Store Connect API Documentation](https://developer.apple.com/documentation/appstoreconnectapi)
- [Creating and Using App-Specific Passwords](https://support.apple.com/en-us/HT204397)