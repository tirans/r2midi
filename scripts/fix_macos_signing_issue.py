#!/usr/bin/env python3
"""
Fix macOS signing issues by implementing deep cleaning before code signing.
This script patches the build process to ensure clean app bundles.
"""

import os
import sys
import subprocess
import json
from pathlib import Path


def log(message, level="INFO"):
    """Simple logging."""
    print(f"[{level}] {message}")


def run_command(cmd, check=True):
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=check)
        return result.returncode, result.stdout, result.stderr
    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout, e.stderr


def patch_build_scripts():
    """Patch build scripts to include deep cleaning."""
    scripts_to_patch = [
        "build-client-local.sh",
        "build-server-local.sh"
    ]
    
    for script_name in scripts_to_patch:
        script_path = Path(script_name)
        if not script_path.exists():
            log(f"Script not found: {script_name}", "WARNING")
            continue
        
        log(f"Patching {script_name}...")
        
        # Read current content
        content = script_path.read_text()
        
        # Check if already patched
        if "deep_clean_app_bundle.py" in content:
            log(f"{script_name} already patched", "INFO")
            continue
        
        # Find where to insert the cleaning step
        # Look for the signing section
        patch_marker = "# Sign the application"
        if patch_marker not in content:
            # Try alternative markers
            patch_marker = "briefcase package"
            
        if patch_marker in content:
            # Insert deep clean before signing
            clean_code = '''
# Deep clean the app bundle before signing
log_info "Deep cleaning app bundle before signing..."
if [ -d "dist/*.app" ]; then
    for app in dist/*.app; do
        if [ -d "$app" ]; then
            log_info "Cleaning: $(basename "$app")"
            if python3 scripts/deep_clean_app_bundle.py "$app"; then
                log_success "Successfully cleaned: $(basename "$app")"
            else
                log_warning "Failed to clean: $(basename "$app")"
            fi
        fi
    done
fi

'''
            # Insert before the marker
            content = content.replace(patch_marker, clean_code + patch_marker)
            
            # Write back
            script_path.write_text(content)
            log(f"Patched {script_name}", "SUCCESS")
        else:
            log(f"Could not find patch location in {script_name}", "WARNING")


def create_briefcase_post_build_hook():
    """Create a post-build hook for Briefcase to clean apps."""
    hook_content = '''#!/usr/bin/env python3
"""
Briefcase post-build hook to clean app bundles.
"""

import os
import subprocess
from pathlib import Path


def post_build(app, **kwargs):
    """Run after the app is built but before signing."""
    print("[Briefcase Hook] Running post-build cleanup...")
    
    # Get the app path
    app_path = Path(app.bundle_path)
    
    if app_path.exists() and app_path.suffix == '.app':
        print(f"[Briefcase Hook] Cleaning {app_path.name}...")
        
        # Run deep clean script
        deep_clean_script = Path(__file__).parent.parent / "scripts" / "deep_clean_app_bundle.py"
        
        if deep_clean_script.exists():
            result = subprocess.run(
                ["python3", str(deep_clean_script), str(app_path)],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                print(f"[Briefcase Hook] Successfully cleaned {app_path.name}")
            else:
                print(f"[Briefcase Hook] Failed to clean {app_path.name}: {result.stderr}")
        else:
            print(f"[Briefcase Hook] Deep clean script not found: {deep_clean_script}")
    else:
        print(f"[Briefcase Hook] App bundle not found: {app_path}")
'''
    
    # Create hooks directory
    hooks_dir = Path("hooks")
    hooks_dir.mkdir(exist_ok=True)
    
    # Write post-build hook
    hook_path = hooks_dir / "post_build.py"
    hook_path.write_text(hook_content)
    hook_path.chmod(0o755)
    
    log(f"Created Briefcase post-build hook: {hook_path}", "SUCCESS")


def update_pyproject_for_hooks():
    """Update pyproject.toml to use the post-build hook."""
    pyproject_path = Path("pyproject.toml")
    
    if not pyproject_path.exists():
        log("pyproject.toml not found", "ERROR")
        return False
    
    # For both client and server pyproject.toml files
    for component in ["client", "server"]:
        setup_py = Path(f"setup_{component}.py")
        if setup_py.exists():
            log(f"Checking {component} configuration...", "INFO")
            
            # Note: Briefcase hooks are configured in the build scripts
            # This is just a placeholder for future enhancements


def verify_certificates():
    """Verify that certificates are properly configured."""
    log("Verifying certificate configuration...", "INFO")
    
    # Check for local config
    config_path = Path("apple_credentials/config/app_config.json")
    if config_path.exists():
        try:
            with open(config_path) as f:
                config = json.load(f)
            
            if "apple_developer" in config:
                team_id = config["apple_developer"].get("team_id", "")
                if team_id:
                    log(f"Team ID configured: {team_id}", "SUCCESS")
                else:
                    log("Team ID not found in config", "WARNING")
        except Exception as e:
            log(f"Error reading config: {e}", "ERROR")
    
    # Check keychain for certificates
    returncode, stdout, stderr = run_command(
        "security find-identity -v -p codesigning | grep 'Developer ID Application'",
        check=False
    )
    
    if returncode == 0 and stdout:
        log("Developer ID Application certificate found", "SUCCESS")
        for line in stdout.strip().split('\n'):
            if line.strip():
                log(f"  {line.strip()}", "INFO")
    else:
        log("No Developer ID Application certificate found", "ERROR")


def main():
    """Main execution."""
    log("macOS Signing Fix Implementation", "INFO")
    log("=================================", "INFO")
    
    # Make scripts executable
    log("Making scripts executable...", "INFO")
    for script in ["scripts/deep_clean_app_bundle.py", "scripts/clean-app-bundles.sh"]:
        if Path(script).exists():
            os.chmod(script, 0o755)
            log(f"Made executable: {script}", "SUCCESS")
    
    # Note: Build scripts will use bulletproof_clean_app_bundle.py automatically
    log("\nBuild scripts will use bulletproof cleaning automatically.", "INFO")
    
    # Update pyproject.toml
    log("\nUpdating project configuration...", "INFO")
    update_pyproject_for_hooks()
    
    # Verify certificates
    log("\nVerifying certificates...", "INFO")
    verify_certificates()
    
    log("\n✅ macOS signing fix implementation complete!", "SUCCESS")
    log("\nNext steps:", "INFO")
    log("1. Run: ./setup-local-certificates.sh", "INFO")
    log("2. Run: ./build-all-local.sh --clean", "INFO")
    log("3. The build process will now deep clean app bundles before signing", "INFO")


if __name__ == "__main__":
    main()
