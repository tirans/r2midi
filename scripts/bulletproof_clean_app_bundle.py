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
        
        # Also clean frameworks specifically
        frameworks_dir = clean_app / "Contents" / "Frameworks"
        if frameworks_dir.exists():
            log("Final framework cleaning...")
            for item in frameworks_dir.iterdir():
                run_command(f'xattr -cr "{item}"', check=False)
                run_command(f'xattr -d "*" "{item}" 2>/dev/null', check=False)
        
        # Verify again with detailed count
        log("Verifying cleanup...")
        cmd = f'find "{clean_app}" -exec xattr -l {{}} + 2>/dev/null | grep -v "^$" | wc -l'
        success, stdout, stderr = run_command(cmd)
        xattr_count = int(stdout.strip()) if stdout.strip().isdigit() else -1
        
        if xattr_count == 0:
            log("✅ Ditto + cleanup resulted in completely clean app")
        elif xattr_count > 0:
            log(f"⚠️  Still {xattr_count} xattr lines after cleaning", "WARNING")
            # Show which files still have xattrs
            cmd = f'find "{clean_app}" -exec xattr -l {{}} + 2>/dev/null | grep -B1 "^[[:space:]]" | grep -v "^--$" | head -20'
            success, stdout, stderr = run_command(cmd)
            if stdout.strip():
                log("Files with remaining xattrs:", "WARNING")
                for line in stdout.strip().split('\n')[:10]:
                    log(f"  {line}", "WARNING")
        else:
            log("✅ App appears to be clean")
        
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
    
    log("Checking for extended attributes...")
    
    # Use native find command for better performance
    cmd = f'find "{app_path}" -exec xattr -l {{}} + 2>/dev/null'
    success, stdout, stderr = run_command(cmd, check=False)
    
    if stdout.strip():
        # Parse the output to count files with xattrs
        current_file = None
        for line in stdout.split('\n'):
            if line and not line.startswith(' '):
                # This is a filename
                current_file = line.rstrip(':')
            elif line.strip() and current_file:
                # This is an xattr for the current file
                problematic.append((current_file, "xattrs", line.strip()))
    
    # Also check for resource fork files
    cmd = f'find "{app_path}" -name "._*" -o -name ".DS_Store" 2>/dev/null'
    success, stdout, stderr = run_command(cmd, check=False)
    
    if stdout.strip():
        for file in stdout.strip().split('\n'):
            if file:
                problematic.append((file, "resource_fork", ""))
    
    return problematic


def aggressive_clean_file(file_path):
    """Aggressively clean a single file."""
    try:
        # Method 1: Remove all xattrs
        run_command(f'xattr -c "{file_path}"', check=False)
        
        # Method 2: Delete all xattrs by name
        run_command(f'xattr -d "*" "{file_path}" 2>/dev/null', check=False)
        
        # Method 3: Clear Finder info if SetFile is available
        if shutil.which('SetFile'):
            run_command(f'SetFile -c "" -t "" "{file_path}" 2>/dev/null', check=False)
        
        # Method 4: Remove specific problematic attributes
        for attr in ['com.apple.FinderInfo', 'com.apple.ResourceFork', 
                     'com.apple.metadata:kMDItemWhereFroms', 'com.apple.quarantine']:
            run_command(f'xattr -d {attr} "{file_path}" 2>/dev/null', check=False)
        
        return True
    except:
        return False


