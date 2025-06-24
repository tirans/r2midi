# Script Usage Analysis Report

## Current State Analysis

### Scripts Referenced by GitHub Actions Workflows

#### build-macos.yml (WORKING)
**Currently Used Scripts:**
- `.github/scripts/detect-runner.sh` ✅ (exists)
- `.github/scripts/clean-app.sh` ✅ (exists) 
- `scripts/bulletproof_clean_app_bundle.py` ✅ (exists)
- `clean-environment.sh` ✅ (exists in root)
- `setup-virtual-environments.sh` ✅ (exists in root)
- `test_environments.sh` ✅ (exists in root)
- `test-signing-environment.sh` ✅ (exists in root)
- `build-all-local.sh` ✅ (exists in root)

#### build-linux.yml (BROKEN)
**Missing Scripts:**
- `.github/scripts/extract-version.sh` ❌ (REMOVED)
- `.github/scripts/validate-build-environment.sh` ❌ (REMOVED)
- `.github/scripts/install-system-dependencies.sh` ❌ (REMOVED)
- `.github/scripts/install-python-dependencies.sh` ❌ (REMOVED)
- `.github/scripts/build-briefcase-apps.sh` ❌ (REMOVED)
- `.github/scripts/package-linux-apps.sh` ❌ (REMOVED)
- `.github/scripts/generate-build-summary.sh` ❌ (REMOVED)

#### build-windows.yml (BROKEN)
**Missing Scripts:**
- `.github/scripts/extract-version.sh` ❌ (REMOVED)
- `.github/scripts/validate-build-environment.sh` ❌ (REMOVED)
- `.github/scripts/install-python-dependencies.sh` ❌ (REMOVED)
- `.github/scripts/build-briefcase-apps.sh` ❌ (REMOVED)
- `.github/scripts/package-windows-apps.sh` ❌ (REMOVED)
- `.github/scripts/generate-build-summary.sh` ❌ (REMOVED)

#### ci.yml (BROKEN)
**Missing Scripts:**
- `.github/scripts/setup-environment.sh` ❌ (REMOVED)
- `.github/scripts/install-system-dependencies.sh` ❌ (REMOVED)
- `.github/scripts/install-python-dependencies.sh` ❌ (REMOVED)
- `.github/scripts/validate-project-structure.sh` ❌ (REMOVED)

### Scripts Referenced by Local Build Scripts

#### build-all-local.sh
**Currently Used Scripts:**
- `.github/scripts/sign-notarize.sh` ✅ (exists)

### Root Directory Scripts Analysis

#### ACTIVELY USED (Referenced by workflows/builds):
- `build-all-local.sh` ✅ (main build script)
- `clean-environment.sh` ✅ (used by macOS workflow)
- `setup-virtual-environments.sh` ✅ (used by macOS workflow)
- `test_environments.sh` ✅ (used by macOS workflow)
- `test-signing-environment.sh` ✅ (used by macOS workflow)

#### ACTIVELY USED (Referenced by workflows/builds):
- `setup-local-certificates.sh` ✅ (used by build-all-local.sh)

#### UNUSED (Not referenced anywhere):
- `build-client-local.sh` ❌ (not called by build-all-local.sh)
- `build-server-local.sh` ❌ (not called by build-all-local.sh)

#### LIKELY UNUSED (Documentation/Development):
- `BULLETPROOF_SIGNING_SOLUTION.md` ❌ (documentation)
- `CERTIFICATE_SETUP_REPORT.md` ❌ (documentation)
- `CHANGELOG.md` ❌ (documentation)
- `CODE_OF_CONDUCT.md` ❌ (documentation)
- `CONTRIBUTING.md` ❌ (documentation)
- `FIXED_XATTR_ISSUE.md` ❌ (documentation)
- `GITHUB_ACTIONS_SIGNING_FIX.md` ❌ (documentation)
- `GITHUB_README.md` ❌ (documentation)
- `PRIVACY.md` ❌ (documentation)
- `QUICK_START.md` ❌ (documentation)
- `SECURITY.md` ❌ (documentation)
- `SIGNING_ANALYSIS_SUMMARY.md` ❌ (documentation)
- `SIGNING_FIX_DOCUMENTATION.md` ❌ (documentation)
- `SIGNING_SOLUTION_GUIDE.sh` ❌ (documentation/guide)
- `analysis_sign_notarize_separation.md` ❌ (documentation)

