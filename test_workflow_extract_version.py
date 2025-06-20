import subprocess
import sys
import os

def test_workflow_extract_version():
    """Test the exact script from the extract-version job in the workflow"""
    print("Testing the exact workflow extract-version script...")
    
    # This is the exact script from lines 305-344 in the workflow
    script = '''
# Extract version from pyproject.toml with multiple fallback methods
VERSION=""

# Method 1: Try tomllib (Python 3.11+)
if [ -z "$VERSION" ]; then
  VERSION=$(python3 -c "
  try:
      import tomllib
      with open('pyproject.toml', 'rb') as f:
          config = tomllib.load(f)
      print(config['project']['version'])
  except:
      pass
  " 2>/dev/null)
fi

# Method 2: Try regex parsing
if [ -z "$VERSION" ]; then
  VERSION=$(python3 -c "
  import re
  with open('pyproject.toml', 'r') as f:
      content = f.read()
      match = re.search(r'version = \"([^\"]+)\"', content)
      if match:
          print(match.group(1))
  " 2>/dev/null)
fi

# Method 3: Simple grep fallback
if [ -z "$VERSION" ]; then
  VERSION=$(grep -E '^version = ".*"' pyproject.toml | sed 's/version = "\\(.*\\)"/\\1/' 2>/dev/null)
fi

# Method 4: Default fallback
if [ -z "$VERSION" ]; then
  VERSION="0.1.0"
fi

echo "version=$VERSION" >> /dev/null  # Simulate GITHUB_OUTPUT
echo "Extracted version: $VERSION"
'''
    
    try:
        # Write the script to a temporary file
        with open('temp_extract_test.sh', 'w') as f:
            f.write('#!/bin/bash\nset -euo pipefail\n' + script)
        
        # Make it executable
        os.chmod('temp_extract_test.sh', 0o755)
        
        # Run the script
        result = subprocess.run(['./temp_extract_test.sh'], 
                              capture_output=True, text=True, cwd='.')
        
        print(f"Exit code: {result.returncode}")
        print(f"STDOUT:\n{result.stdout}")
        print(f"STDERR:\n{result.stderr}")
        
        # Clean up
        os.remove('temp_extract_test.sh')
        
        return result.returncode == 0
        
    except Exception as e:
        print(f"Error running script: {e}")
        return False

def test_individual_methods():
    """Test each method individually"""
    print("\nTesting individual methods from the workflow...")
    
    # Method 1: tomllib
    print("Method 1: tomllib")
    try:
        result = subprocess.run([
            'python3', '-c', '''
try:
    import tomllib
    with open('pyproject.toml', 'rb') as f:
        config = tomllib.load(f)
    print(config['project']['version'])
except:
    pass
'''
        ], capture_output=True, text=True)
        print(f"  Exit code: {result.returncode}")
        print(f"  Output: '{result.stdout.strip()}'")
        print(f"  Error: '{result.stderr.strip()}'")
    except Exception as e:
        print(f"  Exception: {e}")
    
    # Method 2: regex
    print("Method 2: regex")
    try:
        result = subprocess.run([
            'python3', '-c', '''
import re
with open('pyproject.toml', 'r') as f:
    content = f.read()
    match = re.search(r'version = "([^"]+)"', content)
    if match:
        print(match.group(1))
'''
        ], capture_output=True, text=True)
        print(f"  Exit code: {result.returncode}")
        print(f"  Output: '{result.stdout.strip()}'")
        print(f"  Error: '{result.stderr.strip()}'")
    except Exception as e:
        print(f"  Exception: {e}")
    
    # Method 3: grep
    print("Method 3: grep")
    try:
        result = subprocess.run([
            'bash', '-c', 'grep -E \'^version = ".*"\' pyproject.toml | sed \'s/version = "\\(.*\\)"/\\1/\''
        ], capture_output=True, text=True)
        print(f"  Exit code: {result.returncode}")
        print(f"  Output: '{result.stdout.strip()}'")
        print(f"  Error: '{result.stderr.strip()}'")
    except Exception as e:
        print(f"  Exception: {e}")

if __name__ == "__main__":
    print("=== Workflow Extract Version Test ===")
    
    # Test individual methods
    test_individual_methods()
    
    # Test the complete workflow script
    script_success = test_workflow_extract_version()
    
    print(f"\n=== Summary ===")
    print(f"Workflow script success: {'✓' if script_success else '✗'}")