#!/usr/bin/env python3
"""
Test script to verify MIDI functionality works after removing legacy rtmidi package
"""

import sys
import os

# Add the server directory to the path so we can import midi_utils
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'server'))

try:
    from midi_utils import MidiUtils
    print("✓ Successfully imported MidiUtils")
    
    # Test getting MIDI ports
    ports = MidiUtils.get_midi_ports()
    print(f"✓ Successfully got MIDI ports: {ports}")
    
    # Test that rtmidi module is available
    import rtmidi
    print(f"✓ Successfully imported rtmidi module")
    print(f"✓ rtmidi module location: {rtmidi.__file__}")
    
    # Test creating MIDI objects
    midi_in = rtmidi.RtMidiIn()
    midi_out = rtmidi.RtMidiOut()
    print("✓ Successfully created RtMidiIn and RtMidiOut objects")
    
    print("\n🎉 All tests passed! MIDI functionality is working correctly.")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)