# Apple Authentication Update

## Changes Made

I've updated the macOS code signing and notarization process to better handle authentication with Apple's services. The key changes include:

1. Enhanced the setup-macos-signing action to:
   - Test API key credentials after storing them
   - Provide more detailed warning messages when falling back to Apple ID authentication
   - Clearly indicate that Apple ID authentication may fail with a 401 error
   - Reference the troubleshooting guide for more information

## Why These Changes Were Made

Apple has restricted the use of Apple ID authentication for notarization operations, especially in automated CI/CD environments. This results in 401 authentication errors with messages like:

```
Error: HTTP status code: 401. Unable to authenticate. The application is not allowed for primary authentication.
```

or

```
Error: HTTP status code: 401. Invalid credentials. Username or password is incorrect. Use the app-specific password generated at appleid.apple.com.
```

These errors occur even when using correct Apple ID credentials with app-specific passwords.

## How to Resolve the 401 Authentication Error

To resolve this issue, you need to switch from Apple ID authentication to App Store Connect API Key authentication. Follow these steps:

1. **Create an App Store Connect API Key**:
   - Go to [App Store Connect](https://appstoreconnect.apple.com/access/api)
   - Click the "Keys" tab
   - Click "+" to create a new API key
   - Give it a name (e.g., "R2MIDI Notarization")
   - Select "Developer" access role
   - Click "Generate"
   - **Download the .p8 file immediately** (you won't be able to download it again)
   - Note the Key ID and Issuer ID

2. **Validate Your API Key**:
   - Run `./validate_api_key.sh`
   - This script will read your configuration from `apple_credentials/config/app_config.json` and test if your API key is valid and working correctly

3. **Update Your Configuration**:
   - Update your `apple_credentials/config/app_config.json` file to include the API key information:
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

4. **Update GitHub Secrets**:
   - Run `python scripts/setup_apple_store.py phase2` to update your GitHub secrets
   - This will process your API key and configure your repository to use the API key authentication method

5. **Run the Workflow Again**:
   - After updating your configuration and GitHub secrets, run the workflow again
   - The 401 error should be resolved

## Additional Resources

For more detailed information, see:
- [Apple Authentication Troubleshooting Guide](apple_auth_troubleshooting.md)
- [Apple Notarization Authentication Guide](apple_notarization_guide.md)
