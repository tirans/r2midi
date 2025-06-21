"""
MIDI Preset Selection Client

A client application for selecting and controlling MIDI presets.
"""

from .api_client import CachedApiClient
from .models import Device, Preset, UIState

__version__ = "0.1.0"
__all__ = ["CachedApiClient", "Device", "Preset", "UIState"]
