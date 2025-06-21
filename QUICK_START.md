# R2MIDI Enhanced Build System - Quick Start

## 🚀 Quick Setup

```bash
# 1. Validate system
./validate-build-system.sh

# 2. Setup environments
./clean-environment.sh
./setup-virtual-environments.sh

# 3. Test setup
./test_environments.sh

# 4. Build applications
./build-all-local.sh --dev --no-sign
```

## 📦 Build Outputs

After successful build, check the `artifacts/` directory:
- `R2MIDI-Client-VERSION.pkg` - Client installer
- `R2MIDI-Server-VERSION.pkg` - Server installer

## 🔧 Common Commands

```bash
# Development build (unsigned)
./build-all-local.sh --dev --no-sign

# Production build (requires certificates)
./build-all-local.sh --version 1.0.0

# Clean environment
./clean-environment.sh --deep

# Setup with UV (faster)
./setup-virtual-environments.sh --use-uv
```

## 🆘 Troubleshooting

1. **Python version**: Requires Python 3.10+
2. **Virtual environments**: Run `./setup-virtual-environments.sh`
3. **Build failures**: Check `./test_environments.sh`
4. **Signing issues**: Verify Apple Developer certificates

## 📋 GitHub Actions

Push to `main` or `develop` branch to trigger CI builds.
Artifacts will be available in the Actions tab.

---

For detailed documentation, see the full project README.
