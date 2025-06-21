import json
import logging
import logging.handlers
import os
import re
import socket
import sys
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

# Load environment variables from .env file
load_dotenv()


# Path validation utility functions
def validate_path_component(component: str) -> bool:
    """
    Validate a path component to prevent path traversal attacks.

    Args:
        component: A single path component (filename or directory name)

    Returns:
        True if the component is safe, False otherwise
    """
    # Reject empty components
    if not component or component.isspace():
        return False

    # Reject components with path traversal sequences
    if ".." in component or "/" in component or "\\" in component:
        return False

    # Only allow alphanumeric characters, underscores, hyphens, and spaces
    return bool(re.match(r"^[a-zA-Z0-9_\-\s.]+$", component))


def sanitize_path_component(component: str) -> str:
    """
    Sanitize a path component by removing or replacing unsafe characters.

    Args:
        component: A single path component (filename or directory name)

    Returns:
        A sanitized version of the component
    """
    # Replace spaces with underscores
    sanitized = component.replace(" ", "_")

    # Remove any characters that aren't alphanumeric, underscore, hyphen, or period
    sanitized = re.sub(r"[^a-zA-Z0-9_\-.]", "", sanitized)

    # Ensure the component doesn't start with a period (hidden file)
    if sanitized.startswith("."):
        sanitized = "x" + sanitized

    return sanitized


def safe_path_join(base_path: str, *components: str) -> Tuple[str, bool, bool]:
    """
    Safely join path components to prevent path traversal attacks.

    Args:
        base_path: The base directory path
        *components: Path components to join

    Returns:
        Tuple of (joined_path, is_safe, was_sanitized)
    """
    # Create sanitized components
    sanitized_components = []
    for component in components:
        if not validate_path_component(component):
            sanitized = sanitize_path_component(component)
            # We'll log this later when the logger is available
            sanitized_components.append(sanitized)
        else:
            sanitized_components.append(component)

    # Join the path components
    joined_path = os.path.join(base_path, *sanitized_components)

    # Ensure the joined path is within the base path
    real_base = os.path.realpath(base_path)
    real_joined = os.path.realpath(joined_path)

    is_safe = real_joined.startswith(real_base)

    # We'll log any issues later when the logger is available
    return joined_path, is_safe, sanitized_components != list(components)


# Import modules - handle both relative and absolute imports
try:
    # Try relative imports first (when imported as package)
    from .device_manager import DeviceManager
    from .git_operations import git_sync as git_sync_operation
    from .midi_utils import MidiUtils
    from .models import (Device, DeviceCreate, DirectoryStructureRequest,
                         DirectoryStructureResponse, ManufacturerCreate,
                         ManufacturerRequest, Preset, PresetCreate,
                         PresetRequest)
    from .version import __version__
except ImportError:
    # Fall back to absolute imports (when run directly)
    from server.device_manager import DeviceManager
    from server.git_operations import git_sync as git_sync_operation
    from server.midi_utils import MidiUtils
    from server.models import (Device, DeviceCreate, DirectoryStructureRequest,
                               DirectoryStructureResponse, ManufacturerCreate,
                               ManufacturerRequest, Preset, PresetCreate,
                               PresetRequest)
    from server.version import __version__

# Configure logging
# Create logs directory if it doesn't exist
logs_dir = os.path.join(os.path.dirname(__file__), "logs")
os.makedirs(logs_dir, exist_ok=True)

# Define log format
log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
formatter = logging.Formatter(log_format)

# Set up rotating file handlers for log rotation
# Each log file will be limited to 10 MB, and we'll keep 10 backup files
# This ensures logs don't exceed 100 MB in total (10 files * 10 MB)
max_bytes = 10 * 1024 * 1024  # 10 MB
backup_count = 10

# Configure root logger with rotating file handlers
root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)

# Console handler
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(formatter)
root_logger.addHandler(console_handler)

# Main log rotating file handler
main_log_handler = logging.handlers.RotatingFileHandler(
    os.path.join(logs_dir, "main.log"),
    maxBytes=max_bytes,
    backupCount=backup_count,
    mode="a",
)
main_log_handler.setFormatter(formatter)
root_logger.addHandler(main_log_handler)

