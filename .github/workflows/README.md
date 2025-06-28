# R2MIDI GitHub Actions Workflows

A script-based, maintainable CI/CD pipeline for building, testing, and distributing R2MIDI applications across all platforms.

## 🏗️ Current Architecture

The R2MIDI project uses **script-based workflows** with centralized shell scripts:

```
CI (ci.yml) → Cross-platform testing and validation
├── Build Linux (build-linux.yml) → Linux application builds
├── Build macOS (build-macos.yml) → macOS application builds (signed)
├── Build Windows (build-windows.yml) → Windows application builds
├── Build Main (build.yml) → Legacy multi-platform build
└── Release (release.yml) → Production releases with PyPI publishing
```

## 📋 Workflow Details

### 1. CI Workflow (`ci.yml`)

**Purpose**: Continuous integration for all branches

**Triggers**:
- Push to: `master`, `develop`
- Pull requests to: `master`, `develop`
- Manual dispatch with skip options

**Jobs**:
- **Test**: Python 3.12 on Linux, Windows, macOS
- **Lint**: Code quality checks (report-only, non-blocking)
- **Security**: Safety and bandit security scans
- **Build Test**: Validate build configuration on all platforms

**Features**:
- Skip controls via inputs or commit messages (`[skip tests]`, `[skip lint]`)
- Coverage reporting to Codecov
- Cross-platform validation

### 2. Platform Build Workflows

#### macOS Build (`build-macos.yml`)
- **Signing**: Apple Developer ID (production) or unsigned (dev)
- **Output**: DMG and PKG installers
- **Features**: Code signing, notarization, Gatekeeper compatibility

#### Linux Build (`build-linux.yml`)
- **Output**: DEB packages, TAR.GZ archives, AppImage (if available)
- **Features**: Universal Linux compatibility

#### Windows Build (`build-windows.yml`)
- **Output**: ZIP portable apps, MSI installers (if available)
- **Features**: Portable applications, no admin required

### 3. Release Workflow (`release.yml`)

**Purpose**: Production releases with full pipeline

**Triggers**:
- Push to: `master` branch
- Manual dispatch with version control

**Features**:
- Automatic version management (patch/minor/major/none)
- Cross-platform builds using reusable workflows
- PyPI publishing with OIDC trusted publishing
- GitHub release creation with comprehensive changelogs

### 4. Legacy Build Workflow (`build.yml`)

**Purpose**: Comprehensive build and test pipeline

**Features**:
- Version auto-increment on master
- Cross-platform testing
- Python package building
- macOS signing with PyInstaller

## 🔧 Script-Based Architecture

All workflows use centralized scripts from `.github/scripts/`:

### Core Setup Scripts
- **`setup-environment.sh`** - Environment configuration, Git setup, PYTHONPATH
- **`install-system-dependencies.sh`** - Platform-specific system packages
- **`install-python-dependencies.sh`** - Python packages by build type

### Build Scripts
- **`extract-version.sh`** - Version extraction and GitHub outputs
- **`build-briefcase-apps.sh`** - Cross-platform Briefcase builds
- **`build-python-package.sh`** - PyPI package building

### Platform Packaging Scripts
- **`package-macos-apps.sh`** - macOS DMG/PKG creation and verification
- **`package-linux-apps.sh`** - Linux package creation (DEB/TAR.GZ/AppImage)
- **`package-windows-apps.sh`** - Windows ZIP/MSI packaging

### Signing and Security Scripts
- **`sign-and-notarize-macos.sh`** - Apple code signing and notarization
- **`validate-build-environment.sh`** - Pre-build environment validation

### Utility Scripts
- **`update-version.sh`** - Automated version management
- **`validate-project-structure.sh`** - Project integrity checks
- **`prepare-release-artifacts.sh`** - Release artifact organization
- **`generate-build-summary.sh`** - Consistent build reporting
- **`make-scripts-executable.sh`** - Script permission management
- **`validate-refactoring.sh`** - Workflow validation

## 🐍 Python Dependency Build Types

The `install-python-dependencies.sh` script supports multiple build types:

- **`production`** - Briefcase + project requirements
- **`development`** - Production + dev tools (black, flake8, pytest, mypy)
- **`testing`** - Minimal testing dependencies
- **`ci`** - All CI tools including security scanners
- **`package`** - Only packaging tools (build, twine)

## 🔐 Required Secrets

