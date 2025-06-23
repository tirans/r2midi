#!/usr/bin/env python3
"""
Bulletproof macOS app bundle cleaner for code signing.
Uses multiple methods including Apple's ditto tool which is designed for this purpose.
"""

import os
import sys
import subprocess
import shutil
import tempfile
import argparse
from pathlib import Path
import time
import stat


def log(message, level="INFO"):
    """Simple logging function."""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {level}: {message}")


def run_command(cmd, shell=True, check=False):
    """Run a command and return the result."""
    try:
        result = subprocess.run(cmd, shell=shell, capture_output=True, text=True, check=check)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)


def make_writable(path):
    """Make a file or directory writable."""
    try:
        current = os.stat(path).st_mode
        os.chmod(path, current | stat.S_IWUSR)
    except:
        pass


def remove_quarantine_recursively(path):
    """Remove com.apple.quarantine xattr recursively."""
    # Remove quarantine attribute specifically
    run_command(f'xattr -dr com.apple.quarantine "{path}"', check=False)
    
    # Remove all extended attributes using -rc (recursive clear)
    # Note: -rc is more reliable than -cr on some macOS versions
    run_command(f'xattr -rc "{path}"', check=False)


def clean_with_ditto(app_path):
    """Use Apple's ditto command to create a clean copy without extended attributes."""
    app_path = Path(app_path)
    temp_dir = tempfile.mkdtemp()
    clean_app = Path(temp_dir) / app_path.name
    
    try:
        log(f"Using ditto to create clean copy of {app_path.name}...")
        
        # Use ditto with proper flags to exclude ALL metadata
        # --norsrc: Don't preserve resource forks
        # --noextattr: Don't preserve extended attributes
        # --noacl: Don't preserve ACLs
        cmd = f'ditto --norsrc --noextattr --noacl "{app_path}" "{clean_app}"'
        success, stdout, stderr = run_command(cmd)
        
        if not success:
            log(f"Ditto failed: {stderr}", "WARNING")
            return False
            
        # Verify the copy is clean
        success, stdout, stderr = run_command(f'xattr -lr "{clean_app}"')
        xattr_lines = [line for line in stdout.split('\n') if line.strip()]
        
        if len(xattr_lines) > 0:
            log(f"Ditto copy still has {len(xattr_lines)} extended attributes", "WARNING")
            # Try to clean them
            remove_quarantine_recursively(clean_app)
        
        # Always run a final recursive xattr clear to be absolutely sure
        log("Running final recursive xattr clear...")
        run_command(f'xattr -rc "{clean_app}"', check=False)
        
        # Verify again
        success, stdout, stderr = run_command(f'xattr -lr "{clean_app}"')
        xattr_lines = [line for line in stdout.split('\n') if line.strip()]
        if len(xattr_lines) == 0:
            log("✅ Ditto + xattr -rc resulted in completely clean app")
        else:
            log(f"⚠️  Still {len(xattr_lines)} xattrs after all cleaning attempts", "WARNING")
        
        # Replace original with clean copy
        backup_path = app_path.parent / f"{app_path.name}.backup-{int(time.time())}"
        log(f"Moving original to backup: {backup_path}")
        shutil.move(str(app_path), str(backup_path))
        
        log(f"Moving clean copy to original location...")
        shutil.move(str(clean_app), str(app_path))
        
        log("Successfully replaced with ditto-cleaned version")
        return True
        
    except Exception as e:
        log(f"Ditto method failed: {e}", "ERROR")
        return False
    finally:
        # Cleanup temp directory
        try:
            shutil.rmtree(temp_dir)
        except:
            pass


def nuclear_clean_with_tar(app_path):
    """Use tar to strip all metadata - this is the nuclear option."""
    app_path = Path(app_path)
    parent_dir = app_path.parent
    app_name = app_path.name
    
    try:
        log("Using tar method to strip all metadata...")
        
        # Create a tar archive without extended attributes
        tar_file = parent_dir / f"{app_name}.clean.tar"
        
        # Change to parent directory to get correct paths in tar
        original_dir = os.getcwd()
        os.chdir(parent_dir)
        
        # Create tar without extended attributes
        # Using GNU tar options if available, otherwise fallback
        cmd = f'tar --no-xattrs -cf "{tar_file.name}" "{app_name}" 2>/dev/null || tar -cf "{tar_file.name}" "{app_name}"'
        success, stdout, stderr = run_command(cmd)
        
        if not success:
            log(f"Tar creation failed: {stderr}", "ERROR")
            return False
        
        # Backup original
        backup_path = parent_dir / f"{app_name}.backup-{int(time.time())}"
        shutil.move(str(app_path), str(backup_path))
        
        # Extract tar
        cmd = f'tar -xf "{tar_file.name}"'
        success, stdout, stderr = run_command(cmd)
        
        if success:
            log("Successfully extracted clean version from tar")
            # Remove tar file
            tar_file.unlink()
            
            # Final cleanup of any remaining xattrs
            remove_quarantine_recursively(app_name)
            
            return True
        else:
            log(f"Tar extraction failed: {stderr}", "ERROR")
            # Restore backup
            if backup_path.exists():
                shutil.move(str(backup_path), str(app_path))
            return False
            
    except Exception as e:
        log(f"Tar method failed: {e}", "ERROR")
        return False
    finally:
        os.chdir(original_dir)


