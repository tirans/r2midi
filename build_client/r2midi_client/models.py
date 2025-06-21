from dataclasses import dataclass
from typing import Dict, List, Optional


@dataclass
class Device:
    """Client-side model for device information"""

    name: str
    manufacturer: str = ""
    midi_port: Optional[Dict[str, str]] = None
    midi_channel: Optional[Dict[str, int]] = None
    community_folders: Optional[List[str]] = None
    version: Optional[str] = None


@dataclass
class Preset:
    """Client-side model for preset information"""

    preset_name: str
    category: str
    characters: Optional[List[str]] = None
    sendmidi_command: Optional[str] = None
    cc_0: Optional[int] = None
    pgm: Optional[int] = None
    source: Optional[str] = None  # 'default' or community folder name

    def get_display_name(self) -> str:
        """Get a formatted display name for the preset"""
        display_name = f"{self.preset_name} ({self.category})"
        if self.source and self.source != "default":
            display_name += f" [{self.source}]"
        return display_name

    def get_details(self) -> str:
        """Get detailed information about the preset"""
        details = [f"Name: {self.preset_name}", f"Category: {self.category}"]

        if self.source:
            details.append(f"Source: {self.source}")

        if self.characters:
            details.append(f"Characters: {', '.join(self.characters)}")

        if self.cc_0 is not None and self.pgm is not None:
            details.append(f"CC 0: {self.cc_0}, Program: {self.pgm}")

        return "\n".join(details)


@dataclass
class UIState:
    """Client-side model for UI state persistence"""

    manufacturer: Optional[str] = None
    device: Optional[str] = None
    community_folder: Optional[str] = None
    midi_in_port: Optional[str] = None
    midi_out_port: Optional[str] = None
    sequencer_port: Optional[str] = None
    midi_channel: Optional[int] = None
    sync_enabled: bool = True
