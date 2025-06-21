#!/usr/bin/env python3
"""
Setup script for R2MIDI Server (macOS)
"""

import os
import sys

from setuptools import setup

# Add parent directory to path to import version
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from version import __version__

APP = ["main.py"]
DATA_FILES = [
    ("midi-presets", ["midi-presets/README.md"]),
]

OPTIONS = {
    "argv_emulation": False,
    "iconfile": "../r2midi.icns",
    "plist": {
        "CFBundleName": "R2MIDI Server",
        "CFBundleDisplayName": "R2MIDI Server",
        "CFBundleIdentifier": "com.r2midi.server",
        "CFBundleVersion": __version__,
        "CFBundleShortVersionString": __version__,
        "CFBundleExecutable": "R2MIDI Server",
        "LSMinimumSystemVersion": "10.15",
        "NSHighResolutionCapable": True,
        "NSRequiresAquaSystemAppearance": False,
        "LSApplicationCategoryType": "public.app-category.music",
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "MIDI File",
                "CFBundleTypeExtensions": ["mid", "midi"],
                "CFBundleTypeRole": "Editor",
            }
        ],
    },
    "packages": [],
    "includes": ["midi_utils", "device_manager", "models"],
    "excludes": [],
    "optimize": 2,
    "compressed": True,
    "strip_debug_info": True,
}

setup(
    name="R2MIDI Server",
    version=__version__,
    author="R2MIDI Team",
    author_email="team@r2midi.org",
    description="R2MIDI Server Application",
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
    python_requires=">=3.10",
)