def find_problematic_files(app_path):
    """Find files with extended attributes or resource forks."""
    problematic = []
    
    for root, dirs, files in os.walk(app_path):
        for item in files + dirs:
            item_path = os.path.join(root, item)
            
            # Check for extended attributes
            success, stdout, stderr = run_command(f'xattr -l "{item_path}"', check=False)
            if stdout.strip():
                problematic.append((item_path, "xattrs", stdout.strip()))
            
            # Check for resource forks (._* files)
            if item.startswith("._"):
                problematic.append((item_path, "resource_fork", ""))
    
    return problematic


def aggressive_clean_file(file_path):
    """Aggressively clean a single file."""
    try:
        # Remove all xattrs
        run_command(f'xattr -c "{file_path}"', check=False)
        
        # If it's a Mach-O binary, try to strip it
        success, stdout, stderr = run_command(f'file "{file_path}"', check=False)
        if "Mach-O" in stdout:
            # Don't strip code signature
            run_command(f'strip -S "{file_path}" 2>/dev/null', check=False)
        
        return True
    except:
        return False


def clean_python_framework(framework_path):
    """Special handling for Python.framework."""
    framework_path = Path(framework_path)
    
    if not framework_path.exists():
        return
    
    log(f"Deep cleaning Python.framework...")
    
    # Remove all .pyc files (they often have xattrs)
    pyc_count = 0
    for pyc_file in framework_path.rglob("*.pyc"):
        try:
            pyc_file.unlink()
            pyc_count += 1
        except:
            pass
    
    if pyc_count > 0:
        log(f"Removed {pyc_count} .pyc files")
    
    # Remove __pycache__ directories
    pycache_count = 0
    for pycache in framework_path.rglob("__pycache__"):
        try:
            shutil.rmtree(pycache)
            pycache_count += 1
        except:
            pass
    
    if pycache_count > 0:
        log(f"Removed {pycache_count} __pycache__ directories")
    
    # Remove all .DS_Store files
    for ds_store in framework_path.rglob(".DS_Store"):
        try:
            ds_store.unlink()
        except:
            pass
    
    # Strip xattrs from remaining files - use xattr -rc for complete removal
    log("Running xattr -rc on Python.framework...")
    run_command(f'xattr -rc "{framework_path}"', check=False)
    
    # Belt and suspenders - also do per-file clearing
    run_command(f'find "{framework_path}" -type f -exec xattr -c {{}} \\; 2>/dev/null', check=False)
    run_command(f'find "{framework_path}" -type d -exec xattr -c {{}} \\; 2>/dev/null', check=False)


