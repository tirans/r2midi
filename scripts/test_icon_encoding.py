#!/usr/bin/env python3
"""Test script to verify icon generation works on Windows."""

import os
import platform
import sys

# Add parent directory to path to import generate_icons
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scripts.generate_icons import safe_print


def test_safe_print():
    """Test the safe_print function with various inputs."""
    print(f"Testing on {platform.system()} platform...")
    print("=" * 50)

    # Test basic messages
    safe_print("Testing basic message")

    # Test with success indicators
    safe_print("Testing success message", True)
    safe_print("Testing error message", False)
    safe_print("Testing warning message", None)

    # Test with Unicode characters
    safe_print("Testing with emojis: 🎵 🎹 🎼", True)
    safe_print("Testing path: C:\\Users\\test\\r2midi\\resources\\icon.ico", True)

    # Test long messages
    safe_print(
        "Testing very long message that might contain various characters and symbols: !@#$%^&*()_+-=[]{}|;':\",./<>?",
        True,
    )

    print("=" * 50)
    print("If you see this message, the test completed successfully!")


if __name__ == "__main__":
    test_safe_print()
