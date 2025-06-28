# Self-Hosted Runner Setup for macOS-Pkg-Builder

This guide helps you set up a self-hosted GitHub Actions runner that can build macOS PKG files using macOS-Pkg-Builder.

## Prerequisites

### 1. macOS Requirements
- **macOS 10.15+** (Catalina or newer recommended)
- **macOS 12.0+** (Monterey) for best compatibility
- **Minimum 8GB RAM** for building
- **20GB+ free disk space**

### 2. Required Software

#### Xcode Command Line Tools
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Verify installation
xcode-select -p
# Should output: /Applications/Xcode.app/Contents/Developer
# or: /Library/Developer/CommandLineTools
```

#### Python 3.8+
```bash
# Check current version
python3 --version

# Install Python 3.12 (recommended)
# Option 1: Using Homebrew
brew install python@3.12

# Option 2: Download from python.org
# Visit https://www.python.org/downloads/
```

#### Git (usually pre-installed)
```bash
# Verify Git
git --version
```

### 3. Development Certificates

Your self-hosted runner needs access to Apple Developer certificates:

```bash
# Import your Developer ID certificates
security import /path/to/DeveloperID_Application.p12 -P "password"
security import /path/to/DeveloperID_Installer.p12 -P "password"

# Verify certificates are available
security find-identity -v -p codesigning
```

## GitHub Actions Runner Setup

### 1. Download and Configure Runner

1. Go to your repository → Settings → Actions → Runners
2. Click "New self-hosted runner"
3. Select macOS and follow the setup instructions

```bash
# Example setup commands (use your actual token)
mkdir actions-runner && cd actions-runner
curl -o actions-runner-osx-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-osx-x64-2.311.0.tar.gz
tar xzf ./actions-runner-osx-x64-2.311.0.tar.gz
./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN
```

### 2. Configure Runner Labels

Add labels to identify your runner:
```bash
./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN --labels macos-pkg-builder,self-hosted,macOS
```

### 3. Run as Service (Recommended)

```bash
# Install as LaunchDaemon
sudo ./svc.sh install

# Start the service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status
```

## Environment Verification

Run our environment checker to verify everything is set up correctly:

```bash
# Clone your repository
git clone https://github.com/YOUR_ORG/YOUR_REPO.git
cd YOUR_REPO

# Check environment
chmod +x scripts/check-runner-environment.sh
./scripts/check-runner-environment.sh
```

Expected output:
```
✅ macOS version is compatible (12.0+)
✅ Python 3 found: 3.12.0
✅ pip3 found: 23.0.1
✅ All required development tools are available
✅ PyPI is accessible
✅ pip install test successful
✅ Sufficient disk space: 45GB available

🎉 Environment is ready for macOS-Pkg-Builder!
```

## Troubleshooting

### Common Issues

#### 1. "Command not found: codesign"
```bash
# Install Xcode Command Line Tools
xcode-select --install

# If already installed, reset path
sudo xcode-select --reset
```

#### 2. "Permission denied" during pip install
```bash
# Use user install
pip3 install --user macos-pkg-builder

# Or fix permissions
sudo chown -R $(whoami) /usr/local/lib/python3.*/site-packages/
```

#### 3. "Cannot reach PyPI"
```bash
# Check network connectivity
curl -I https://pypi.org

# If behind proxy, configure pip
pip3 config set global.proxy https://your-proxy:port
```

#### 4. Certificate issues
```bash
# List available certificates
security find-identity -v

# Import certificates to login keychain
security import certificate.p12 -k ~/Library/Keychains/login.keychain-db

# Set partition list for automatic access
security set-key-partition-list -S apple-tool:,apple: -s -k "keychain-password" certificate.p12
```

## GitHub Workflow Configuration

Update your workflow to use the self-hosted runner:

```yaml
jobs:
  build-macos:
    runs-on: self-hosted  # or your custom label
    # ... rest of your workflow
```

## Monitoring and Maintenance

### Check Runner Health
```bash
# View runner logs
tail -f _diag/Runner_*.log

# Check system resources
top -l 1 | head -20
df -h
```

### Regular Maintenance
```bash
# Update Python packages
pip3 install --upgrade pip
pip3 install --upgrade macos-pkg-builder

# Clean up old builds
cd YOUR_REPO
./scripts/cleanup-old-build-scripts.sh

# Update Xcode Command Line Tools (when available)
softwareupdate -l
```

## Security Considerations

1. **Isolate the runner** - Use a dedicated machine or VM
2. **Limit repository access** - Only add to repositories that need it
3. **Regular updates** - Keep macOS, Python, and tools updated
4. **Certificate security** - Store certificates securely, rotate regularly
5. **Network security** - Ensure proper firewall and VPN configuration

## Performance Optimization

1. **SSD storage** - Use SSD for faster builds
2. **RAM** - 16GB+ recommended for large projects
3. **Dedicated runner** - Don't run other resource-intensive tasks
4. **Clean builds** - Regular cleanup prevents disk space issues

This setup will allow your self-hosted runner to successfully build PKG files using macOS-Pkg-Builder with the same reliability as GitHub's hosted runners.
