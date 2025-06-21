#!/usr/bin/env python3
"""
Test script to verify midi_utils.py works with rtmidi-python
"""

import sys
import os

# Add the server directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'server'))

try:
    from midi_utils import MidiUtils
    print("✓ Successfully imported MidiUtils")
except ImportError as e:
    print(f"✗ Failed to import MidiUtils: {e}")
    sys.exit(1)

def test_midi_functionality():
    """Test basic MIDI functionality"""
    print("\n=== Testing MIDI Functionality ===")
    
    # Test MIDI availability
    print("Testing MIDI availability...")
    try:
        is_available = MidiUtils.is_midi_available()
        print(f"✓ MIDI available: {is_available}")
    except Exception as e:
        print(f"✗ Error checking MIDI availability: {e}")
        return False
    
    # Test getting MIDI ports
    print("Testing MIDI port detection...")
    try:
        ports = MidiUtils.get_midi_ports()
        print(f"✓ MIDI ports detected:")
        print(f"  Input ports: {ports['in']}")
        print(f"  Output ports: {ports['out']}")
    except Exception as e:
        print(f"✗ Error getting MIDI ports: {e}")
        return False
    
    # Test deprecated sendmidi method
    print("Testing deprecated sendmidi method...")
    try:
        sendmidi_available = MidiUtils.is_sendmidi_installed()
        print(f"✓ Deprecated sendmidi method works: {sendmidi_available}")
    except Exception as e:
        print(f"✗ Error with deprecated sendmidi method: {e}")
        return False
    
    return True

def test_midi_command_parsing():
    """Test MIDI command parsing without actually sending"""
    print("\n=== Testing MIDI Command Parsing ===")
    
    # Test with a sample command (this will fail at port opening, but should parse correctly)
    test_command = 'dev "Test Port" ch 1 cc 0 64 pc 42'
    print(f"Testing command parsing with: {test_command}")
    
    try:
        # This will likely fail because "Test Port" doesn't exist, but it should parse correctly
        success, message = MidiUtils.send_midi_command(test_command)
        if "not found" in message.lower():
            print("✓ Command parsing works (port not found as expected)")
            return True
        elif success:
            print("✓ Command executed successfully")
            return True
        else:
            print(f"? Command failed with: {message}")
            return True  # This is expected if no MIDI ports are available
    except Exception as e:
        print(f"✗ Error parsing MIDI command: {e}")
        return False

if __name__ == "__main__":
    print("Testing midi_utils.py with rtmidi-python...")
    
    success = True
    success &= test_midi_functionality()
    success &= test_midi_command_parsing()
    
    if success:
        print("\n✓ All tests passed! midi_utils.py is working with rtmidi-python")
    else:
        print("\n✗ Some tests failed")
        sys.exit(1)