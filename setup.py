#!/usr/bin/env python3
"""Minimal setup.py for editable installs"""
from setuptools import find_packages, setup

# Read version from server/version.py
version = {}
with open("server/version.py") as fp:
    exec(fp.read(), version)

setup(
    name="r2midi",
    version=version["__version__"],
    packages=find_packages(),
    package_data={
        "server": ["midi-presets/**/*"],
    },
    install_requires=[
        "fastapi>=0.104.0",
        "uvicorn>=0.23.2",
        "pydantic>=2.4.2",
        "python-rtmidi>=1.5.5",
        "pyqt6>=6.5.2",
        "httpx>=0.25.0",
        "python-dotenv>=1.0.0",
        "black>=24.8.0",
        "GitPython>=3.1.40",
        "psutil>=7.0.0",
    ],
    extras_require={
        "test": [
            "pytest>=7.4.0",
            "pytest-asyncio>=0.21.1",
            "pytest-mock>=3.11.1",
            "pytest-cov>=4.1.0",
            "pytest-qt>=4.4.0",
            "httpx>=0.25.0",
        ],
    },
    python_requires=">=3.12,<3.13",
)
