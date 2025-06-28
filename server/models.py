from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class Device(BaseModel):
    """Model for device information"""

    name: str
    manufacturer: str
    midi_port: Optional[Dict[str, str]] = None
    midi_channel: Optional[Dict[str, int]] = None
    community_folders: Optional[List[str]] = None


class Preset(BaseModel):
    """Model for preset information"""

    preset_name: str
    category: str
    characters: Optional[List[str]] = None
    sendmidi_command: Optional[str] = None
    cc_0: Optional[int] = None
    pgm: Optional[int] = None
    source: Optional[str] = None  # 'default' or community folder name


class PresetRequest(BaseModel):
    """Model for preset selection request"""

    preset_name: str
    midi_port: str
    midi_channel: int
    sequencer_port: Optional[str] = None


class UIState(BaseModel):
    """Model for UI state persistence"""

    manufacturer: Optional[str] = None
    device: Optional[str] = None
    community_folder: Optional[str] = None
    midi_in_port: Optional[str] = None
    midi_out_port: Optional[str] = None
    sequencer_port: Optional[str] = None
    midi_channel: Optional[int] = None
    sync_enabled: bool = True


class ManufacturerRequest(BaseModel):
    """Model for manufacturer request"""

    manufacturer: str


class ManufacturerCreate(BaseModel):
    """Model for creating a manufacturer"""

    name: str


class DeviceCreate(BaseModel):
    """Model for creating a device"""

    name: str
    manufacturer: str
    version: str = "1.0.0"
    manufacturer_id: int = 0
    device_id: int = 0
    midi_ports: Dict[str, str] = Field(default_factory=dict)
    midi_channels: Dict[str, int] = Field(default_factory=dict)


class PresetCollectionCreate(BaseModel):
    """Model for creating a preset collection"""

    name: str
    device: str
    manufacturer: str
    version: str = "1.0"
    revision: int = 1
    author: str = "User"
    description: str = ""


class PresetCreate(BaseModel):
    """Model for creating a preset"""

    preset_name: str
    category: str
    collection: str
    device: str
    manufacturer: str
    cc_0: Optional[int] = None
    pgm: int
    characters: List[str] = Field(default_factory=list)
    sendmidi_command: Optional[str] = None


class DirectoryStructureRequest(BaseModel):
    """Model for checking/creating directory structure"""

    manufacturer: str
    device: str
    create_if_missing: bool = True


class DirectoryStructureResponse(BaseModel):
    """Response model for directory structure check"""

    manufacturer_exists: bool
    device_exists: bool
    json_exists: bool
    created_manufacturer: bool = False
    created_device: bool = False
    created_json: bool = False
    json_path: Optional[str] = None
