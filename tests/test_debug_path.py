import sys


def test_debug_path():
    """Test to print the Python path"""
    print("\nPython path in pytest:")
    for path in sys.path:
        print(f"  - {path}")
    assert True
