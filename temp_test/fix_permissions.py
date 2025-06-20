#!/usr/bin/env python3

import os
import stat
import subprocess

scripts_dir = "/Users/tirane/Desktop/r2midi/.github/scripts"

# List of scripts to make executable
scripts = [
    "configure-build.sh",
    "setup-python-environment.sh", 
    "install-dependencies.sh",
    "setup-apple-certificates.sh",
    "build-server-app.sh",
    "build-client-app.sh",
    "sign-apps.sh",
    "create-pkg-installers.sh",
    "create-dmg-installers.sh",
    "notarize-packages.sh",
    "create-build-report.sh",
    "cleanup-build.sh",
    "make-scripts-executable.sh"
]

print("Making GitHub scripts executable...")

for script in scripts:
    script_path = os.path.join(scripts_dir, script)
    if os.path.exists(script_path):
        # Make executable (755 permissions)
        os.chmod(script_path, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        print(f"✅ Made executable: {script}")
    else:
        print(f"❌ Not found: {script}")

print("\nVerifying permissions:")
for script in scripts:
    script_path = os.path.join(scripts_dir, script)
    if os.path.exists(script_path):
        file_stat = os.stat(script_path)
        is_executable = bool(file_stat.st_mode & stat.S_IXUSR)
        permissions = oct(file_stat.st_mode)[-3:]
        print(f"  {script}: {permissions} ({'executable' if is_executable else 'not executable'})")

print("\n✅ All scripts should now be executable!")
