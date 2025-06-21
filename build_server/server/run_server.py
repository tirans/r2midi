#!/usr/bin/env python3
"""
R2MIDI Server entry point
"""
import os
import sys

# Add the project root to the Python path
project_root = os.path.dirname(os.path.dirname(__file__))
sys.path.insert(0, project_root)

if __name__ == "__main__":
    from server.main import main

    main()