# All log rotating file handler
all_log_handler = logging.handlers.RotatingFileHandler(
    os.path.join(logs_dir, "all.log"),
    maxBytes=max_bytes,
    backupCount=backup_count,
    mode="a",
)
all_log_handler.setFormatter(formatter)
root_logger.addHandler(all_log_handler)

# Configure module-specific loggers
device_manager_logger = logging.getLogger("device_manager")
device_manager_logger.setLevel(logging.INFO)
device_manager_handler = logging.handlers.RotatingFileHandler(
    os.path.join(logs_dir, "device_manager.log"),
    maxBytes=max_bytes,
    backupCount=backup_count,
    mode="a",
)
device_manager_handler.setFormatter(formatter)
device_manager_logger.addHandler(device_manager_handler)

midi_utils_logger = logging.getLogger("midi_utils")
midi_utils_logger.setLevel(logging.INFO)
midi_utils_handler = logging.handlers.RotatingFileHandler(
    os.path.join(logs_dir, "midi_utils.log"),
    maxBytes=max_bytes,
    backupCount=backup_count,
    mode="a",
)
midi_utils_handler.setFormatter(formatter)
midi_utils_logger.addHandler(midi_utils_handler)

ui_launcher_logger = logging.getLogger("ui_launcher")
ui_launcher_logger.setLevel(logging.INFO)
ui_launcher_handler = logging.handlers.RotatingFileHandler(
    os.path.join(logs_dir, "ui_launcher.log"),
    maxBytes=max_bytes,
    backupCount=backup_count,
    mode="a",
)
ui_launcher_handler.setFormatter(formatter)
ui_launcher_logger.addHandler(ui_launcher_handler)

logger = logging.getLogger(__name__)


