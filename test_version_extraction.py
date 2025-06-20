import subprocess
import sys
import os

def test_extract_version_script():
    """Test the extract-version.sh script"""
    print("Testing extract-version.sh script...")
    
    try:
        result = subprocess.run(['./.github/scripts/extract-version.sh'], 
                              capture_output=True, text=True, cwd='.')
        print(f"Exit code: {result.returncode}")
        print(f"STDOUT:\n{result.stdout}")
        print(f"STDERR:\n{result.stderr}")
        return result.returncode == 0
    except Exception as e:
        print(f"Error running script: {e}")
        return False

def test_pyproject_version_extraction():
    """Test the pyproject.toml version extraction methods from the workflow"""
    print("\nTesting pyproject.toml version extraction methods...")
    
    # Method 1: Try tomllib (Python 3.11+)
    print("Method 1: tomllib")
    try:
        import tomllib
        with open('pyproject.toml', 'rb') as f:
            config = tomllib.load(f)
        version = config['project']['version']
        print(f"  Success: {version}")
    except Exception as e:
        print(f"  Failed: {e}")
    
    # Method 2: Try regex parsing
    print("Method 2: regex parsing")
    try:
        import re
        with open('pyproject.toml', 'r') as f:
            content = f.read()
            match = re.search(r'version = "([^"]+)"', content)
            if match:
                version = match.group(1)
                print(f"  Success: {version}")
            else:
                print("  Failed: No match found")
    except Exception as e:
        print(f"  Failed: {e}")
    
    # Method 3: Simple grep fallback (simulate)
    print("Method 3: grep simulation")
    try:
        with open('pyproject.toml', 'r') as f:
            lines = f.readlines()
        for line in lines:
            if line.strip().startswith('version = "'):
                version = line.split('"')[1]
                print(f"  Success: {version}")
                break
        else:
            print("  Failed: No version line found")
    except Exception as e:
        print(f"  Failed: {e}")

def test_server_version_extraction():
    """Test the server/version.py extraction"""
    print("\nTesting server/version.py extraction...")
    
    try:
        with open('server/version.py', 'r') as f:
            content = f.read()
        
        # Simulate the grep command from the script
        import re
        match = re.search(r'__version__ = "([^"]*)"', content)
        if match:
            version = match.group(1).strip()
            print(f"  Success: {version}")
            return version
        else:
            print("  Failed: No __version__ found")
            return None
    except Exception as e:
        print(f"  Failed: {e}")
        return None

if __name__ == "__main__":
    print("=== Version Extraction Test ===")
    
    # Test server/version.py extraction
    server_version = test_server_version_extraction()
    
    # Test pyproject.toml extraction
    test_pyproject_version_extraction()
    
    # Test the actual script
    script_success = test_extract_version_script()
    
    print(f"\n=== Summary ===")
    print(f"Server version extraction: {'✓' if server_version else '✗'}")
    print(f"Extract script success: {'✓' if script_success else '✗'}")