#### DEVELOPMENT/TESTING SCRIPTS (Likely unused in production):
- `check-build-error.sh` ❌ (debugging)
- `clean-for-signing.sh` ❌ (development)
- `cleanup-and-test.sh` ❌ (development)
- `cleanup-signing-scripts.sh` ❌ (development)
- `commit-signing-fixes.sh` ❌ (development)
- `diagnose-build.sh` ❌ (debugging)
- `emergency-fix-python-framework.sh` ❌ (emergency fix)
- `fix-signing.sh` ❌ (development)
- `make-signing-scripts-executable.sh` ❌ (development)
- `quick-fix-certs.sh` ❌ (development)
- `test-build-system.sh` ❌ (testing)
- `test-build.sh` ❌ (testing)
- `test-signing-fix.sh` ❌ (testing)
- `test_fixes.sh` ❌ (testing)

### /scripts Directory Analysis

#### ACTIVELY USED:
- `bulletproof_clean_app_bundle.py` ✅ (used by macOS workflow)

#### POTENTIALLY USEFUL (Development/Setup):
- `certificate_manager.py` ⚠️ (certificate management)
- `configure_briefcase_signing.py` ⚠️ (briefcase configuration)
- `generate_icons.py` ⚠️ (icon generation)
- `setup_apple_store.py` ⚠️ (App Store setup)
- `setup_github_secrets.py` ⚠️ (GitHub secrets setup)
- `update_pyproject.py` ⚠️ (project configuration)
- `validate_pyproject.py` ⚠️ (project validation)

#### LIKELY UNUSED:
- `README.md` ❌ (documentation)
- `apply_fix.sh` ❌ (development)
- `clean-app-bundles.sh` ❌ (development)
- `cleanup.sh` ❌ (development)
- `debug_certificates.sh` ❌ (debugging)
- `install_dependencies.sh` ❌ (development)
- `list_github_secrets.py` ❌ (development)
- `make_all_executable.sh` ❌ (development)
- `make_executable.sh` ❌ (development)
- `quick_macos_setup.sh` ❌ (development)
- `quick_start.sh` ❌ (development)
- `requirements.txt` ❌ (development)
- `run_secrets_manager.sh` ❌ (development)
- `security_scan.py` ❌ (development)
- `select_entitlements.py` ❌ (development)
- `setup_complete_github_secrets.sh` ❌ (development)
- `setup_secrets.sh` ❌ (development)
- `test_encryption_fix.py` ❌ (testing)
- `test_github_setup.py` ❌ (testing)
- `test_icon_encoding.py` ❌ (testing)
- `test_pkg_build_locally.sh` ❌ (testing)
- `test_setup.sh` ❌ (testing)

## Critical Issues Found

### 🚨 BROKEN WORKFLOWS
1. **build-linux.yml** - Missing 7 essential scripts
2. **build-windows.yml** - Missing 6 essential scripts  
3. **ci.yml** - Missing 4 essential scripts

### 🔧 IMMEDIATE ACTIONS NEEDED
1. **Restore missing scripts** or **update workflows** to use alternative approaches
2. **Verify local build dependencies** (build-client-local.sh, build-server-local.sh)
3. **Clean up unused documentation and development scripts**

## Recommendations

### Priority 1: Fix Broken Workflows
- Either restore the missing scripts or refactor workflows to use existing build system
- Consider consolidating Linux/Windows builds to use similar approach as macOS (build-all-local.sh)