### macOS Code Signing
```
APPLE_CERTIFICATE_P12        # Base64 Developer ID certificate (.p12)
APPLE_CERTIFICATE_PASSWORD   # Certificate password
APPLE_ID                     # Apple Developer email
APPLE_ID_PASSWORD            # App-specific password
APPLE_TEAM_ID                # Developer Team ID
```

### PyPI Publishing
Uses OIDC trusted publishing (no secrets required for production)

## 🚀 Usage Examples

### Development Workflow
```bash
# Feature development - triggers CI
git checkout -b feature/new-feature
git push origin feature/new-feature

# Pull request - runs full CI suite
gh pr create --title "New Feature" --body "Description"
```

### Release Workflow
```bash
# Production release with auto-versioning
git checkout master
git merge develop
git push origin master  # → Triggers release.yml

# Manual release with version control
gh workflow run release.yml \
  --field version-type=minor \
  --field build-type=production
```

### Manual Platform Builds
```bash
# Build specific platform
gh workflow run build-macos.yml \
  --field version=1.2.3 \
  --field build-type=production

gh workflow run build-linux.yml \
  --field build-type=dev
```

## 📊 Build Matrix

| Platform | Development | Production | Code Signing | Artifacts |
|----------|-------------|------------|--------------|-----------|
| Linux    | ✅ CI/Test  | ✅ Release | ❌ Unsigned  | DEB, TAR.GZ, AppImage |
| Windows  | ✅ CI/Test  | ✅ Release | ❌ Unsigned  | ZIP, MSI |
| macOS    | ✅ CI/Test  | ✅ Release | ✅ Signed    | DMG, PKG |
| Python   | ✅ CI/Test  | ✅ PyPI    | ✅ OIDC      | Wheel, Source |

## 🛠️ Local Development

All scripts can be run locally for testing:

```bash
# Set up environment
./.github/scripts/setup-environment.sh

# Install dependencies for development
./.github/scripts/install-python-dependencies.sh development

# Validate build environment
./.github/scripts/validate-build-environment.sh linux

# Build applications
./.github/scripts/build-briefcase-apps.sh linux unsigned

# Generate build summary
./.github/scripts/generate-build-summary.sh linux dev 1.0.0 unsigned
```

## 🔍 Validation and Testing

```bash
# Make all scripts executable
./.github/scripts/make-scripts-executable.sh

# Validate the entire workflow setup
./.github/scripts/validate-refactoring.sh

# Test individual script functionality
bash -n ./.github/scripts/setup-environment.sh  # Syntax check
./.github/scripts/extract-version.sh             # Version extraction
```

## 🔄 Version Management

- **Automatic**: Patch increment on master push (build.yml)
- **Manual**: Choose major/minor/patch/none (release.yml)
- **Format**: Semantic versioning `{major}.{minor}.{patch}`
- **Source**: `server/version.py` → `__version__ = "x.y.z"`

## ⚡ Performance Optimizations

- **Script-based**: Eliminates inline code duplication
- **Conditional installs**: Platform-specific dependencies only
- **Parallel builds**: Matrix strategy for multi-platform
- **Caching**: pip cache for Python dependencies
- **Artifact management**: Retention policies by build type

## 🔧 Customization

### Adding a New Platform
1. Update build matrices in workflow files
2. Add platform logic to `install-system-dependencies.sh`
3. Create new `package-{platform}-apps.sh` script
4. Update `generate-build-summary.sh` for platform-specific output

### Adding Build Types
1. Add new case to `install-python-dependencies.sh`
2. Update workflow inputs and documentation
3. Adjust artifact retention and naming

### Modifying Dependencies
1. Edit `install-system-dependencies.sh` for system packages
2. Edit `install-python-dependencies.sh` for Python packages
3. Test with `validate-build-environment.sh`

## 📚 Documentation

- **Setup**: See individual script headers for usage
- **Troubleshooting**: Check `validate-refactoring.sh` output
- **Architecture**: [REFACTORING_SUMMARY.md](../REFACTORING_SUMMARY.md)

## 📈 Migration from v3.x

The workflows have been refactored from inline code to script-based:

- **Before**: ~275 lines of duplicated inline code
- **After**: Centralized, reusable shell scripts
- **Benefits**: Better maintainability, consistency, local testing
- **Compatibility**: All external interfaces preserved

---

*Architecture version: 4.0 (Script-based workflows)*  
*Last updated: December 2024*
