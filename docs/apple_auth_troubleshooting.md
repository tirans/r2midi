# Troubleshooting Apple Authentication Errors

## 401 Authentication Error

If you're encountering a 401 authentication error with the message "The application is not allowed for primary authentication" when trying to notarize your macOS application, this guide will help you resolve the issue.

## Why This Happens

Apple has restricted the use of Apple ID authentication for some notarization operations, especially in automated CI/CD environments. This is why you're seeing the error:

```
Error: HTTP status code: 401. Unable to authenticate. The application is not allowed for primary authentication.
```

## Solution: Use App Store Connect API Key Authentication

The recommended solution is to switch from Apple ID authentication to App Store Connect API Key authentication. This method is more secure and reliable for automated workflows.

## Step 1: Create an App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/access/api)
2. Click the "Keys" tab
3. Click "+" to create a new API key
4. Give it a name (e.g., "R2MIDI Notarization")
5. Select "Developer" access role
6. Click "Generate"
7. **Download the .p8 file immediately** (you won't be able to download it again)
8. Note the Key ID displayed on the page
9. Note the Issuer ID (displayed at the top of the page)

## Step 2: Validate Your API Key

We've created a simple validation script to help you test your API key:

```bash
./validate_api_key.sh
```

This script will:
1. Read your Key ID, Issuer ID, and path to the .p8 file from `apple_credentials/config/app_config.json`
2. Test if the API key is valid
3. Provide detailed error messages and troubleshooting tips if there are issues

## Step 3: Update Your Configuration

Update your `apple_credentials/config/app_config.json` file to include the API key information:

```json
"apple_developer": {
  "apple_id": "your.apple.id@example.com",
  "team_id": "YOUR_TEAM_ID",
  "app_specific_password": "your-app-specific-password",
  "app_store_connect_key_id": "YOUR_KEY_ID",
  "app_store_connect_issuer_id": "YOUR_ISSUER_ID",
  "app_store_connect_api_key_path": "/path/to/AuthKey_KEYID.p8"
}
```

## Step 4: Update GitHub Secrets

Run the setup script to update your GitHub secrets:

```bash
python scripts/setup_apple_store.py phase2
```

This will:
1. Process your API key
2. Create or update the necessary GitHub secrets
3. Configure your repository to use the API key authentication method

## Step 5: Verify the Solution

After updating your configuration and GitHub secrets, try running the workflow again. The 401 error should be resolved.

## Common Issues

If you're still experiencing issues, check the following:

1. **Invalid API Key**: Make sure your .p8 file is valid and not corrupted
2. **Incorrect Key ID or Issuer ID**: Double-check these values in App Store Connect
3. **Insufficient Permissions**: Ensure your API key has the "Developer" role assigned
4. **Expired API Key**: API keys expire after 1 year; create a new one if needed

## Further Resources

For more detailed information, see:
- [Apple Notarization Authentication Guide](apple_notarization_guide.md)
- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [App Store Connect API Documentation](https://developer.apple.com/documentation/appstoreconnectapi)
