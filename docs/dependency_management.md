# Dependency Management Guide

## Overview

This document provides guidelines for managing dependencies in the R2MIDI project, including best practices and solutions to common issues.

## Python Dependencies

The R2MIDI project uses several methods to manage Python dependencies:

1. **pyproject.toml**: The primary source of dependencies for modern Python packaging
2. **setup.py**: Used for editable installs and backward compatibility
3. **requirements.txt**: Used for quick installation of dependencies

It's important to maintain consistency across these files to avoid conflicts and warnings.

## MIDI Libraries

The project uses `python-rtmidi` for MIDI device interaction. Note that there are two similar packages:

- `python-rtmidi`: The recommended package, properly configured with modern Python packaging
- `rtmidi`: An alternative package that uses legacy setup.py mechanisms

We use `python-rtmidi` across all dependency specifications to avoid deprecation warnings.

## Deprecation Warning Resolution

If you encounter a deprecation warning like this:

```
DEPRECATION: Building 'rtmidi' using the legacy setup.py bdist_wheel mechanism, which will be removed in a future version.
```

This indicates that pip is trying to install the `rtmidi` package using legacy methods. The solution is to:

1. Use `python-rtmidi` instead of `rtmidi` in all dependency specifications
2. Ensure consistency between pyproject.toml, setup.py, and requirements.txt

## Best Practices

1. Always use `python-rtmidi>=1.5.5` in all dependency specifications
2. When adding new dependencies, add them to both pyproject.toml and requirements.txt
3. For development dependencies, use the optional-dependencies section in pyproject.toml
4. Use virtual environments to isolate project dependencies

## Troubleshooting

If you encounter dependency-related issues:

1. Check for consistency between pyproject.toml, setup.py, and requirements.txt
2. Use `pip list` to see which packages are actually installed
3. Consider using `pip install --use-pep517` if you must use packages with legacy setup.py mechanisms