def is_port_in_use(port: int) -> bool:
    """
    Check if a port is already in use

    Args:
        port: Port number to check

    Returns:
        True if the port is in use, False otherwise
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0


def find_available_port(start_port: int, max_attempts: int = 10) -> int:
    """
    Find an available port starting from start_port

    Args:
        start_port: Port number to start checking from
        max_attempts: Maximum number of ports to check

    Returns:
        An available port number
    """
    port = start_port
    for _ in range(max_attempts):
        if not is_port_in_use(port):
            return port
        port += 1
    # If we couldn't find an available port, return the original port
    # This will likely fail, but it's better than returning an invalid port
    logger.warning(f"Could not find an available port after {max_attempts} attempts")
    return start_port


# Initialize components
device_manager = DeviceManager()


# Define lifespan context manager (replaces on_event handlers)
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize the application
    logger.info("Application starting up...")

    try:
        # Scan for devices
        logger.info("Scanning for MIDI devices...")
        device_manager.scan_devices()
        logger.info(f"Found {len(device_manager.devices)} devices")

    except Exception as e:
        logger.error(f"Error during startup: {str(e)}")

    # Yield control to FastAPI
    yield

    # Shutdown: Clean up resources
    logger.info("Application shutting down...")


# Create FastAPI app with lifespan
app = FastAPI(
    title="MIDI Preset Selection API",
    description="API for selecting MIDI presets and controlling MIDI devices",
    version=__version__,
    lifespan=lifespan,
)

# Add CORS middleware to allow client connections
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
        "http://localhost:*",
        "http://127.0.0.1:*",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


# API Routes
@app.get("/manufacturers", response_model=List[str])
async def get_manufacturers():
    """Return all manufacturers"""
    try:
        manufacturers = device_manager.get_manufacturers()
        logger.info(f"Returning {len(manufacturers)} manufacturers: {manufacturers}")
        return manufacturers
    except Exception as e:
        logger.error(f"Error getting manufacturers: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error getting manufacturers: {str(e)}"
        )


@app.get("/devices/{manufacturer}", response_model=List[str])
async def get_devices_by_manufacturer(manufacturer: str):
    """Return all devices for a specific manufacturer"""
    try:
        devices = device_manager.get_devices_by_manufacturer(manufacturer)
        logger.info(
            f"Returning {len(devices)} devices for manufacturer {manufacturer}: {devices}"
        )
        return devices
    except Exception as e:
        logger.error(f"Error getting devices for manufacturer {manufacturer}: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Error getting devices for manufacturer {manufacturer}: {str(e)}",
        )


@app.post("/device_info", response_model=List[Dict[str, Any]])
async def get_device_info(request: ManufacturerRequest):
    """Return device info for a specific manufacturer"""
    try:
        manufacturer = request.manufacturer
        device_info = device_manager.get_device_info_by_manufacturer(manufacturer)
        logger.info(
            f"Returning device info for {len(device_info)} devices for manufacturer {manufacturer}"
        )
        return device_info
    except Exception as e:
        logger.error(
            f"Error getting device info for manufacturer {request.manufacturer}: {str(e)}"
        )
        raise HTTPException(
            status_code=500,
            detail=f"Error getting device info for manufacturer {request.manufacturer}: {str(e)}",
        )


@app.get("/community_folders/{device_name}", response_model=List[str])
async def get_community_folders(device_name: str):
    """Return all community folders for a specific device"""
    try:
        folders = device_manager.get_community_folders(device_name)
        logger.info(
            f"Returning {len(folders)} community folders for device {device_name}: {folders}"
        )
        return folders
    except Exception as e:
        logger.error(
            f"Error getting community folders for device {device_name}: {str(e)}"
        )
        raise HTTPException(
            status_code=500,
            detail=f"Error getting community folders for device {device_name}: {str(e)}",
        )


@app.get("/presets/{manufacturer}/{device}", response_model=List[Preset])
async def get_presets_by_manufacturer_and_device(
    manufacturer: str, device: str, community_folder: Optional[str] = None
):
    """
    Return presets for a specific manufacturer and device

    Args:
        manufacturer: Name of the manufacturer
        device: Name of the device
        community_folder: Optional name of the community folder to get presets from
    """
    try:
        presets = device_manager.get_all_presets(
            device_name=device,
            community_folder=community_folder,
            manufacturer=manufacturer,
        )
        logger.info(
            f"Returning {len(presets)} presets for manufacturer {manufacturer}, device {device}"
        )
        if presets:
            logger.debug(f"First 5 presets: {[p.preset_name for p in presets[:5]]}")
        return presets
    except Exception as e:
        logger.error(
            f"Error getting presets for manufacturer {manufacturer}, device {device}: {str(e)}"
        )
        raise HTTPException(
            status_code=500,
            detail=f"Error getting presets for manufacturer {manufacturer}, device {device}: {str(e)}",
        )


@app.get("/midi_ports", response_model=Dict[str, List[str]])
async def get_midi_ports():
    """Return dictionary of in/out MIDI ports available on the system"""
    try:
        ports = MidiUtils.get_midi_ports()
        logger.info(
            f"Returning MIDI ports: in={len(ports.get('in', []))}, out={len(ports.get('out', []))}"
        )
        logger.debug(f"MIDI ports details: {ports}")
        return ports
    except Exception as e:
        logger.error(f"Error getting MIDI ports: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error getting MIDI ports: {str(e)}"
        )


@app.post("/preset")
async def send_preset(preset: PresetRequest):
    """Send MIDI command for specified preset to specified port/channel"""
    logger.info(
        f"Received preset request: {preset.preset_name} to port {preset.midi_port} on channel {preset.midi_channel}"
    )

    try:
        # Get the preset data
        preset_data = device_manager.get_preset_by_name(preset.preset_name)
        if not preset_data:
            logger.warning(f"Preset '{preset.preset_name}' not found")
            raise HTTPException(
                status_code=404, detail=f"Preset '{preset.preset_name}' not found"
            )

        # Get the bank select (cc_0) and program change (pgm) values
        cc_value = preset_data.get("cc_0")
        pgm_value = preset_data.get("pgm")

        if cc_value is None or pgm_value is None:
            logger.warning(
                f"Missing cc_0 or pgm values for preset '{preset.preset_name}'"
            )
            raise HTTPException(
                status_code=400,
                detail=f"Missing cc_0 or pgm values for preset '{preset.preset_name}'",
            )

        # Use the new send_preset_select function
        logger.info(
            f"Sending preset select: port={preset.midi_port}, channel={preset.midi_channel}, cc0={cc_value}, pgm={pgm_value}"
        )

        # Execute the command
        try:
            success, message = await MidiUtils.asend_preset_select(
                port_name=preset.midi_port,
                channel=preset.midi_channel,
                pgm_value=pgm_value,
                cc_value=cc_value,
                cc_number=0,  # Default to Bank Select (CC 0)
                sequencer_port=preset.sequencer_port,
            )

            if not success:
                logger.error(f"Preset selection failed: {message}")
                raise HTTPException(status_code=500, detail=message)

            logger.info(f"Preset selection succeeded: {message}")

            # If sequencer port is specified, log it
            if preset.sequencer_port:
                logger.info(f"Also sent to sequencer port: {preset.sequencer_port}")

            return {"status": "success", "message": message}

        except Exception as e:
            logger.error(f"Error executing preset selection: {str(e)}")
            raise HTTPException(
                status_code=500, detail=f"Error executing preset selection: {str(e)}"
            )

    except HTTPException:
        # Re-raise HTTP exceptions to preserve their status codes
        raise
    except Exception as e:
        logger.error(f"Unexpected error sending preset: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


# Directory structure management
@app.post("/directory_structure", response_model=DirectoryStructureResponse)
async def check_directory_structure(request: DirectoryStructureRequest):
    """Check if the manufacturer and device directories exist, and if the device JSON file exists"""
    try:
        response = device_manager.check_directory_structure(
            request.manufacturer, request.device, request.create_if_missing
        )
        logger.info(
            f"Checked directory structure for {request.manufacturer}/{request.device}"
        )
        return response
    except Exception as e:
        logger.error(f"Error checking directory structure: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error checking directory structure: {str(e)}"
        )


# Manufacturer management
@app.post("/manufacturers", status_code=status.HTTP_201_CREATED)
async def create_manufacturer(manufacturer: ManufacturerCreate):
    """Create a new manufacturer"""
    try:
        success, message = device_manager.create_manufacturer(manufacturer.name)
        if not success:
            logger.error(f"Error creating manufacturer: {message}")
            raise HTTPException(status_code=400, detail=message)

        logger.info(f"Created manufacturer: {manufacturer.name}")
        return {"status": "success", "message": message}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating manufacturer: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error creating manufacturer: {str(e)}"
        )


@app.delete("/manufacturers/{manufacturer_name}")
async def delete_manufacturer(manufacturer_name: str):
    """Delete a manufacturer and all its devices"""
    try:
        success, message = device_manager.delete_manufacturer(manufacturer_name)
        if not success:
            logger.error(f"Error deleting manufacturer: {message}")
            raise HTTPException(status_code=404, detail=message)

        logger.info(f"Deleted manufacturer: {manufacturer_name}")
        return {"status": "success", "message": message}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting manufacturer: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error deleting manufacturer: {str(e)}"
        )


# Device management
@app.post("/devices", status_code=status.HTTP_201_CREATED)
async def create_device(device: DeviceCreate):
    """Create a new device"""
    try:
        success, message, json_path = device_manager.create_device(device.model_dump())
        if not success:
            logger.error(f"Error creating device: {message}")
            raise HTTPException(status_code=400, detail=message)

        logger.info(
            f"Created device: {device.name} for manufacturer {device.manufacturer}"
        )
        return {"status": "success", "message": message, "json_path": json_path}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating device: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error creating device: {str(e)}")


@app.delete("/devices/{manufacturer}/{device_name}")
async def delete_device(manufacturer: str, device_name: str):
    """Delete a device and all its presets"""
    try:
        success, message = device_manager.delete_device(manufacturer, device_name)
        if not success:
            logger.error(f"Error deleting device: {message}")
            raise HTTPException(status_code=404, detail=message)

        logger.info(f"Deleted device: {device_name} for manufacturer {manufacturer}")
        return {"status": "success", "message": message}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting device: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error deleting device: {str(e)}")


# Preset management
@app.post("/presets", status_code=status.HTTP_201_CREATED)
async def create_preset(preset: PresetCreate):
    """Create a new preset"""
    try:
        success, message = device_manager.create_preset(preset.model_dump())
        if not success:
            logger.error(f"Error creating preset: {message}")
            raise HTTPException(status_code=400, detail=message)

        logger.info(f"Created preset: {preset.preset_name} for device {preset.device}")
        return {"status": "success", "message": message}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating preset: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error creating preset: {str(e)}")


@app.put("/presets", status_code=status.HTTP_200_OK)
async def update_preset(preset: PresetCreate):
    """Update an existing preset"""
    try:
        success, message = device_manager.update_preset(preset.model_dump())
        if not success:
            logger.error(f"Error updating preset: {message}")
            raise HTTPException(status_code=400, detail=message)

        logger.info(f"Updated preset: {preset.preset_name} for device {preset.device}")
        return {"status": "success", "message": message}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating preset: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error updating preset: {str(e)}")


@app.delete("/presets/{manufacturer}/{device}/{collection}/{preset_name}")
async def delete_preset(
    manufacturer: str, device: str, collection: str, preset_name: str
):
    """Delete a preset"""
    try:
        success, message = device_manager.delete_preset(
            manufacturer, device, collection, preset_name
        )
        if not success:
            logger.error(f"Error deleting preset: {message}")
            raise HTTPException(status_code=404, detail=message)

        logger.info(
            f"Deleted preset: {preset_name} from collection {collection} for device {device}"
        )
        return {"status": "success", "message": message}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting preset: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error deleting preset: {str(e)}")


# Collection management endpoints
@app.get("/collections/{manufacturer}/{device}", response_model=List[str])
async def get_collections(manufacturer: str, device: str):
    """Get all collections for a device"""
    try:
        # Check if manufacturer exists
        if manufacturer not in device_manager.manufacturers:
            logger.warning(f"Manufacturer not found: {manufacturer}")
            raise HTTPException(
                status_code=404, detail=f"Manufacturer '{manufacturer}' not found"
            )

        # Check if device exists
        devices = device_manager.get_devices_by_manufacturer(manufacturer)
        if device not in devices:
            logger.warning(f"Device not found: {device}")
            raise HTTPException(status_code=404, detail=f"Device '{device}' not found")

        # Get the device data
        device_data = device_manager.get_device_by_name(device)
        if not device_data:
            logger.warning(f"Device data not found: {device}")
            raise HTTPException(
                status_code=404, detail=f"Device data for '{device}' not found"
            )

        # Get collections
        collections = list(device_data.get("preset_collections", {}).keys())
        logger.info(
            f"Returning {len(collections)} collections for {manufacturer}/{device}"
        )
        return collections
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting collections: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error getting collections: {str(e)}"
        )


@app.post("/collections/{manufacturer}/{device}/{collection_name}")
async def create_collection(manufacturer: str, device: str, collection_name: str):
    """Create a new collection"""
    try:
        # Check if manufacturer exists
        if manufacturer not in device_manager.manufacturers:
            logger.warning(f"Manufacturer not found: {manufacturer}")
            raise HTTPException(
                status_code=404, detail=f"Manufacturer '{manufacturer}' not found"
            )

        # Check if device exists
        devices = device_manager.get_devices_by_manufacturer(manufacturer)
        if device not in devices:
            logger.warning(f"Device not found: {device}")
            raise HTTPException(status_code=404, detail=f"Device '{device}' not found")

        # Get the device data
        device_data = device_manager.get_device_by_name(device)
        if not device_data:
            logger.warning(f"Device data not found: {device}")
            raise HTTPException(
                status_code=404, detail=f"Device data for '{device}' not found"
            )

        # Check if preset_collections exists, create it if it doesn't
        if "preset_collections" not in device_data:
            device_data["preset_collections"] = {}
            logger.info(f"Created preset_collections for device '{device}'")

        # Check if collection already exists
        preset_collections = device_data.get("preset_collections", {})
        if collection_name in preset_collections:
            logger.info(
                f"Collection '{collection_name}' already exists for device '{device}'"
            )
            return {
                "status": "success",
                "message": f"Collection '{collection_name}' already exists",
            }

        # Create the collection
        collection_display_name = (
            "Factory Presets"
            if collection_name == "factory_presets"
            else collection_name
        )
        preset_collections[collection_name] = {
            "metadata": {
                "name": collection_display_name,
                "version": "1.0",
                "revision": 1,
                "author": "r2midi",
                "description": f"{collection_display_name} for {device}",
                "readonly": False,
                "preset_count": 0,
                "parent_collections": [],
                "sync_status": "synced",
                "created_at": datetime.now().isoformat(),
                "modified_at": datetime.now().isoformat(),
            },
            "presets": [],
            "preset_metadata": {},
        }
        logger.info(f"Created collection '{collection_name}' for device '{device}'")

        # Update the device data
        device_data["preset_collections"] = preset_collections

        # Save the device data - use safe path handling
        device_path, is_safe, was_sanitized = safe_path_join(
            device_manager.devices_folder, manufacturer, device
        )

        if not is_safe:
            logger.error(
                f"Path traversal attempt detected for manufacturer '{manufacturer}' and device '{device}'"
            )
            raise HTTPException(status_code=400, detail="Invalid path components")

        if was_sanitized:
            logger.warning(
                f"Path components were sanitized for manufacturer '{manufacturer}' and device '{device}'"
            )

        if not os.path.exists(device_path):
            raise HTTPException(
                status_code=404, detail=f"Device path not found: '{device_path}'"
            )

        json_files = [f for f in os.listdir(device_path) if f.endswith(".json")]

        if not json_files:
            raise HTTPException(
                status_code=404, detail=f"No JSON file found for device '{device}'"
            )

        # Validate the JSON filename
        json_filename = json_files[0]
        if not validate_path_component(json_filename):
            logger.warning(f"Unsafe JSON filename: '{json_filename}'")
            json_filename = sanitize_path_component(json_filename)

        json_path, is_safe, _ = safe_path_join(device_path, json_filename)

        if not is_safe:
            logger.error(
                f"Path traversal attempt detected for JSON file: '{json_filename}'"
            )
            raise HTTPException(status_code=400, detail="Invalid JSON filename")

        with open(json_path, "w") as f:
            json.dump(device_data, f, indent=2)

        logger.info(f"Saved collection '{collection_name}' for device '{device}'")
        return {
            "status": "success",
            "message": f"Collection '{collection_name}' created successfully",
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating collection: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error creating collection: {str(e)}"
        )


@app.put("/collections/{manufacturer}/{device}/{collection_name}")
async def update_collection(
    manufacturer: str, device: str, collection_name: str, data: Dict[str, str]
):
    """Update a collection (rename)"""
    try:
        new_name = data.get("new_name")
        if not new_name:
            raise HTTPException(status_code=400, detail="New name is required")

        # Check if manufacturer exists
        if manufacturer not in device_manager.manufacturers:
            logger.warning(f"Manufacturer not found: {manufacturer}")
            raise HTTPException(
                status_code=404, detail=f"Manufacturer '{manufacturer}' not found"
            )

        # Check if device exists
        devices = device_manager.get_devices_by_manufacturer(manufacturer)
        if device not in devices:
            logger.warning(f"Device not found: {device}")
            raise HTTPException(status_code=404, detail=f"Device '{device}' not found")

        # Get the device data
        device_data = device_manager.get_device_by_name(device)
        if not device_data:
            logger.warning(f"Device data not found: {device}")
            raise HTTPException(
                status_code=404, detail=f"Device data for '{device}' not found"
            )

        # Check if collection exists
        preset_collections = device_data.get("preset_collections", {})
        if collection_name not in preset_collections:
            logger.warning(f"Collection not found: {collection_name}")
            raise HTTPException(
                status_code=404, detail=f"Collection '{collection_name}' not found"
            )

        # Check if new name already exists
        if new_name in preset_collections:
            logger.warning(f"Collection with name '{new_name}' already exists")
            raise HTTPException(
                status_code=400,
                detail=f"Collection with name '{new_name}' already exists",
            )

        # Rename the collection
        preset_collections[new_name] = preset_collections[collection_name]
        preset_collections[new_name]["metadata"]["name"] = new_name
        preset_collections[new_name]["metadata"][
            "modified_at"
        ] = datetime.now().isoformat()
        del preset_collections[collection_name]

        # Update the device data
        device_data["preset_collections"] = preset_collections

        # Save the device data - use safe path handling
        device_path, is_safe, was_sanitized = safe_path_join(
            device_manager.devices_folder, manufacturer, device
        )

        if not is_safe:
            logger.error(
                f"Path traversal attempt detected for manufacturer '{manufacturer}' and device '{device}'"
            )
            raise HTTPException(status_code=400, detail="Invalid path components")

        if was_sanitized:
            logger.warning(
                f"Path components were sanitized for manufacturer '{manufacturer}' and device '{device}'"
            )

        if not os.path.exists(device_path):
            raise HTTPException(
                status_code=404, detail=f"Device path not found: '{device_path}'"
            )

        json_files = [f for f in os.listdir(device_path) if f.endswith(".json")]

        if not json_files:
            raise HTTPException(
                status_code=404, detail=f"No JSON file found for device '{device}'"
            )

        # Validate the JSON filename
        json_filename = json_files[0]
        if not validate_path_component(json_filename):
            logger.warning(f"Unsafe JSON filename: '{json_filename}'")
            json_filename = sanitize_path_component(json_filename)

        json_path, is_safe, _ = safe_path_join(device_path, json_filename)

        if not is_safe:
            logger.error(
                f"Path traversal attempt detected for JSON file: '{json_filename}'"
            )
            raise HTTPException(status_code=400, detail="Invalid JSON filename")

        with open(json_path, "w") as f:
            json.dump(device_data, f, indent=2)

        logger.info(
            f"Renamed collection '{collection_name}' to '{new_name}' for device '{device}'"
        )
        return {
            "status": "success",
            "message": f"Collection '{collection_name}' renamed to '{new_name}' successfully",
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating collection: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error updating collection: {str(e)}"
        )


@app.delete("/collections/{manufacturer}/{device}/{collection_name}")
async def delete_collection(manufacturer: str, device: str, collection_name: str):
    """Delete a collection"""
    try:
        # Check if manufacturer exists
        if manufacturer not in device_manager.manufacturers:
            logger.warning(f"Manufacturer not found: {manufacturer}")
            raise HTTPException(
                status_code=404, detail=f"Manufacturer '{manufacturer}' not found"
            )

        # Check if device exists
        devices = device_manager.get_devices_by_manufacturer(manufacturer)
        if device not in devices:
            logger.warning(f"Device not found: {device}")
            raise HTTPException(status_code=404, detail=f"Device '{device}' not found")

        # Get the device data
        device_data = device_manager.get_device_by_name(device)
        if not device_data:
            logger.warning(f"Device data not found: {device}")
            raise HTTPException(
                status_code=404, detail=f"Device data for '{device}' not found"
            )

        # Check if collection exists
        preset_collections = device_data.get("preset_collections", {})
        if collection_name not in preset_collections:
            logger.warning(f"Collection not found: {collection_name}")
            raise HTTPException(
                status_code=404, detail=f"Collection '{collection_name}' not found"
            )

        # Delete the collection
        del preset_collections[collection_name]

        # Update the device data
        device_data["preset_collections"] = preset_collections

        # Save the device data
        device_path = os.path.join(device_manager.devices_folder, manufacturer, device)
        json_files = [f for f in os.listdir(device_path) if f.endswith(".json")]

        if not json_files:
            raise HTTPException(
                status_code=404, detail=f"No JSON file found for device '{device}'"
            )

        json_path = os.path.join(device_path, json_files[0])

        with open(json_path, "w") as f:
            json.dump(device_data, f, indent=2)

        logger.info(f"Deleted collection '{collection_name}' for device '{device}'")
        return {
            "status": "success",
            "message": f"Collection '{collection_name}' deleted successfully",
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting collection: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Error deleting collection: {str(e)}"
        )


# Git operations
@app.get("/git/sync")
async def git_sync(sync_enabled: bool = True):
    """
    Sync midi-presets based on R2MIDI_ROLE environment variable

    This endpoint:
    1. Checks R2MIDI_ROLE environment variable
    2. If 'dev': Uses git submodule approach
    3. If 'release' or unset: Uses git clone approach
    4. Ensures midi-presets is in the correct state

    Args:
        sync_enabled: Whether to perform the sync operation (default: True)

    Returns:
        JSON response with status and message
    """
    # Skip sync if disabled
    if not sync_enabled:
        logger.info("Sync is disabled, skipping git submodule sync")
        return {"status": "skipped", "message": "Sync is disabled"}

    # Call the git_sync function from the git_operations module
    success, message, _ = git_sync_operation()

    # Return the appropriate response based on the result
    if success:
        return {"status": "success", "message": message}
    else:
        return {"status": "error", "message": message}


@app.get("/git/remote_sync")
async def git_remote_sync():
    """
    Add, commit, and push changes to the midi-presets repository

    This endpoint:
    1. Determines the mode (submodule or clone) based on R2MIDI_ROLE
    2. Adds all changes with git add .
    3. Commits the changes with the message "new presets"
    4. Pushes the changes to the remote repository
    5. If in submodule mode, updates the submodule reference in the parent repository

    Returns:
        JSON response with status and message
    """
    try:
        # Import the git_remote_sync function from the git_operations module
        from server.git_operations import \
            git_remote_sync as git_remote_sync_operation
    except ImportError:
        # Fall back to absolute imports (when run directly)
        from server.git_operations import \
            git_remote_sync as git_remote_sync_operation

    # Call the git_remote_sync function from the git_operations module
    success, message, status_code = git_remote_sync_operation()

    # Return the appropriate response based on the result
    if success:
        return {"status": "success", "message": message}
    else:
        return {"status": "error", "message": message}


def main():
    """Main entry point for the server application"""
    run_server()


def run_server():
    """Run the server application"""
    # Get port from environment variable with default of 7777
    requested_port = int(os.getenv("PORT", 7777))

    # Find an available port starting from the requested port
    port = find_available_port(requested_port)

    if port != requested_port:
        logger.info(f"Port {requested_port} is in use, using port {port} instead")

    logger.info(f"Starting server on port {port}")

    # Start the server
    logger.info(f"Starting server on port {port}...")

    # Add a log message to indicate server is about to start
    print(
        f"\n{'='*50}\nServer is starting on http://0.0.0.0:{port}\nPress Ctrl+C to stop\n{'='*50}\n"
    )

    # Configure uvicorn logging to use our logging setup
    uvicorn_log_config = uvicorn.config.LOGGING_CONFIG
    uvicorn_log_config["handlers"]["default"]["stream"] = sys.stdout
    uvicorn_log_config["handlers"]["access"]["stream"] = sys.stdout

    # Add a rotating file handler for uvicorn logs
    uvicorn_log_config["handlers"]["file"] = {
        "class": "logging.handlers.RotatingFileHandler",
        "formatter": "default",
        "filename": os.path.join(logs_dir, "uvicorn.log"),
        "maxBytes": max_bytes,
        "backupCount": backup_count,
        "mode": "a",
    }
    uvicorn_log_config["loggers"]["uvicorn"]["handlers"].append("file")
    uvicorn_log_config["loggers"]["uvicorn.access"]["handlers"].append("file")

    # Run the server
    uvicorn.run(app, host="0.0.0.0", port=port, log_config=uvicorn_log_config)


# Run the application
if __name__ == "__main__":
    main()