### Priority 2: Clean Up Unused Files
- Remove development/testing scripts that are no longer needed
- Remove duplicate documentation files
- Keep only essential documentation (README.md, LICENSE, etc.)

### Priority 3: Organize Structure
- Move development scripts to a `/dev` or `/tools` directory
- Keep only production-ready scripts in root and `.github/scripts/`
- Maintain clear separation between production and development tools

## Specific Actions to Take

### 🚨 CRITICAL: Fix Broken Workflows (Priority 1)
The following workflows are currently broken and need immediate attention:

**Option A: Restore Missing Scripts**
- Restore the deleted scripts from git history
- Ensure they work with current codebase

**Option B: Refactor Workflows (RECOMMENDED)**
- Update Linux/Windows workflows to use the same approach as macOS
- Use `build-all-local.sh` with platform-specific parameters
- Simplify the build process across all platforms

### 🧹 SAFE TO REMOVE: Unused Files

#### Root Directory - Safe to Remove:
```bash
# Unused build scripts
rm build-client-local.sh build-server-local.sh

# Development/testing scripts
rm check-build-error.sh clean-for-signing.sh cleanup-and-test.sh
rm cleanup-signing-scripts.sh commit-signing-fixes.sh diagnose-build.sh
rm emergency-fix-python-framework.sh fix-signing.sh
rm make-signing-scripts-executable.sh quick-fix-certs.sh
rm test-build-system.sh test-build.sh test-signing-fix.sh test_fixes.sh

# Duplicate/outdated documentation
rm BULLETPROOF_SIGNING_SOLUTION.md CERTIFICATE_SETUP_REPORT.md
rm FIXED_XATTR_ISSUE.md GITHUB_ACTIONS_SIGNING_FIX.md GITHUB_README.md
rm SIGNING_ANALYSIS_SUMMARY.md SIGNING_FIX_DOCUMENTATION.md
rm SIGNING_SOLUTION_GUIDE.sh analysis_sign_notarize_separation.md
```

#### /scripts Directory - Safe to Remove:
```bash
cd scripts/
# Development/testing scripts
rm README.md apply_fix.sh clean-app-bundles.sh cleanup.sh
rm debug_certificates.sh install_dependencies.sh list_github_secrets.py
rm make_all_executable.sh make_executable.sh quick_macos_setup.sh
rm quick_start.sh requirements.txt run_secrets_manager.sh
rm security_scan.py setup_complete_github_secrets.sh setup_secrets.sh
rm test_encryption_fix.py test_github_setup.py test_icon_encoding.py
rm test_pkg_build_locally.sh test_setup.sh
```

### 📁 KEEP: Essential Files

#### Root Directory - Keep These:
- `README.md` (main project documentation)
- `LICENSE` (legal requirement)
- `CHANGELOG.md` (version history)
- `CODE_OF_CONDUCT.md` (community guidelines)
- `CONTRIBUTING.md` (contribution guidelines)
- `PRIVACY.md` (privacy policy)
- `SECURITY.md` (security policy)
- `QUICK_START.md` (user guide)
- All actively used scripts listed above

#### /scripts Directory - Keep These:
- `bulletproof_clean_app_bundle.py` (actively used)
- `certificate_manager.py` (useful for development)
- `configure_briefcase_signing.py` (useful for setup)
- `generate_icons.py` (useful for development)
- `setup_apple_store.py` (useful for App Store setup)
- `setup_github_secrets.py` (useful for CI setup)
- `update_pyproject.py` (useful for maintenance)
- `validate_pyproject.py` (useful for validation)

## Summary
- **BROKEN**: 3 workflows need immediate fixing
- **SAFE TO REMOVE**: ~30 unused files in root + ~15 in /scripts
- **KEEP**: ~8 essential files in root + ~8 useful files in /scripts
- **RESULT**: Cleaner, more maintainable repository structure
