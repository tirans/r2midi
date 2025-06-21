#!/usr/bin/env python3
"""Enhanced setup script for R2MIDI Client (macOS) with py2app"""

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
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "r2midi_client"))
try:
    from version import __version__
except ImportError:
    __version__ = "1.0.0"

PROJECT_ROOT = Path(__file__).parent
CLIENT_DIR = PROJECT_ROOT / "r2midi_client"
RESOURCES_DIR = PROJECT_ROOT / "resources"

APP = [str(CLIENT_DIR / "main.py")]
DATA_FILES = []

if RESOURCES_DIR.exists():
    for resource_file in RESOURCES_DIR.glob("*"):
        if resource_file.is_file():
            DATA_FILES.append(str(resource_file))

OPTIONS = {
    'excludes': [
        'setuptools._vendor', 'pkg_resources._vendor', 'distutils._vendor',
        'setuptools.extern', 'pkg_resources.extern',
        'tkinter', 'fastapi', 'uvicorn', 'rtmidi', 'mido', 'matplotlib', 'numpy',
        'wheel', 'pip', 'setuptools.command', 'distutils.command',
        'test', 'tests', 'testing'
    ],
    'includes': [
        'PyQt6.QtCore', 'PyQt6.QtGui', 'PyQt6.QtWidgets', 
        'httpx', 'pydantic', 'psutil'
    ],
    'packages': ['r2midi_client'],
    'argv_emulation': False,
    'site_packages': True,
    'optimize': 2,
    'strip': False,
    'iconfile': str(RESOURCES_DIR / 'r2midi.icns') if (RESOURCES_DIR / 'r2midi.icns').exists() else None,
    'plist': {
        'CFBundleName': 'R2MIDI Client',
        'CFBundleIdentifier': 'com.r2midi.client',
        'CFBundleVersion': __version__,
        'CFBundleShortVersionString': __version__,
        'LSMinimumSystemVersion': '11.0',
        'NSHighResolutionCapable': True,
    },
}

setup(
    name='R2MIDI Client',
    version=__version__,
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    zip_safe=False,
)
