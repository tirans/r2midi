# Local PKG Build Testing Guide

This guide provides instructions for testing the macOS PKG build process locally on your development machine.

## Quick Start

```bash
# Make the script executable
chmod +x scripts/test_pkg_build_locally.sh

# Run the test (uses defaults: version 0.1.181, build type 'dev')
./scripts/test_pkg_build_locally.sh

# Or specify version and build type
./scripts/test_pkg_build_locally.sh 1.0.0 production
```

## Prerequisites

### Required Software

1. **macOS** - This script only works on macOS
2. **Python 3.12+** - Install from [python.org](https://python.org)
3. **Briefcase** - Install with: `pip install briefcase`
4. **Xcode Command Line Tools** - Install with: `xcode-select --install`

### Optional (for production builds)

1. **Apple Developer Account** with certificates
2. **Developer ID Application Certificate** (for app signing)
3. **Developer ID Installer Certificate** (for PKG signing)

## Setup Instructions

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install briefcase

# Install project dependencies
pip install -r requirements.txt
pip install -r r2midi_client/requirements.txt

# Verify installation
python -c "import briefcase; print('Briefcase installed successfully')"
```

### 2. Apple Developer Certificates (Optional)

#### Option A: Use Local Certificate Files

If you have certificate files, place them in:
```
apple_credentials/
├── certificates/
│   ├── app_cert.p12
│   └── installer_cert.p12
└── config/
    └── app_config.json
```

#### Option B: Install Certificates in Keychain

1. Download certificates from Apple Developer Portal
2. Double-click to install in Keychain Access
3. Verify with: `security find-identity -v -p codesigning`

### 3. Environment Variables (Optional)

For notarization testing, set these environment variables:

```bash
export APPLE_ID="your-apple-id@example.com"
export APPLE_ID_PASSWORD="your-app-specific-password"
export APPLE_TEAM_ID="YOUR_TEAM_ID"
```

## Usage Examples

### Basic Development Build

```bash
# Simple test build (no signing, no notarization)
./scripts/test_pkg_build_locally.sh
```

### Production Build with Signing

```bash
# Set Apple credentials
export APPLE_ID="dev@example.com"
export APPLE_ID_PASSWORD="abcd-efgh-ijkl-mnop"
export APPLE_TEAM_ID="ABC123DEF4"

# Run production build
./scripts/test_pkg_build_locally.sh 1.0.0 production
```

### Custom Version and Build Type

```bash
# Development build with custom version
./scripts/test_pkg_build_locally.sh 0.2.0 dev

# Staging build
./scripts/test_pkg_build_locally.sh 0.2.0 staging
```

## What the Script Does

The local testing script performs the same steps as the GitHub Actions workflow:

1. **Prerequisites Check** - Verifies all required tools are installed
2. **Apple Setup Check** - Checks for certificates and credentials
3. **Certificate Setup** - Configures certificates if available
4. **Signing Configuration** - Sets up briefcase signing and entitlements
5. **Application Build** - Builds both server and client apps with briefcase
6. **PKG Creation** - Creates PKG installers (signed if certificates available)
7. **Validation** - Verifies the created PKG files

## Output

### Successful Build

```
🧪 R2MIDI Local PKG Build Test
================================
Version: 0.1.181
Build Type: dev

🔹 Checking prerequisites...
✅ All prerequisites available

🔹 Checking Apple Developer setup...
✅ Found 1 Developer ID Application certificate(s)
⚠️ No Developer ID Installer certificates found

🔹 Setting up certificates...
✅ Found local certificate files

🔹 Configuring signing and entitlements...
✅ Briefcase signing configuration completed successfully

🔹 Building applications...
✅ Server app built successfully
✅ Client app built successfully

🔹 Creating PKG installers...
✅ Server PKG created
✅ Client PKG created

🔹 Validating results...
✅ 2 PKG installer(s) created

Created PKG files:
  📦 R2MIDI-Server-0.1.181-dev.pkg (45M)
     ⚠️ Unsigned (test build)
  📦 R2MIDI-Client-0.1.181-dev.pkg (42M)
     ⚠️ Unsigned (test build)

Built applications:
  🖥️ R2MIDI Server.app
  🖥️ R2MIDI Client.app

✅ Local PKG build test completed successfully!
```

### Output Locations

After a successful build, you'll find:

```
artifacts/
├── R2MIDI-Server-0.1.181-dev.pkg
└── R2MIDI-Client-0.1.181-dev.pkg

build/
├── server/macos/app/R2MIDI Server.app
└── r2midi-client/macos/app/R2MIDI Client.app
```

## Troubleshooting

### Common Issues

#### 1. "briefcase: command not found"

```bash
# Install briefcase
pip install briefcase

# Or if using a virtual environment
source your-venv/bin/activate
pip install briefcase
```

#### 2. "No Developer ID Application certificates found"

This is normal for development builds. The script will use ad-hoc signing.

For production builds:
- Install certificates in Keychain Access
- Or place certificate files in `apple_credentials/` directory

#### 3. "PKG creation will be limited or may fail"

This happens when you don't have a "Developer ID Installer" certificate.

Solutions:
- Get a Developer ID Installer certificate from Apple
- Use DMG distribution instead
- Continue with unsigned PKG for testing

#### 4. "Application build failed"

Check the briefcase build logs for specific errors:

```bash
# Check recent build logs
ls -la logs/briefcase.*.build.log | tail -1
tail -50 logs/briefcase.*.build.log
```

Common build issues:
- Missing dependencies: `pip install -r requirements.txt`
- Signing issues: Run `python scripts/fix_macos_signing.py`
- PyQt6 issues: The script includes automatic fixes

#### 5. Code Signing Errors

If you encounter signing errors:

```bash
# Run the signing fix script
python scripts/fix_macos_signing.py

# Then retry the build
./scripts/test_pkg_build_locally.sh
```

### Debug Mode

For more detailed output, you can modify the script or run individual steps:

```bash
# Check what certificates are available
security find-identity -v -p codesigning

# Test briefcase build manually
briefcase build macos app -a server

# Check signing configuration
python scripts/configure_briefcase_signing.py
python scripts/select_entitlements.py
```

## Advanced Usage

### Testing Different Configurations

#### Test with Ad-hoc Signing Only

```bash
# Temporarily remove certificates to test ad-hoc signing
security delete-keychain build.keychain 2>/dev/null || true
./scripts/test_pkg_build_locally.sh
```

#### Test with Specific Entitlements

```bash
# Force use of specific entitlements
cp entitlements.plist entitlements_test.plist
# Edit entitlements_test.plist as needed
# Update pyproject.toml to use entitlements_test.plist
./scripts/test_pkg_build_locally.sh
```

### Integration with CI/CD

You can use this script as a basis for local CI/CD testing:

```bash
# Create a simple CI test
#!/bin/bash
set -e

echo "Running local CI test..."
./scripts/test_pkg_build_locally.sh 1.0.0 production

echo "Testing PKG installation..."
# Add your PKG testing logic here

echo "Local CI test completed!"
```

## Comparison with GitHub Actions

| Feature | Local Script | GitHub Actions |
|---------|-------------|----------------|
| Certificate Setup | ✅ Automatic | ✅ Automatic |
| App Building | ✅ Sequential | ✅ Parallel |
| PKG Creation | ✅ Basic/Full | ✅ Full |
| Notarization | ✅ Optional | ✅ Yes |
| Artifact Upload | ❌ Local only | ✅ Yes |
| Build Time | ~5-10 min | ~8-12 min |

## Next Steps

After successful local testing:

1. **Test the PKG installers** - Install them on a clean macOS system
2. **Verify app functionality** - Ensure both server and client work correctly
3. **Production deployment** - Use GitHub Actions for official releases
4. **Distribution** - Upload signed PKGs to your distribution platform

## Getting Help

If you encounter issues:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the build logs in the `logs/` directory
3. Run the individual configuration scripts to isolate issues
4. Check the [macOS signing solution documentation](MACOS_SIGNING_SOLUTION.md)

## Script Options

```bash
# Show help
./scripts/test_pkg_build_locally.sh --help

# Available options
./scripts/test_pkg_build_locally.sh [version] [build_type]

# Where:
#   version    = Application version (default: 0.1.181)
#   build_type = dev, staging, or production (default: dev)
```

This local testing script provides a reliable way to test your PKG build process before pushing to GitHub Actions, saving time and ensuring your builds work correctly.