#!/usr/bin/env python3
"""Enhanced setup script for R2MIDI Server (macOS) with py2app"""

# Import setuptools first to ensure distutils compatibility
import setuptools

import os
import sys
from pathlib import Path
from setuptools import setup

# Suppress setuptools deprecation warnings
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning, module="setuptools")
warnings.filterwarnings("ignore", category=DeprecationWarning, module="pkg_resources")
warnings.filterwarnings("ignore", category=DeprecationWarning, module="distutils")
warnings.filterwarnings("ignore", category=UserWarning, module="_distutils_hack")

# Get version
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "server"))
try:
    from version import __version__
except ImportError:
    __version__ = "0.1.192"

PROJECT_ROOT = Path(__file__).parent
SERVER_DIR = PROJECT_ROOT / "server"
RESOURCES_DIR = PROJECT_ROOT / "resources"

APP = [str(SERVER_DIR / "main.py")]
DATA_FILES = []

if RESOURCES_DIR.exists():
    for resource_file in RESOURCES_DIR.glob("*"):
        if resource_file.is_file():
            DATA_FILES.append(str(resource_file))

OPTIONS = {
    'excludes': [
        'setuptools._vendor', 'pkg_resources._vendor', 'distutils._vendor',
        'setuptools.extern', 'pkg_resources.extern',
        'PyQt6', 'tkinter', 'matplotlib', 'numpy',
        'wheel', 'pip', 'setuptools.command', 'distutils.command'
    ],
    'includes': ['fastapi', 'uvicorn', 'rtmidi', 'mido', 'starlette', 'pydantic'],
    'packages': ['server', 'uvicorn', 'fastapi'],
    'argv_emulation': False,
    'site_packages': True,
    'optimize': 2,
    'iconfile': str(RESOURCES_DIR / 'r2midi.icns') if (RESOURCES_DIR / 'r2midi.icns').exists() else None,
    'plist': {
        'CFBundleName': 'R2MIDI Server',
        'CFBundleIdentifier': 'com.r2midi.server',
        'CFBundleVersion': __version__,
        'LSMinimumSystemVersion': '11.0',
        'NSHighResolutionCapable': True,
    },
}

setup(
    name='R2MIDI Server',
    version=__version__,
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    zip_safe=False,
)
