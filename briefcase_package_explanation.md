# Yes! Briefcase has a `package` command! 📦

## Key Differences Between `briefcase build` and `briefcase package`:

**`briefcase build`:**
- Creates the app bundle (.app file)
- Basic compilation and assembly
- Uses ad-hoc signing by default (development only)
- No distribution packaging
- Good for development and testing

**`briefcase package`:**
- Builds AND packages for distribution
- Supports proper code signing with Developer ID certificates
- Creates distribution formats: ZIP, DMG, PKG
- Includes notarization support
- Ready for distribution to end users

## Examples from this R2MIDI project:

**In GitHub Actions workflow (.github/workflows/build-macos.yml):**
```bash
# Package server app with Developer ID signing
briefcase package macos app -a server

# Package client app with Developer ID signing  
briefcase package macos app -a r2midi-client
```

**In local test script (scripts/test_pkg_build_locally.sh):**
```bash
# Package server app (includes build + proper signing)
briefcase package macos app -a server

# Package client app (includes build + proper signing)
briefcase package macos app -a r2midi-client
```

## Package Command Options:

```bash
# Basic packaging
briefcase package macos app -a myapp

# With specific signing identity
briefcase package macos app -a myapp -i "Developer ID Application: Your Name"

# Create PKG installer
briefcase package macos app -a myapp -p pkg

# Create DMG
briefcase package macos app -a myapp -p dmg

# Ad-hoc signing (development only)
briefcase package macos app -a myapp --adhoc-sign

# Update before packaging
briefcase package macos app -a myapp -u
```

## When to use `package` vs `build`:

- **Use `briefcase build`**: During development, testing, debugging
- **Use `briefcase package`**: For distribution, CI/CD, release builds

## Why we switched to `package` in this project:

The GitHub Actions was failing because it used `briefcase build` which defaults to ad-hoc signing. By switching to `briefcase package`, it now uses the configured Developer ID certificate from pyproject.toml:

```toml
codesign_identity = "Developer ID Application: Tiran Efrat (79449BGAM5)"
```

This resolves the signing errors and creates properly signed apps ready for distribution! ✅

## Summary:

Yes, briefcase definitely has a `package` command! It's the recommended command for creating distribution-ready applications with proper signing and packaging. The `build` command is more for development, while `package` is for production releases.