#!/usr/bin/env python3
"""
Setup script for R2MIDI Client (macOS)
"""

import os
import sys

from setuptools import setup

# Get version from parent directory
sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "server")
)
from version import __version__

APP = ["main.py"]
DATA_FILES = [
    ("ui", ["ui/main_window.py"] if os.path.exists("ui/main_window.py") else []),
]

OPTIONS = {
    "argv_emulation": False,
    "iconfile": "../r2midi.icns",
    "plist": {
        "CFBundleName": "R2MIDI Client",
        "CFBundleDisplayName": "R2MIDI Client",
        "CFBundleIdentifier": "com.r2midi.client",
        "CFBundleVersion": __version__,
        "CFBundleShortVersionString": __version__,
        "CFBundleExecutable": "R2MIDI Client",
        "LSMinimumSystemVersion": "10.15",
        "NSHighResolutionCapable": True,
        "NSRequiresAquaSystemAppearance": False,
        "LSApplicationCategoryType": "public.app-category.music",
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "MIDI File",
                "CFBundleTypeExtensions": ["mid", "midi"],
                "CFBundleTypeRole": "Viewer",
            }
        ],
    },
    "packages": [],
    "includes": [
        "api_client",
        "config",
        "models",
        "performance",
        "shortcuts",
        "themes",
    ],
    "excludes": [],
    "optimize": 2,
    "compressed": True,
    "strip_debug_info": True,
}

setup(
    name="R2MIDI Client",
    version=__version__,
    author="R2MIDI Team",
    author_email="team@r2midi.org",
    description="R2MIDI Client Application",
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
    python_requires=">=3.10",
)
