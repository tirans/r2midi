#!/usr/bin/env python3
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
