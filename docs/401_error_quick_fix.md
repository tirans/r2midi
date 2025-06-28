# Quick Fix for 401 Authentication Error

If you're seeing this error:

```
⚠️ App Store Connect API key credentials not provided.
Apple has restricted Apple ID authentication for notarization in CI/CD environments.
It is strongly recommended to use App Store Connect API key authentication.

Error: HTTP status code: 401. Invalid credentials. Username or password is incorrect.
```

Follow these steps to resolve it:

## Step 1: Create an App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/access/api)
2. Click the "Keys" tab
3. Click "+" to create a new API key
4. Name it "R2MIDI Notarization"
5. Select "Developer" access role
6. Click "Generate"
7. **Download the .p8 file immediately** (you won't be able to download it again)
8. Note the Key ID and Issuer ID

## Step 2: Place the API Key File

1. Put the .p8 file in the `apple_credentials/app_store_connect/` directory
2. Make sure it follows the naming convention: `AuthKey_KEYID.p8`

## Step 3: Update Configuration

Edit `apple_credentials/config/app_config.json` and add these fields:

```json
"apple_developer": {
  "apple_id": "your.apple.id@example.com",
  "team_id": "YOUR_TEAM_ID",
  "app_specific_password": "your-app-specific-password",
  "app_store_connect_key_id": "YOUR_KEY_ID",
  "app_store_connect_issuer_id": "YOUR_ISSUER_ID",
  "app_store_connect_api_key_path": "/full/path/to/apple_credentials/app_store_connect/AuthKey_KEYID.p8"
}
```

Replace the placeholder values with your actual information.

## Step 4: Validate Your API Key

Run the validation script:

```bash
./validate_api_key.sh
```

The script will automatically read the configuration from `apple_credentials/config/app_config.json` and validate your API key.

## Step 5: Update GitHub Secrets

Run the setup script:

```bash
python scripts/setup_apple_store.py phase2
```

This will update your GitHub secrets with the API key information.

## Step 6: Run the Workflow Again

The 401 error should now be resolved.

## Need More Help?

See the detailed [Apple Authentication Troubleshooting Guide](apple_auth_troubleshooting.md) for more information.