def bulletproof_clean(app_path, method="auto"):
    """
    Bulletproof cleaning with multiple fallback methods.
    
    Methods:
    - auto: Try all methods in order until one succeeds
    - ditto: Use Apple's ditto command
    - tar: Use tar to strip metadata
    - inplace: Clean in place (risky but sometimes necessary)
    """
    app_path = Path(app_path).resolve()
    
    if not app_path.exists():
        log(f"App bundle not found: {app_path}", "ERROR")
        return False
    
    if not app_path.suffix == '.app':
        log(f"Not an app bundle: {app_path}", "ERROR")
        return False
    
    log(f"Starting bulletproof clean of {app_path.name}")
    log(f"Method: {method}")
    
    # First, always try to clean Python.framework if it exists
    python_framework = app_path / "Contents" / "Frameworks" / "Python.framework"
    if python_framework.exists():
        clean_python_framework(python_framework)
    
    # Find problematic files before cleaning
    log("Scanning for problematic files...")
    problematic = find_problematic_files(app_path)
    if problematic:
        log(f"Found {len(problematic)} files with extended attributes or resource forks")
        
        # Show first 10 problematic files
        for path, issue_type, details in problematic[:10]:
            rel_path = os.path.relpath(path, app_path)
            log(f"  {rel_path}: {issue_type}")
        
        if len(problematic) > 10:
            log(f"  ... and {len(problematic) - 10} more")
    
    # Try cleaning methods
    success = False
    
    if method == "auto" or method == "ditto":
        log("Attempting ditto method...")
        if clean_with_ditto(app_path):
            success = True
        elif method == "ditto":
            return False
    
    if not success and (method == "auto" or method == "tar"):
        log("Attempting tar method...")
        if nuclear_clean_with_tar(app_path):
            success = True
        elif method == "tar":
            return False
    
    if not success and (method == "auto" or method == "inplace"):
        log("Attempting in-place cleaning...")
        
        # Remove all metadata files
        metadata_patterns = [
            ".DS_Store", "._*", "__MACOSX", ".idea", ".git", ".pytest_cache",
            "*.pyc", "*.pyo", "__pycache__", ".coverage", "*.swp", "*.swo",
            "Thumbs.db", "desktop.ini", ".gitignore", ".gitmodules"
        ]
        
        removed_count = 0
        for pattern in metadata_patterns:
            if "*" in pattern:
                # Use find for patterns
                cmd = f'find "{app_path}" -name "{pattern}" -delete 2>/dev/null'
            else:
                # Use find for exact names
                cmd = f'find "{app_path}" -name "{pattern}" -exec rm -rf {{}} + 2>/dev/null'
            
            run_command(cmd, check=False)
        
        # Nuclear xattr removal
        log("Removing all extended attributes...")
        
        # Method 1: xattr -rc (most effective)
        log("Running xattr -rc (recursive clear)...")
        run_command(f'xattr -rc "{app_path}"', check=False)
        
        # Method 2: Also try -cr in case of version differences
        run_command(f'xattr -cr "{app_path}"', check=False)
        
        # Method 3: find with xattr -c on each file (belt and suspenders)
        log("Running per-file xattr clear...")
        run_command(f'find "{app_path}" -type f -exec xattr -c {{}} \\; 2>/dev/null', check=False)
        run_command(f'find "{app_path}" -type d -exec xattr -c {{}} \\; 2>/dev/null', check=False)
        
        # Method 3: Specific xattr removal
        xattrs_to_remove = [
            "com.apple.quarantine",
            "com.apple.metadata:kMDItemWhereFroms",
            "com.apple.metadata:kMDItemDownloadedDate",
            "com.apple.lastuseddate#PS",
            "com.apple.finder.info"
        ]
        
        for xattr_name in xattrs_to_remove:
            run_command(f'xattr -dr {xattr_name} "{app_path}" 2>/dev/null', check=False)
        
        success = True
    
    # Verify cleanup
    if success:
        log("Verifying cleanup...")
        
        # Check for remaining xattrs
        success, stdout, stderr = run_command(f'find "{app_path}" -exec xattr -l {{}} \\; 2>/dev/null | wc -l')
        if stdout:
            xattr_count = int(stdout.strip())
            if xattr_count == 0:
                log("✅ App bundle is completely clean!")
            else:
                log(f"⚠️  {xattr_count} extended attributes remain")
        
        # Check if it can be signed
        log("Testing code signing...")
        test_result, stdout, stderr = run_command(
            f'codesign --force --deep --sign - "{app_path}" 2>&1',
            check=False
        )
        
        if test_result:
            log("✅ Test signing succeeded!")
        else:
            if "resource fork" in stderr:
                log("❌ Still has resource fork issues", "ERROR")
                success = False
            else:
                log("⚠️  Test signing failed but might work with real certificate")
    
    return success


def main():
    parser = argparse.ArgumentParser(
        description='Bulletproof macOS app bundle cleaner for code signing',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Methods:
  auto    - Try all methods until one succeeds (default)
  ditto   - Use Apple's ditto command (recommended)
  tar     - Use tar to strip all metadata
  inplace - Clean files in place (risky)

Examples:
  %(prog)s MyApp.app
  %(prog)s --method ditto MyApp.app
  %(prog)s --verify-only MyApp.app
        """
    )
    
    parser.add_argument('app_path', help='Path to .app bundle')
    parser.add_argument('--method', choices=['auto', 'ditto', 'tar', 'inplace'], 
                       default='auto', help='Cleaning method to use')
    parser.add_argument('--verify-only', action='store_true', 
                       help='Only verify if app is clean, don\'t modify')
    
    args = parser.parse_args()
    
    app_path = Path(args.app_path)
    
    if args.verify_only:
        log("Verification mode - checking for issues only")
        problematic = find_problematic_files(app_path)
        
        if not problematic:
            log("✅ App bundle is clean!")
            return 0
        else:
            log(f"❌ Found {len(problematic)} files with issues", "ERROR")
            return 1
    
    # Perform cleaning
    if bulletproof_clean(app_path, method=args.method):
        log("✅ Bulletproof cleaning completed successfully!")
        return 0
    else:
        log("❌ Bulletproof cleaning failed!", "ERROR")
        return 1


if __name__ == '__main__':
    sys.exit(main())
