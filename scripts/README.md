# GitHub Secrets Manager for R2MIDI macOS Signing

Complete automation tool for setting up GitHub repository secrets needed for macOS code signing and notarization.

## Quick Start

### Normal Usage (Idempotent)
```bash
# Only updates missing or changed secrets
./scripts/quick_start.sh
```

### Force Update All Secrets
```bash  
# Updates ALL secrets regardless of current state
./scripts/quick_start.sh --force
```

## Available Scripts

### 1. `scripts/setup_github_secrets.py` (Main Script)
The core idempotent secrets manager that handles all GitHub API operations.

**Usage:**
```bash
python scripts/setup_github_secrets.py [--force]
```

**Options:**
- `--force`, `-f`: Force update all secrets even if they already exist

### 2. `scripts/setup_complete_github_secrets.sh` (Wrapper)
Complete setup script that handles dependencies and runs the main script.

**Usage:**
```bash
./scripts/setup_complete_github_secrets.sh [--force]
```

### 3. `scripts/quick_start.sh` (Interactive)
Interactive setup with configuration testing and user prompts.

**Usage:**
```bash
./scripts/quick_start.sh [--force]
```

### 4. `scripts/test_github_setup.py` (Validator)
Tests configuration and prerequisites without making changes.

**Usage:**
```bash
python scripts/test_github_setup.py
```

## When to Use Force Mode

### 🔥 Use `--force` When:

1. **Certificate Changes**: You've renewed or changed your Apple Developer certificates
2. **Password Updates**: You've changed your P12 password or app-specific password
3. **Credential Refresh**: You want to refresh all credentials for security
4. **Troubleshooting**: Some secrets may be corrupted or not working properly
5. **Config Changes**: You've updated values in `app_config.json`
6. **Fresh Start**: You want to ensure all secrets are current

### ✅ Normal Mode (Default) When:

1. **First Time Setup**: Setting up secrets for the first time
2. **Adding Missing Secrets**: Only some secrets are missing
3. **Regular Usage**: Most common scenario for ongoing use
4. **CI/CD Integration**: Automated runs that should be safe and fast

## What Gets Updated

### Required for macOS Signing:
- `APPLE_DEVELOPER_ID_APPLICATION_CERT` (base64 of app_cert.p12)
- `APPLE_DEVELOPER_ID_INSTALLER_CERT` (base64 of installer_cert.p12)
- `APPLE_CERT_PASSWORD` (P12 password)
- `APPLE_ID` (Apple Developer account email)
- `APPLE_ID_PASSWORD` (App-specific password)
- `APPLE_TEAM_ID` (Apple Developer Team ID)

### Optional App Store Connect:
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID` 
- `APP_STORE_CONNECT_API_KEY` (base64 of .p8 file)

### Build Configuration:
- `ENABLE_APP_STORE_BUILD`
- `ENABLE_APP_STORE_SUBMISSION`
- `ENABLE_NOTARIZATION`

### App Information:
- `APP_BUNDLE_ID_PREFIX`
- `APP_AUTHOR_NAME`
- `APP_AUTHOR_EMAIL`

## Configuration Source

All secrets are generated from:
- `apple_credentials/config/app_config.json` - Main configuration
- P12 certificate files (app_cert.p12, installer_cert.p12)
- App Store Connect API key (.p8 file)

## Examples

### Example 1: First Time Setup
```bash
# Normal idempotent setup
./scripts/quick_start.sh
```

### Example 2: Certificate Renewal
```bash
# After renewing Apple Developer certificates
./scripts/quick_start.sh --force
```

### Example 3: Troubleshooting
```bash
# If builds are failing due to secret issues
python scripts/setup_github_secrets.py --force
```

### Example 4: Testing Only
```bash
# Just test configuration without changes
python scripts/test_github_setup.py
```

## Output Differences

### Normal Mode Output:
```
✅ Created secret: APPLE_DEVELOPER_ID_APPLICATION_CERT
✅ Updated secret: APPLE_ID
ℹ️  Created: 8, Updated: 5
```

### Force Mode Output:
```
🔥 FORCE updated secret: APPLE_DEVELOPER_ID_APPLICATION_CERT
🔥 FORCE updated secret: APPLE_ID
🔥 Force updated: 13 secrets
```

## Security Notes

- Force mode re-encrypts all secrets with fresh values
- All secrets are encrypted using repository's public key
- No secrets are stored locally after upload
- P12 certificates are re-encoded from source files
- Safe to run multiple times in either mode

## Troubleshooting

### If secrets aren't working:
```bash
./scripts/quick_start.sh --force
```

### If configuration is wrong:
```bash
python scripts/test_github_setup.py
```

### If certificates are missing:
```bash
cd .github/scripts
./setup-macos-signing.sh
```

## Integration

Works with GitHub Actions workflow in `.github/workflows/build-macos.yml` that expects these exact secret names for automated macOS code signing and notarization.