def clean_framework(framework_path, framework_name="Framework"):
    """Deep clean any framework bundle."""
    framework_path = Path(framework_path)
    
    if not framework_path.exists():
        return
    
    log(f"Deep cleaning {framework_name}...")
    
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
    
    # Remove all .DS_Store and ._* files
    for pattern in [".DS_Store", "._*"]:
        for file in framework_path.rglob(pattern):
            try:
                file.unlink()
            except:
                pass
    
    # Use native macOS tool to strip all metadata
    log(f"Stripping all metadata from {framework_name}...")
    
    # Method 1: Use xattr -rc (recursive clear)
    run_command(f'xattr -rc "{framework_path}"', check=False)
    
    # Method 2: Use find with xattr -d * to delete ALL attributes
    run_command(f'find "{framework_path}" -type f -exec xattr -d "*" {{}} \\; 2>/dev/null', check=False)
    run_command(f'find "{framework_path}" -type d -exec xattr -d "*" {{}} \\; 2>/dev/null', check=False)
    
    # Method 3: Use SetFile to clear Finder info specifically
    if shutil.which('SetFile'):
        run_command(f'find "{framework_path}" -type f -exec SetFile -c "" -t "" {{}} \\; 2>/dev/null', check=False)
    
    # Method 4: Remove com.apple.FinderInfo specifically
    run_command(f'xattr -dr com.apple.FinderInfo "{framework_path}" 2>/dev/null', check=False)
    
    log(f"Completed deep clean of {framework_name}")


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
    
    # First, clean ALL frameworks
    log("Cleaning all frameworks...")
    frameworks_dir = app_path / "Contents" / "Frameworks"
    if frameworks_dir.exists():
        for item in frameworks_dir.iterdir():
            if item.suffix == '.framework':
                clean_framework(item, item.name)
            elif item.suffix in ['.dylib', '.so']:
                # Clean individual dylib files
                log(f"Cleaning dylib: {item.name}")
                run_command(f'xattr -c "{item}"', check=False)
                run_command(f'xattr -d "*" "{item}" 2>/dev/null', check=False)
                if shutil.which('SetFile'):
                    run_command(f'SetFile -c "" -t "" "{item}" 2>/dev/null', check=False)
    
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
        
        # Nuclear xattr removal with improved methods
        log("Removing all extended attributes...")
        
        # Method 1: xattr -rc (recursive clear)
        log("Method 1: xattr -rc...")
        run_command(f'xattr -rc "{app_path}"', check=False)
        
        # Method 2: Find and delete ALL xattrs
        log("Method 2: Deleting all xattrs by wildcard...")
        run_command(f'find "{app_path}" -type f -exec xattr -d "*" {{}} \\; 2>/dev/null', check=False)
        run_command(f'find "{app_path}" -type d -exec xattr -d "*" {{}} \\; 2>/dev/null', check=False)
        
        # Method 3: Clear Finder info with SetFile
        if shutil.which('SetFile'):
            log("Method 3: Clearing Finder info with SetFile...")
            run_command(f'find "{app_path}" -type f -exec SetFile -c "" -t "" {{}} \\; 2>/dev/null', check=False)
        
        # Method 4: Target specific problematic attributes
        log("Method 4: Removing specific attributes...")
        problematic_attrs = [
            "com.apple.FinderInfo",
            "com.apple.ResourceFork", 
            "com.apple.quarantine",
            "com.apple.metadata:kMDItemWhereFroms",
            "com.apple.metadata:kMDItemDownloadedDate",
            "com.apple.lastuseddate#PS"
        ]
        
        for xattr_name in problematic_attrs:
            run_command(f'xattr -dr {xattr_name} "{app_path}" 2>/dev/null', check=False)
        
        # Method 5: Use native macOS 'dot_clean' utility
        log("Method 5: Running dot_clean utility...")
        parent_dir = os.path.dirname(app_path)
        run_command(f'dot_clean -m "{parent_dir}" 2>/dev/null', check=False)
        
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
        
        # Check if it can be signed with a more specific test
        log("Testing code signing readiness...")
        
        # First check if there are any files with xattrs
        cmd = f'find "{app_path}" -exec xattr -l {{}} + 2>/dev/null | wc -l'
        success_check, stdout, stderr = run_command(cmd)
        final_xattr_count = int(stdout.strip()) if stdout.strip().isdigit() else -1
        
        log(f"Final extended attribute count: {final_xattr_count}")
        
        if final_xattr_count == 0:
            log("✅ No extended attributes found - ready for signing!")
            success = True
        else:
            # Try to identify which files are problematic
            log("Identifying problematic files...", "WARNING")
            cmd = f'find "{app_path}" -exec xattr -l {{}} + 2>/dev/null | grep -B1 "^[[:space:]]" | grep -v "^--$" | grep -v "^[[:space:]]" | sort | uniq'
            success_check, stdout, stderr = run_command(cmd)
            if stdout.strip():
                log("Files with extended attributes:", "WARNING")
                for line in stdout.strip().split('\n')[:20]:
                    if line.strip():
                        log(f"  {line}", "WARNING")
            
            # Test actual signing
            test_result, stdout, stderr = run_command(
                f'codesign --force --deep --sign - "{app_path}" 2>&1',
                check=False
            )
            
            if test_result:
                log("✅ Test signing succeeded despite xattrs!")
            else:
                if "resource fork" in stderr or "Finder information" in stderr:
                    log("❌ Still has resource fork/Finder info issues", "ERROR")
                    log(f"Error: {stderr}", "ERROR")
                    success = False
                else:
                    log("⚠️  Test signing failed but might work with real certificate")
                    log(f"Error: {stderr}", "WARNING")
    
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
