#!/usr/bin/env python3
import sys

import yaml

file_path = ".github/actions/build-apps/action.yml"

try:
    with open(file_path, "r") as f:
        yaml.safe_load(f)
    print(f"✅ {file_path} - YAML syntax is valid!")
    sys.exit(0)
except yaml.YAMLError as e:
    print(f"❌ {file_path} - YAML error: {e}")
    sys.exit(1)
except Exception as e:
    print(f"❌ {file_path} - Error: {e}")
    sys.exit(1)
