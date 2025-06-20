# Self-Hosted Runner Setup for macOS M3 Max

This guide explains how to easily switch between GitHub runners and self-hosted runners for macOS PKG builds on your M3 Max machine.

## Quick Switch Guide

To switch from GitHub runners to self-hosted runners, you only need to make **ONE MINOR CHANGE**:

### Option 1: Using GitHub Repository Variables (Recommended)
1. Go to your GitHub repository → Settings → Secrets and variables → Actions → Variables tab
2. Create a new repository variable:
   - **Name**: `MACOS_RUNNER`
   - **Value**: `self-hosted`
3. Save the variable

### Option 2: Direct Workflow Edit
1. Edit `.github/workflows/build-macos.yml`
2. Change line 53 from:
   ```yaml
   runs-on: ${{ vars.MACOS_RUNNER || 'macos-14' }}
   ```
   to:
   ```yaml
   runs-on: self-hosted
   ```

## How It Works

The system automatically detects the runner type and uses appropriate credentials:

### GitHub Runners (Default)
- Uses GitHub secrets: `APPLE_ID`, `APPLE_ID_PASSWORD`, `APPLE_TEAM_ID`
- Uses base64-encoded certificates from secrets
- Runs on `macos-14` virtual machines

### Self-Hosted Runners (M3 Max)
- Uses local credentials from `apple_credentials/config/app_config.json`
- Uses local certificates from `apple_credentials/certificates/`
- Runs on your M3 Max machine with `self-hosted` label

## Prerequisites for Self-Hosted Runner

### 1. Local Credentials Setup
Ensure your `apple_credentials/config/app_config.json` contains:
```json
{
  "apple_developer": {
    "apple_id": "your-apple-id@example.com",
    "team_id": "YOUR_TEAM_ID",
    "p12_password": "your-certificate-password",
    "app_specific_password": "your-app-specific-password"
  }
}
```

### 2. Local Certificates Setup
Ensure these files exist in `apple_credentials/certificates/`:
- `app_cert.p12` - Developer ID Application certificate
- `installer_cert.p12` - Developer ID Installer certificate

### 3. GitHub Self-Hosted Runner Setup
1. Install GitHub Actions runner on your M3 Max:
   ```bash
   # Download the runner
   mkdir actions-runner && cd actions-runner
   curl -o actions-runner-osx-arm64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-osx-arm64-2.311.0.tar.gz
   tar xzf ./actions-runner-osx-arm64-2.311.0.tar.gz
   
   # Configure the runner
   ./config.sh --url https://github.com/YOUR_USERNAME/r2midi --token YOUR_REGISTRATION_TOKEN
   
   # Install and start the service
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

2. Ensure the runner has the `self-hosted` label (this is automatic)

### 4. Required Software on M3 Max
- Xcode Command Line Tools
- Python 3.12
- Git
- Security framework access (for keychain operations)

## Credential Priority

The system uses this priority order:

1. **Local credentials** (if `apple_credentials/config/app_config.json` exists and is valid)
2. **GitHub secrets** (fallback for GitHub runners)

## Security Benefits

### Self-Hosted Runner Advantages:
- ✅ Credentials never leave your machine
- ✅ Certificates stored locally, not in GitHub secrets
- ✅ Full control over build environment
- ✅ Faster builds (no VM startup time)
- ✅ Access to M3 Max performance

### GitHub Runner Advantages:
- ✅ No local setup required
- ✅ Isolated build environment
- ✅ Automatic scaling
- ✅ No local resource usage

## Switching Back to GitHub Runners

To switch back to GitHub runners:

### Option 1: Using Repository Variables
1. Go to repository → Settings → Secrets and variables → Actions → Variables
2. Delete the `MACOS_RUNNER` variable, or change its value to `macos-14`

### Option 2: Direct Workflow Edit
1. Edit `.github/workflows/build-macos.yml`
2. Change the `runs-on` value back to `macos-14`

## Troubleshooting

### Common Issues:

1. **"No valid Apple credentials found"**
   - Check that `apple_credentials/config/app_config.json` exists
   - Verify all required fields are present and not null
   - Ensure the file is valid JSON

2. **"Failed to import local application certificate"**
   - Check that `apple_credentials/certificates/app_cert.p12` exists
   - Verify the p12_password in app_config.json is correct
   - Ensure the certificate is not expired

3. **"No installer signing certificate found"**
   - Check that `apple_credentials/certificates/installer_cert.p12` exists
   - Verify you have a "Developer ID Installer" certificate (not "3rd Party Mac Developer Installer")

4. **Runner not picking up jobs**
   - Ensure the self-hosted runner is online: `./svc.sh status`
   - Check runner logs: `tail -f _diag/Runner_*.log`
   - Verify the runner has the correct labels

### Debug Commands:

```bash
# Check if credentials can be loaded
source .github/scripts/load-apple-credentials.sh

# Check if certificates can be found
ls -la apple_credentials/certificates/

# Validate JSON config
python3 -m json.tool apple_credentials/config/app_config.json

# Check runner status
cd actions-runner && ./svc.sh status
```

## Performance Comparison

| Aspect | GitHub Runner | Self-Hosted M3 Max |
|--------|---------------|-------------------|
| Setup Time | ~2-3 minutes | ~30 seconds |
| Build Speed | Standard | 2-3x faster |
| PKG Creation | 25-60 minutes | 10-25 minutes |
| Security | Cloud-based | Local control |
| Cost | Free (with limits) | Hardware cost |
| Maintenance | None | Runner updates |

## File Structure

```
r2midi/
├── .github/
│   ├── workflows/
│   │   └── build-macos.yml          # Modified to support both runner types
│   └── scripts/
│       ├── setup-certificates.sh    # Modified to support local certificates
│       └── load-apple-credentials.sh # New: Credential loading logic
├── apple_credentials/
│   ├── config/
│   │   └── app_config.json          # Local credentials (self-hosted)
│   └── certificates/
│       ├── app_cert.p12             # Local app certificate
│       └── installer_cert.p12       # Local installer certificate
└── SELF_HOSTED_RUNNER_SETUP.md     # This documentation
```

## Summary

With this setup, you can easily switch between GitHub runners and self-hosted runners with just one variable change. The system automatically detects the environment and uses the appropriate credentials and certificates, providing a seamless experience for both development and production builds.