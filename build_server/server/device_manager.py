import concurrent.futures
import json
import logging
import os
import re
import shutil
import subprocess
import time
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

# Import modules - handle both relative and absolute imports
try:
    # Try relative imports first (when imported as package)
    from .models import Device, DirectoryStructureResponse, Preset
except ImportError:
    # Fall back to absolute imports (when run directly)
    from server.models import Device, DirectoryStructureResponse, Preset


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
    was_sanitized = False

    for component in components:
        if not validate_path_component(component):
            sanitized = sanitize_path_component(component)
            sanitized_components.append(sanitized)
            was_sanitized = True
        else:
            sanitized_components.append(component)

    # Join the path components
    joined_path = os.path.join(base_path, *sanitized_components)

    # Ensure the joined path is within the base path
    real_base = os.path.realpath(base_path)
    real_joined = os.path.realpath(joined_path)

    is_safe = real_joined.startswith(real_base)

    return joined_path, is_safe, was_sanitized


# Get logger
logger = logging.getLogger(__name__)


class DeviceManager:
    """Handles scanning and managing device data"""

    def __init__(self, devices_folder=None, sync_enabled=True):
        """
        Initialize the device manager with the path to the devices folder

        Args:
            devices_folder: Path to the devices folder
            sync_enabled: Whether to sync with the remote repository
        """
        if devices_folder is None:
            # Default to midi-presets/devices relative to this file
            devices_folder = os.path.join(
                os.path.dirname(__file__), "midi-presets", "devices"
            )
        self.devices_folder = devices_folder
        self.devices = {}  # Map of device name to device data
        self.manufacturers = []  # List of manufacturer names
        self.device_structure = {}  # Map of manufacturer to list of devices
        self._json_cache = {}  # Cache for loaded JSON files
        self._cache_timeout = 3600  # Cache timeout in seconds (1 hour)
        self.sync_enabled = sync_enabled

        # Validate that the midi-presets submodule exists and is up to date
        self._validate_midi_presets_submodule()

    def _validate_midi_presets_submodule(self):
        """
        Validate that the midi-presets exists based on R2MIDI_ROLE environment variable.
        - If R2MIDI_ROLE=dev: Use as git submodule
        - If R2MIDI_ROLE=release (or unset): Use as cloned repository
        """
        import os

        try:
            from .git_operations import get_midi_presets_mode, git_sync
        except ImportError:
            from server.git_operations import get_midi_presets_mode, git_sync

        mode = get_midi_presets_mode()
        logger.info(f"Validating midi-presets in {mode} mode")

        # Skip sync if disabled
        if not self.sync_enabled:
            logger.info("Sync is disabled, skipping git validation")
            # Still check if the directory exists
            midi_presets_dir = os.path.join(os.path.dirname(__file__), "midi-presets")
            if not os.path.exists(midi_presets_dir):
                logger.warning(
                    "midi-presets directory does not exist and sync is disabled"
                )
            return

        # Check if the midi-presets directory exists
        midi_presets_dir = os.path.join(os.path.dirname(__file__), "midi-presets")
        if not os.path.exists(midi_presets_dir):
            logger.warning(
                f"midi-presets directory does not exist, attempting to initialize it in {mode} mode"
            )
            success, message, _ = git_sync()
            if not success:
                logger.error(f"Failed to initialize midi-presets: {message}")
                return
            logger.info(f"Successfully initialized midi-presets: {message}")
        else:
            # Always run git_sync to ensure we have the right type (clone vs submodule)
            logger.info(
                f"Ensuring midi-presets is correctly configured for {mode} mode"
            )
            success, message, _ = git_sync()
            if not success:
                logger.error(f"Failed to configure midi-presets: {message}")
                return
            logger.info(f"Successfully configured midi-presets: {message}")

    def _load_json_file(self, file_path: str, cache_timeout: int = None) -> Dict:
        """
        Load a JSON file with caching to improve performance

        Args:
            file_path: Path to the JSON file
            cache_timeout: Optional cache timeout in seconds (defaults to self._cache_timeout)

        Returns:
            Dictionary containing the JSON data
        """
        # Use instance cache_timeout if not provided
        if cache_timeout is None:
            cache_timeout = self._cache_timeout

        # Check if file exists
        if not os.path.exists(file_path):
            logger.warning(f"JSON file not found: {file_path}")
            return {}

        # Check if file is in cache and not expired
        if file_path in self._json_cache:
            timestamp, data = self._json_cache[file_path]
            if time.time() - timestamp < cache_timeout:
                logger.debug(f"Using cached JSON data for {file_path}")
                return data

        # Load file and update cache
        try:
            start_time = time.time()
            with open(file_path, "r") as f:
                data = json.load(f)
            load_time = time.time() - start_time
            logger.debug(f"Loaded JSON file {file_path} in {load_time:.4f} seconds")

            # Update cache with the new timeout
            self._json_cache[file_path] = (time.time(), data)
            return data
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in file {file_path}: {str(e)}")
            return {}
        except Exception as e:
            logger.error(f"Error loading JSON file {file_path}: {str(e)}")
            return {}

    def run_git_sync(self) -> Tuple[bool, str]:
        """
        Run git sync to update the midi-presets based on R2MIDI_ROLE
        Returns a tuple of (success, message)
        """
        try:
            from .git_operations import get_midi_presets_mode, git_sync
        except ImportError:
            from server.git_operations import get_midi_presets_mode, git_sync

        mode = get_midi_presets_mode()
        logger.info(f"Running git sync in {mode} mode")

        # Skip sync if disabled
        if not self.sync_enabled:
            logger.info("Sync is disabled, skipping git sync")
            return False, "Sync is disabled"

        # Use the git_sync function which handles both modes
        success, message, _ = git_sync()

        if success:
            logger.info(f"Git sync completed successfully in {mode} mode: {message}")
        else:
            logger.error(f"Git sync failed in {mode} mode: {message}")

        return success, message

    def _process_manufacturer(
        self, manufacturer: str
    ) -> Tuple[Dict[str, Dict], List[str]]:
        """
        Process a single manufacturer directory

        Args:
            manufacturer: Name of the manufacturer

        Returns:
            Tuple of (devices, device_structure)
        """
        manufacturer_path = os.path.join(self.devices_folder, manufacturer)
        logger.debug(f"Processing manufacturer directory: {manufacturer}")

        # Initialize return values
        manufacturer_devices = {}
        manufacturer_device_structure = []

        try:
            # Get list of files and directories in manufacturer directory
            items = os.listdir(manufacturer_path)

            # Process device directories and JSON files
            device_dirs = [
                d
                for d in items
                if os.path.isdir(os.path.join(manufacturer_path, d))
                and d != "community"
            ]
            json_files = [f for f in items if f.endswith(".json")]

            logger.debug(
                f"Found {len(device_dirs)} device directories and {len(json_files)} JSON files in {manufacturer} directory"
            )

            # Use a thread pool to process JSON files in parallel
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=min(32, os.cpu_count() * 2)
            ) as executor:
                # Submit tasks for each JSON file
                future_to_file = {
                    executor.submit(
                        self._load_json_file, os.path.join(manufacturer_path, filename)
                    ): filename
                    for filename in json_files
                }

                # Process results as they complete
                for future in concurrent.futures.as_completed(future_to_file):
                    filename = future_to_file[future]
                    try:
                        device_data = future.result()

                        # Check if device has device_info with a name
                        if (
                            device_data
                            and "device_info" in device_data
                            and "name" in device_data["device_info"]
                        ):
                            device_name = device_data["device_info"]["name"]

                            # Add manufacturer information
                            device_data["manufacturer"] = manufacturer

                            # Check for community folders
                            community_path = os.path.join(
                                manufacturer_path, "community"
                            )
                            community_folders = []

                            if os.path.exists(community_path) and os.path.isdir(
                                community_path
                            ):
                                community_items = [
                                    f
                                    for f in os.listdir(community_path)
                                    if f.endswith(".json")
                                ]
                                community_folders = [
                                    os.path.splitext(f)[0] for f in community_items
                                ]
                                logger.debug(
                                    f"Found {len(community_folders)} community folders for {device_name}"
                                )

                            device_data["community_folders"] = community_folders

                            # Store the device data
                            manufacturer_devices[device_name] = device_data
                            manufacturer_device_structure.append(device_name)

                            logger.debug(
                                f"Loaded device: {device_name} from manufacturer {manufacturer}"
                            )
                        else:
                            logger.warning(
                                f"Device file '{filename}' does not have a device_info.name field"
                            )
                    except Exception as e:
                        logger.error(f"Error processing JSON file {filename}: {str(e)}")

            # Process device directories
            for device_dir in device_dirs:
                device_path = os.path.join(manufacturer_path, device_dir)
                logger.debug(f"Processing device directory: {device_dir}")

                # Get JSON files in device directory
                device_json_files = [
                    f for f in os.listdir(device_path) if f.endswith(".json")
                ]

                if device_json_files:
                    # Use a thread pool to process JSON files in parallel
                    with concurrent.futures.ThreadPoolExecutor(
                        max_workers=min(32, os.cpu_count() * 2)
                    ) as executor:
                        # Submit tasks for each JSON file
                        future_to_file = {
                            executor.submit(
                                self._load_json_file,
                                os.path.join(device_path, filename),
                            ): filename
                            for filename in device_json_files
                        }

                        # Process results as they complete
                        for future in concurrent.futures.as_completed(future_to_file):
                            filename = future_to_file[future]
                            try:
                                device_data = future.result()

                                # Check if device has device_info with a name
                                if (
                                    device_data
                                    and "device_info" in device_data
                                    and "name" in device_data["device_info"]
                                ):
                                    device_name = device_data["device_info"]["name"]

                                    # Add manufacturer information
                                    device_data["manufacturer"] = manufacturer

                                    # Check for community folders
                                    community_path = os.path.join(
                                        manufacturer_path, "community"
                                    )
                                    community_folders = []

                                    if os.path.exists(community_path) and os.path.isdir(
                                        community_path
                                    ):
                                        community_items = [
                                            f
                                            for f in os.listdir(community_path)
                                            if f.endswith(".json")
                                        ]
                                        community_folders = [
                                            os.path.splitext(f)[0]
                                            for f in community_items
                                        ]
                                        logger.debug(
                                            f"Found {len(community_folders)} community folders for {device_name}"
                                        )

                                    device_data["community_folders"] = community_folders

                                    # Store the device data
                                    manufacturer_devices[device_name] = device_data
                                    manufacturer_device_structure.append(device_name)

                                    logger.debug(
                                        f"Loaded device: {device_name} from manufacturer {manufacturer}"
                                    )
                                else:
                                    logger.warning(
                                        f"Device file '{filename}' does not have a device_info.name field"
                                    )
                            except Exception as e:
                                logger.error(
                                    f"Error processing JSON file {filename}: {str(e)}"
                                )

            return manufacturer_devices, manufacturer_device_structure

        except Exception as e:
            logger.error(f"Error processing manufacturer {manufacturer}: {str(e)}")
            return {}, []

    def scan_devices(self) -> Dict[str, Dict]:
        """
        Scan devices folder for JSON files and load them into memory
        Returns a dictionary of device names to device data
        """
        logger.info(f"Scanning devices folder: {self.devices_folder}")

        # Clear existing data
        self.devices = {}
        self.manufacturers = []
        self.device_structure = {}

        # Check if devices folder exists
        if not os.path.exists(self.devices_folder):
            logger.warning(f"Devices folder '{self.devices_folder}' does not exist")
            return {}

        # Use the optimized scan implementation
        start_time = time.time()

        try:
            # Get list of manufacturer directories
            manufacturers = [
                d
                for d in os.listdir(self.devices_folder)
                if os.path.isdir(os.path.join(self.devices_folder, d))
            ]
            logger.info(f"Found {len(manufacturers)} manufacturer directories")
            self.manufacturers = manufacturers

            # Use a thread pool to process manufacturers in parallel
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=min(32, os.cpu_count() * 4)
            ) as executor:
                # Submit tasks for each manufacturer
                future_to_manufacturer = {
                    executor.submit(
                        self._process_manufacturer, manufacturer
                    ): manufacturer
                    for manufacturer in manufacturers
                }

                # Process results as they complete
                for future in concurrent.futures.as_completed(future_to_manufacturer):
                    manufacturer = future_to_manufacturer[future]
                    try:
                        manufacturer_devices, manufacturer_device_structure = (
                            future.result()
                        )
                        self.devices.update(manufacturer_devices)
                        self.device_structure[manufacturer] = (
                            manufacturer_device_structure
                        )
                        logger.info(
                            f"Processed manufacturer {manufacturer} with {len(manufacturer_device_structure)} devices"
                        )
                    except Exception as e:
                        logger.error(
                            f"Error processing manufacturer {manufacturer}: {str(e)}"
                        )

            scan_time = time.time() - start_time
            logger.info(
                f"Optimized scan completed in {scan_time:.4f} seconds, found {len(self.devices)} devices"
            )

            return self.devices
        except Exception as e:
            scan_time = time.time() - start_time
            logger.error(
                f"Error during optimized scan: {str(e)} (failed in {scan_time:.4f} seconds)"
            )
            logger.warning("Falling back to standard implementation")

        try:
            # Get list of manufacturer directories
            manufacturers = [
                d
                for d in os.listdir(self.devices_folder)
                if os.path.isdir(os.path.join(self.devices_folder, d))
            ]
            logger.info(f"Found {len(manufacturers)} manufacturer directories")
            self.manufacturers = manufacturers

            # Process each manufacturer directory
            for manufacturer in manufacturers:
                manufacturer_path = os.path.join(self.devices_folder, manufacturer)
                logger.debug(f"Processing manufacturer directory: {manufacturer}")

                # Initialize device structure for this manufacturer
                self.device_structure[manufacturer] = []

                # Get list of files and directories in manufacturer directory
                items = os.listdir(manufacturer_path)

                # Process device directories and JSON files
                device_dirs = [
                    d
                    for d in items
                    if os.path.isdir(os.path.join(manufacturer_path, d))
                    and d != "community"
                ]
                json_files = [f for f in items if f.endswith(".json")]

                logger.info(
                    f"Found {len(device_dirs)} device directories and {len(json_files)} JSON files in {manufacturer} directory"
                )

                # Process JSON files directly in manufacturer directory
                for filename in json_files:
                    file_path = os.path.join(manufacturer_path, filename)
                    logger.debug(f"Processing device file: {filename}")

                    try:
                        with open(file_path, "r") as f:
                            device_data = json.load(f)

                            # Check if device has device_info with a name
                            if (
                                "device_info" in device_data
                                and "name" in device_data["device_info"]
                            ):
                                device_name = device_data["device_info"]["name"]

                                # Add manufacturer information
                                device_data["manufacturer"] = manufacturer

                                # Check for community folders
                                community_path = os.path.join(
                                    manufacturer_path, "community"
                                )
                                community_folders = []

                                if os.path.exists(community_path) and os.path.isdir(
                                    community_path
                                ):
                                    community_items = [
                                        f
                                        for f in os.listdir(community_path)
                                        if f.endswith(".json")
                                    ]
                                    community_folders = [
                                        os.path.splitext(f)[0] for f in community_items
                                    ]
                                    logger.debug(
                                        f"Found {len(community_folders)} community folders for {device_name}"
                                    )

                                device_data["community_folders"] = community_folders

                                # Store the device data
                                self.devices[device_name] = device_data
                                self.device_structure[manufacturer].append(device_name)

                                logger.info(
                                    f"Loaded device: {device_name} from manufacturer {manufacturer}"
                                )
                            else:
                                logger.warning(
                                    f"Device file '{filename}' does not have a device_info.name field"
                                )
                    except json.JSONDecodeError as e:
                        logger.error(
                            f"Invalid JSON in device file '{filename}': {str(e)}"
                        )
                    except Exception as e:
                        logger.error(
                            f"Error loading device file '{filename}': {str(e)}"
                        )

                # Process device directories
                for device_dir in device_dirs:
                    device_dir_path = os.path.join(manufacturer_path, device_dir)
                    logger.debug(f"Processing device directory: {device_dir}")

                    # Look for JSON files in the device directory
                    device_json_files = [
                        f for f in os.listdir(device_dir_path) if f.endswith(".json")
                    ]
                    logger.info(
                        f"Found {len(device_json_files)} JSON files in {device_dir} directory"
                    )

                    for filename in device_json_files:
                        file_path = os.path.join(device_dir_path, filename)
                        logger.debug(
                            f"Processing device file: {filename} in directory {device_dir}"
                        )

                        try:
                            with open(file_path, "r") as f:
                                device_data = json.load(f)

                                # Check if device has device_info with a name
                                if (
                                    "device_info" in device_data
                                    and "name" in device_data["device_info"]
                                ):
                                    device_name = device_data["device_info"]["name"]

                                    # Add manufacturer information
                                    device_data["manufacturer"] = manufacturer

                                    # Check for community folders
                                    community_path = os.path.join(
                                        device_dir_path, "community"
                                    )
                                    community_folders = []

                                    if os.path.exists(community_path) and os.path.isdir(
                                        community_path
                                    ):
                                        community_items = [
                                            f
                                            for f in os.listdir(community_path)
                                            if f.endswith(".json")
                                        ]
                                        community_folders = [
                                            os.path.splitext(f)[0]
                                            for f in community_items
                                        ]
                                        logger.debug(
                                            f"Found {len(community_folders)} community folders for {device_name}"
                                        )

                                    device_data["community_folders"] = community_folders

                                    # Store the device data
                                    self.devices[device_name] = device_data
                                    self.device_structure[manufacturer].append(
                                        device_name
                                    )

                                    logger.info(
                                        f"Loaded device: {device_name} from manufacturer {manufacturer}"
                                    )
                                else:
                                    logger.warning(
                                        f"Device file '{filename}' in directory {device_dir} does not have a device_info.name field"
                                    )
                        except json.JSONDecodeError as e:
                            logger.error(
                                f"Invalid JSON in device file '{filename}' in directory {device_dir}: {str(e)}"
                            )
                        except Exception as e:
                            logger.error(
                                f"Error loading device file '{filename}' in directory {device_dir}: {str(e)}"
                            )

            logger.info(
                f"Loaded {len(self.devices)} devices from {len(self.manufacturers)} manufacturers"
            )
            return self.devices

        except Exception as e:
            logger.error(f"Error scanning devices folder: {str(e)}")
            return self.devices

    def get_device_by_name(self, name: str) -> Optional[Dict]:
        """Get device data by name"""
        logger.debug(f"Getting device by name: {name}")
        device = self.devices.get(name)
        if device:
            logger.debug(f"Found device: {name}")
        else:
            logger.debug(f"Device not found: {name}")
        return device

    def get_manufacturers(self) -> List[str]:
        """
        Get list of all manufacturers
        Returns a list of manufacturer names
        """
        logger.info(f"Getting all manufacturers ({len(self.manufacturers)} available)")
        return self.manufacturers

    def get_devices_by_manufacturer(self, manufacturer: str) -> List[str]:
        """
        Get list of devices for a specific manufacturer
        Returns a list of device names
        """
        logger.info(f"Getting devices for manufacturer: {manufacturer}")
        return self.device_structure.get(manufacturer, [])

    def get_device_info_by_manufacturer(self, manufacturer: str) -> List[Dict]:
        """
        Get device info for a specific manufacturer
        Returns a list of dictionaries containing device_info
        """
        logger.info(f"Getting device info for manufacturer: {manufacturer}")
        result = []

        # Check if manufacturer exists
        if manufacturer not in self.manufacturers:
            logger.warning(f"Manufacturer not found: {manufacturer}")
            return result

        # Get devices for this manufacturer
        device_names = self.device_structure.get(manufacturer, [])

        # Get device info for each device
        for device_name in device_names:
            device_data = self.devices.get(device_name)
            if device_data and "device_info" in device_data:
                result.append(device_data["device_info"])

        logger.info(f"Found {len(result)} devices for manufacturer {manufacturer}")
        return result

    def get_community_folders(self, device_name: str) -> List[str]:
        """
        Get list of community folders for a specific device
        Returns a list of folder names
        """
        logger.info(f"Getting community folders for device: {device_name}")
        device = self.devices.get(device_name)
        if device:
            return device.get("community_folders", [])
        return []

    def get_all_devices(self) -> List[Device]:
        """
        Get all devices with their MIDI ports and channels
        Returns a list of Device objects
        """
        logger.info(f"Getting all devices ({len(self.devices)} available)")
        result = []

        try:
            for name, data in self.devices.items():
                try:
                    device_info = data.get("device_info", {})
                    midi_ports = device_info.get("midi_ports", {})
                    midi_channels = device_info.get("midi_channels", {})

                    device = Device(
                        name=name,
                        manufacturer=data.get("manufacturer", ""),
                        midi_port=midi_ports,
                        midi_channel=midi_channels,
                        community_folders=data.get("community_folders", []),
                    )
                    result.append(device)
                    logger.debug(
                        f"Added device: {name}, manufacturer: {data.get('manufacturer', '')}, "
                        f"MIDI ports: {midi_ports}, MIDI channels: {midi_channels}, "
                        f"community folders: {data.get('community_folders', [])}"
                    )
                except Exception as e:
                    logger.error(f"Error creating Device object for {name}: {str(e)}")

            logger.info(f"Returning {len(result)} devices")
            return result
        except Exception as e:
            logger.error(f"Error getting all devices: {str(e)}")
            return result

    def clear_cache(self):
        """Clear the JSON cache to force reloading of all files"""
        self._json_cache = {}
        logger.info("JSON cache cleared")

    def _optimized_get_all_presets(
        self,
        device_name: Optional[str] = None,
        community_folder: Optional[str] = None,
        manufacturer: Optional[str] = None,
    ) -> List[Preset]:
        """
        Get all presets from all devices or a specific device with optimized JSON loading

        Args:
            device_name: Optional name of the device to get presets from
            community_folder: Optional name of the community folder to get presets from
            manufacturer: Optional name of the manufacturer to filter devices by

        Returns:
            A list of Preset objects
        """
        if manufacturer and device_name:
            logger.info(
                f"Getting presets for manufacturer: {manufacturer}, device: {device_name}"
            )
        elif manufacturer:
            logger.info(f"Getting presets for manufacturer: {manufacturer}")
        elif device_name:
            logger.info(f"Getting presets for device: {device_name}")
        else:
            logger.info("Getting all presets from all devices")

        result = []

        try:
            preset_count = 0

            # Filter devices by manufacturer and/or device_name
            devices_to_process = {}

            # If both manufacturer and device_name are provided
            if manufacturer and device_name:
                # Find the device with the matching name and manufacturer
                for name, data in self.devices.items():
                    if name == device_name and data.get("manufacturer") == manufacturer:
                        devices_to_process = {name: data}
                        break

                if not devices_to_process:
                    logger.warning(
                        f"Device not found: {device_name} for manufacturer: {manufacturer}"
                    )
                    return []

            # If only manufacturer is provided
            elif manufacturer:
                # Filter devices by manufacturer
                for name, data in self.devices.items():
                    if data.get("manufacturer") == manufacturer:
                        devices_to_process[name] = data

                if not devices_to_process:
                    logger.warning(f"No devices found for manufacturer: {manufacturer}")
                    return []

            # If only device_name is provided
            elif device_name:
                if device_name in self.devices:
                    devices_to_process = {device_name: self.devices[device_name]}
                else:
                    logger.warning(f"Device not found: {device_name}")
                    return []
            else:
                devices_to_process = self.devices

            for device_name, device_data in devices_to_process.items():
                logger.debug(f"Processing device: {device_name}")
                manufacturer = device_data.get("manufacturer", "")

                # Process default presets
                preset_collections = device_data.get("preset_collections", {})
                for collection_name, collection_data in preset_collections.items():
                    presets = collection_data.get("presets", [])
                    logger.debug(
                        f"Device {device_name} collection {collection_name} has {len(presets)} presets"
                    )

                    for preset in presets:
                        try:
                            preset_obj = Preset(
                                preset_name=preset.get("preset_name", ""),
                                category=preset.get("category", ""),
                                characters=preset.get("characters", []),
                                sendmidi_command=preset.get("sendmidi_command", ""),
                                cc_0=preset.get("cc_0"),
                                pgm=preset.get("pgm"),
                                source="default",
                            )
                            result.append(preset_obj)
                            preset_count += 1
                            logger.debug(
                                f"Added preset: {preset_obj.preset_name} ({preset_obj.category})"
                            )
                        except Exception as e:
                            preset_name = preset.get("preset_name", "unknown")
                            logger.error(
                                f"Error creating Preset object for {preset_name}: {str(e)}"
                            )

                # Process community presets if requested
                if community_folder:
                    logger.debug(
                        f"Processing community folder: {community_folder} for device: {device_name}"
                    )

                    # Construct path to community folder
                    community_path = os.path.join(
                        self.devices_folder,
                        manufacturer,
                        "community",
                        f"{community_folder}.json",
                    )

                    if os.path.exists(community_path):
                        try:
                            # Use cached JSON loading
                            community_data = self._load_json_file(community_path)

                            # Process presets from community folder
                            community_presets = community_data.get("presets", [])
                            logger.debug(
                                f"Community folder {community_folder} has {len(community_presets)} presets"
                            )

                            for preset in community_presets:
                                try:
                                    preset_obj = Preset(
                                        preset_name=preset.get("preset_name", ""),
                                        category=preset.get("category", ""),
                                        characters=preset.get("characters", []),
                                        sendmidi_command=preset.get(
                                            "sendmidi_command", ""
                                        ),
                                        cc_0=preset.get("cc_0"),
                                        pgm=preset.get("pgm"),
                                        source=community_folder,
                                    )
                                    result.append(preset_obj)
                                    preset_count += 1
                                    logger.debug(
                                        f"Added community preset: {preset_obj.preset_name} ({preset_obj.category})"
                                    )
                                except Exception as e:
                                    preset_name = preset.get("preset_name", "unknown")
                                    logger.error(
                                        f"Error creating Preset object for community preset {preset_name}: {str(e)}"
                                    )
                        except json.JSONDecodeError as e:
                            logger.error(
                                f"Invalid JSON in community file '{community_path}': {str(e)}"
                            )
                        except Exception as e:
                            logger.error(
                                f"Error loading community file '{community_path}': {str(e)}"
                            )
                    else:
                        logger.warning(f"Community folder not found: {community_path}")

            logger.info(f"Returning {preset_count} presets")
            return result
        except Exception as e:
            logger.error(f"Error getting presets: {str(e)}")
            return result

    def get_all_presets(
        self,
        device_name: Optional[str] = None,
        community_folder: Optional[str] = None,
        manufacturer: Optional[str] = None,
    ) -> List[Preset]:
        """
        Get all presets from all devices or a specific device

        Args:
            device_name: Optional name of the device to get presets from
            community_folder: Optional name of the community folder to get presets from
            manufacturer: Optional name of the manufacturer to filter devices by

        Returns:
            A list of Preset objects
        """
        # Use the optimized version of get_all_presets
        start_time = time.time()
        try:
            # Call the integrated optimized version with the necessary parameters
            result = self._optimized_get_all_presets(
                device_name=device_name,
                community_folder=community_folder,
                manufacturer=manufacturer,
            )

            # Log performance metrics
            load_time = time.time() - start_time
            logger.info(
                f"Returning {len(result)} presets (loaded in {load_time:.4f} seconds using optimized version)"
            )
            return result
        except Exception as e:
            load_time = time.time() - start_time
            logger.error(
                f"Error getting presets: {str(e)} (failed in {load_time:.4f} seconds)"
            )
            return []

    def get_preset_by_name(self, preset_name: str) -> Optional[Dict]:
        """Get preset data by preset name"""
        start_time = time.time()

        for device_name, device_data in self.devices.items():
            # Check in preset collections
            preset_collections = device_data.get("preset_collections", {})
            for collection_name, collection_data in preset_collections.items():
                presets = collection_data.get("presets", [])
                for preset in presets:
                    if preset.get("preset_name") == preset_name:
                        load_time = time.time() - start_time
                        logger.debug(
                            f"Found preset {preset_name} in device {device_name} collection {collection_name} in {load_time:.4f} seconds"
                        )
                        return preset

            # Check in community folders
            manufacturer = device_data.get("manufacturer", "")
            community_folders = device_data.get("community_folders", [])

            for folder in community_folders:
                community_path = os.path.join(
                    self.devices_folder, manufacturer, "community", f"{folder}.json"
                )

                if os.path.exists(community_path):
                    try:
                        # Use cached JSON loading for better performance
                        community_data = self._load_json_file(community_path)
                        community_presets = community_data.get("presets", [])

                        for preset in community_presets:
                            if preset.get("preset_name") == preset_name:
                                load_time = time.time() - start_time
                                logger.debug(
                                    f"Found preset {preset_name} in community folder {folder} in {load_time:.4f} seconds"
                                )
                                return preset
                    except Exception as e:
                        logger.error(
                            f"Error loading community file '{community_path}': {str(e)}"
                        )

        load_time = time.time() - start_time
        logger.debug(
            f"Preset {preset_name} not found (searched in {load_time:.4f} seconds)"
        )
        return None

    def check_directory_structure(
        self, manufacturer: str, device: str, create_if_missing: bool = True
    ) -> DirectoryStructureResponse:
        """
        Check if the manufacturer and device directories exist, and if the device JSON file exists.
        Optionally create them if they don't exist.

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            create_if_missing: Whether to create the directories and file if they don't exist

        Returns:
            DirectoryStructureResponse object with information about the directory structure
        """
        # Normalize names to avoid path issues
        manufacturer_safe = manufacturer.replace(" ", "_")
        device_safe = device.replace(" ", "_")

        # Construct paths
        manufacturer_path = os.path.join(self.devices_folder, manufacturer_safe)
        device_path = os.path.join(manufacturer_path, device_safe)
        json_path = os.path.join(
            device_path, f"{manufacturer_safe.lower()}_{device_safe.lower()}.json"
        )

        # Check if they exist
        manufacturer_exists = os.path.exists(manufacturer_path) and os.path.isdir(
            manufacturer_path
        )
        device_exists = os.path.exists(device_path) and os.path.isdir(device_path)
        json_exists = os.path.exists(json_path)

        response = DirectoryStructureResponse(
            manufacturer_exists=manufacturer_exists,
            device_exists=device_exists,
            json_exists=json_exists,
            json_path=json_path,
        )

        # Create if requested and missing
        if create_if_missing:
            # Create manufacturer directory if it doesn't exist
            if not manufacturer_exists:
                try:
                    os.makedirs(manufacturer_path, exist_ok=True)
                    response.created_manufacturer = True
                    manufacturer_exists = True
                    response.manufacturer_exists = True
                    logger.info(f"Created manufacturer directory: {manufacturer_path}")
                except Exception as e:
                    logger.error(
                        f"Error creating manufacturer directory {manufacturer_path}: {str(e)}"
                    )
                    return response

            # Create device directory if it doesn't exist
            if manufacturer_exists and not device_exists:
                try:
                    os.makedirs(device_path, exist_ok=True)
                    response.created_device = True
                    device_exists = True
                    response.device_exists = True
                    logger.info(f"Created device directory: {device_path}")
                except Exception as e:
                    logger.error(
                        f"Error creating device directory {device_path}: {str(e)}"
                    )
                    return response

            # Create JSON file if it doesn't exist
            if device_exists and not json_exists:
                try:
                    # Create a basic device JSON file
                    device_data = {
                        "_metadata": {
                            "schema_version": "1.0.0",
                            "file_revision": 1,
                            "created_by": "r2midi",
                            "modified_by": "r2midi",
                            "created_at": datetime.now().isoformat(),
                            "modified_at": datetime.now().isoformat(),
                            "migration_path": [],
                            "compatibility": {},
                        },
                        "device_info": {
                            "name": device,
                            "version": "1.0.0",
                            "manufacturer": manufacturer,
                            "manufacturer_id": 0,
                            "device_id": 0,
                            "ports": ["IN", "OUT"],
                            "midi_channels": {"IN": 1, "OUT": 1},
                            "midi_ports": {"IN": "", "OUT": ""},
                        },
                        "capabilities": {},
                        "preset_collections": {
                            "default": {
                                "metadata": {
                                    "name": "default",
                                    "version": "1.0",
                                    "revision": 1,
                                    "author": "r2midi",
                                    "description": "Default preset collection",
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
                        },
                    }

                    with open(json_path, "w") as f:
                        json.dump(device_data, f, indent=2)

                    response.created_json = True
                    response.json_exists = True
                    logger.info(f"Created device JSON file: {json_path}")
                except Exception as e:
                    logger.error(
                        f"Error creating device JSON file {json_path}: {str(e)}"
                    )
                    return response

        return response

    def create_manufacturer(self, name: str) -> Tuple[bool, str]:
        """
        Create a new manufacturer directory

        Args:
            name: Name of the manufacturer

        Returns:
            Tuple of (success, message)
        """
        # Validate and sanitize the manufacturer name
        if not validate_path_component(name):
            logger.warning(f"Unsafe manufacturer name: '{name}'")
            name_safe = sanitize_path_component(name)
            logger.info(f"Sanitized manufacturer name from '{name}' to '{name_safe}'")
        else:
            name_safe = name.replace(" ", "_")  # Still normalize spaces

        # Construct path safely
        manufacturer_path, is_safe, was_sanitized = safe_path_join(
            self.devices_folder, name_safe
        )

        if not is_safe:
            logger.error(f"Path traversal attempt detected for manufacturer: '{name}'")
            return False, "Invalid manufacturer name"

        # Check if it already exists
        if os.path.exists(manufacturer_path):
            return False, f"Manufacturer '{name}' already exists"

        # Create the directory
        try:
            os.makedirs(manufacturer_path, exist_ok=True)
            logger.info(f"Created manufacturer directory: {manufacturer_path}")

            # Rescan devices to include the new manufacturer
            self.scan_devices()

            return True, f"Manufacturer '{name}' created successfully"
        except Exception as e:
            logger.error(
                f"Error creating manufacturer directory {manufacturer_path}: {str(e)}"
            )
            return False, f"Error creating manufacturer: {str(e)}"

    def delete_manufacturer(self, name: str) -> Tuple[bool, str]:
        """
        Delete a manufacturer directory and all its contents

        Args:
            name: Name of the manufacturer

        Returns:
            Tuple of (success, message)
        """
        # Check if manufacturer exists
        if name not in self.manufacturers:
            return False, f"Manufacturer '{name}' does not exist"

        # Construct path safely
        manufacturer_path, is_safe, was_sanitized = safe_path_join(
            self.devices_folder, name
        )

        if not is_safe:
            logger.error(f"Path traversal attempt detected for manufacturer: '{name}'")
            return False, "Invalid manufacturer name"

        if was_sanitized:
            logger.warning(f"Manufacturer name was sanitized: '{name}'")

        # Check if it exists
        if not os.path.exists(manufacturer_path):
            return False, f"Manufacturer directory '{manufacturer_path}' does not exist"

        # Delete the directory
        try:
            shutil.rmtree(manufacturer_path)
            logger.info(f"Deleted manufacturer directory: {manufacturer_path}")

            # Rescan devices to update the list
            self.scan_devices()

            return True, f"Manufacturer '{name}' deleted successfully"
        except Exception as e:
            logger.error(
                f"Error deleting manufacturer directory {manufacturer_path}: {str(e)}"
            )
            return False, f"Error deleting manufacturer: {str(e)}"

    def create_device(
        self, device_data: Dict[str, Any]
    ) -> Tuple[bool, str, Optional[str]]:
        """
        Create a new device with the given data

        Args:
            device_data: Dictionary containing device data

        Returns:
            Tuple of (success, message, json_path)
        """
        manufacturer = device_data.get("manufacturer")
        name = device_data.get("name")

        if not manufacturer or not name:
            return False, "Manufacturer and name are required", None

        # Check if manufacturer exists
        if manufacturer not in self.manufacturers:
            # Create manufacturer if it doesn't exist
            success, message = self.create_manufacturer(manufacturer)
            if not success:
                return False, f"Error creating manufacturer: {message}", None

        # Check and create directory structure
        response = self.check_directory_structure(
            manufacturer, name, create_if_missing=True
        )

        if not response.manufacturer_exists or not response.device_exists:
            return False, "Failed to create directory structure", None

        # Create or update the device JSON file
        try:
            # Normalize names for file paths
            manufacturer_safe = manufacturer.replace(" ", "_")
            device_safe = name.replace(" ", "_")

            # Construct the JSON file path
            json_path = os.path.join(
                self.devices_folder,
                manufacturer_safe,
                device_safe,
                f"{manufacturer_safe.lower()}_{device_safe.lower()}.json",
            )

            # Create a basic device JSON file
            device_json = {
                "_metadata": {
                    "schema_version": "1.0.0",
                    "file_revision": 1,
                    "created_by": "r2midi",
                    "modified_by": "r2midi",
                    "created_at": datetime.now().isoformat(),
                    "modified_at": datetime.now().isoformat(),
                    "migration_path": [],
                    "compatibility": {},
                },
                "device_info": {
                    "name": name,
                    "version": device_data.get("version", "1.0.0"),
                    "manufacturer": manufacturer,
                    "manufacturer_id": device_data.get("manufacturer_id", 0),
                    "device_id": device_data.get("device_id", 0),
                    "ports": ["IN", "OUT"],
                    "midi_channels": device_data.get(
                        "midi_channels", {"IN": 1, "OUT": 1}
                    ),
                    "midi_ports": device_data.get("midi_ports", {"IN": "", "OUT": ""}),
                },
                "capabilities": {},
                "preset_collections": {
                    "default": {
                        "metadata": {
                            "name": "default",
                            "version": "1.0",
                            "revision": 1,
                            "author": "r2midi",
                            "description": "Default preset collection",
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
                },
            }

            with open(json_path, "w") as f:
                json.dump(device_json, f, indent=2)

            logger.info(f"Created device JSON file: {json_path}")

            # Rescan devices to include the new device
            self.scan_devices()

            return True, f"Device '{name}' created successfully", json_path
        except Exception as e:
            logger.error(f"Error creating device JSON file: {str(e)}")
            return False, f"Error creating device: {str(e)}", None

    def delete_device(self, manufacturer: str, device: str) -> Tuple[bool, str]:
        """
        Delete a device directory and all its contents

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device

        Returns:
            Tuple of (success, message)
        """
        # Check if manufacturer exists
        if manufacturer not in self.manufacturers:
            return False, f"Manufacturer '{manufacturer}' does not exist"

        # Check if device exists
        devices = self.get_devices_by_manufacturer(manufacturer)
        if device not in devices:
            return (
                False,
                f"Device '{device}' does not exist for manufacturer '{manufacturer}'",
            )

        # Construct path
        device_path = os.path.join(self.devices_folder, manufacturer, device)

        # Check if it exists
        if not os.path.exists(device_path):
            return False, f"Device directory '{device_path}' does not exist"

        # Delete the directory
        try:
            shutil.rmtree(device_path)
            logger.info(f"Deleted device directory: {device_path}")

            # Rescan devices to update the list
            self.scan_devices()

            return True, f"Device '{device}' deleted successfully"
        except Exception as e:
            logger.error(f"Error deleting device directory {device_path}: {str(e)}")
            return False, f"Error deleting device: {str(e)}"

    def create_preset(self, preset_data: Dict[str, Any]) -> Tuple[bool, str]:
        """
        Create a new preset in the specified collection

        Args:
            preset_data: Dictionary containing preset data

        Returns:
            Tuple of (success, message)
        """
        manufacturer = preset_data.get("manufacturer")
        device_name = preset_data.get("device")
        collection_name = preset_data.get("collection")
        preset_name = preset_data.get("preset_name")

        if (
            not manufacturer
            or not device_name
            or not collection_name
            or not preset_name
        ):
            return (
                False,
                "Manufacturer, device, collection, and preset_name are required",
            )

        # Check if manufacturer exists
        if manufacturer not in self.manufacturers:
            return False, f"Manufacturer '{manufacturer}' does not exist"

        # Check if device exists
        devices = self.get_devices_by_manufacturer(manufacturer)
        if device_name not in devices:
            return (
                False,
                f"Device '{device_name}' does not exist for manufacturer '{manufacturer}'",
            )

        # Get the device data
        device = self.get_device_by_name(device_name)
        if not device:
            return False, f"Device '{device_name}' not found"

        # Check if preset_collections exists, create it if it doesn't
        if "preset_collections" not in device:
            device["preset_collections"] = {}
            logger.info(f"Created preset_collections for device '{device_name}'")

        # Check if collection exists, create it if it doesn't
        preset_collections = device.get("preset_collections", {})
        if collection_name not in preset_collections:
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
                    "description": f"{collection_display_name} for {device_name}",
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
            logger.info(
                f"Created collection '{collection_name}' for device '{device_name}'"
            )

            # Update the device data
            device["preset_collections"] = preset_collections

        # Get the collection data
        collection = preset_collections[collection_name]
        presets = collection.get("presets", [])
        preset_metadata = collection.get("preset_metadata", {})

        # Check if preset already exists
        for preset in presets:
            if preset.get("preset_name") == preset_name:
                return (
                    False,
                    f"Preset '{preset_name}' already exists in collection '{collection_name}'",
                )

        # Create the preset
        try:
            # Generate a unique preset ID
            preset_id = f"{preset_name.lower().replace(' ', '_')}_{len(presets) + 1}"

            # Create the preset
            new_preset = {
                "preset_id": preset_id,
                "preset_name": preset_name,
                "category": preset_data.get("category", ""),
                "cc_0": preset_data.get("cc_0"),
                "pgm": preset_data.get("pgm", 0),
                "characters": preset_data.get("characters", []),
                "sendmidi_command": preset_data.get(
                    "sendmidi_command",
                    f"sendmidi dev \"{device_name}\" cc 0 {preset_data.get('cc_0', 0)} pc {preset_data.get('pgm', 0)}",
                ),
            }

            # Create the preset metadata
            new_preset_metadata = {
                "version": "1.0",
                "validation_status": "validated",
                "source": "user",
                "created_at": datetime.now().isoformat(),
                "modified_at": datetime.now().isoformat(),
            }

            # Add the preset to the collection
            presets.append(new_preset)
            preset_metadata[preset_id] = new_preset_metadata

            # Update the collection metadata
            collection["metadata"]["preset_count"] = len(presets)
            collection["metadata"]["modified_at"] = datetime.now().isoformat()

            # Update the device data
            device["preset_collections"][collection_name]["presets"] = presets
            device["preset_collections"][collection_name][
                "preset_metadata"
            ] = preset_metadata
            device["preset_collections"][collection_name]["metadata"] = collection[
                "metadata"
            ]

            # Save the device data
            device_path = os.path.join(self.devices_folder, manufacturer, device_name)
            json_files = [f for f in os.listdir(device_path) if f.endswith(".json")]

            if not json_files:
                return False, f"No JSON file found for device '{device_name}'"

            json_path = os.path.join(device_path, json_files[0])

            with open(json_path, "w") as f:
                json.dump(device, f, indent=2)

            logger.info(
                f"Created preset '{preset_name}' in collection '{collection_name}' for device '{device_name}'"
            )

            return True, f"Preset '{preset_name}' created successfully"
        except Exception as e:
            logger.error(f"Error creating preset: {str(e)}")
            return False, f"Error creating preset: {str(e)}"

    def update_preset(self, preset_data: Dict[str, Any]) -> Tuple[bool, str]:
        """
        Update an existing preset with new data

        Args:
            preset_data: Dictionary containing preset data

        Returns:
            Tuple of (success, message)
        """
        manufacturer = preset_data.get("manufacturer")
        device_name = preset_data.get("device")
        collection_name = preset_data.get("collection")
        preset_name = preset_data.get("preset_name")

        if (
            not manufacturer
            or not device_name
            or not collection_name
            or not preset_name
        ):
            return (
                False,
                "Manufacturer, device, collection, and preset_name are required",
            )

        # Check if manufacturer exists
        if manufacturer not in self.manufacturers:
            return False, f"Manufacturer '{manufacturer}' does not exist"

        # Check if device exists
        devices = self.get_devices_by_manufacturer(manufacturer)
        if device_name not in devices:
            return (
                False,
                f"Device '{device_name}' does not exist for manufacturer '{manufacturer}'",
            )

        # Get the device data
        device = self.get_device_by_name(device_name)
        if not device:
            return False, f"Device '{device_name}' not found"

        # Check if collection exists
        preset_collections = device.get("preset_collections", {})
        if collection_name not in preset_collections:
            return (
                False,
                f"Collection '{collection_name}' does not exist for device '{device_name}'",
            )

        # Get the collection data
        collection = preset_collections[collection_name]
        presets = collection.get("presets", [])
        preset_metadata = collection.get("preset_metadata", {})

        # Find the preset
        preset_index = None
        preset_id = None

        for i, preset in enumerate(presets):
            if preset.get("preset_name") == preset_name:
                preset_index = i
                preset_id = preset.get("preset_id")
                break

        if preset_index is None:
            return (
                False,
                f"Preset '{preset_name}' not found in collection '{collection_name}'",
            )

        # Update the preset
        try:
            # Create the updated preset
            updated_preset = {
                "preset_id": preset_id,
                "preset_name": preset_name,
                "category": preset_data.get("category", ""),
                "cc_0": preset_data.get("cc_0"),
                "pgm": preset_data.get("pgm", 0),
                "characters": preset_data.get("characters", []),
                "sendmidi_command": preset_data.get(
                    "sendmidi_command",
                    f"sendmidi dev \"{device_name}\" cc 0 {preset_data.get('cc_0', 0)} pc {preset_data.get('pgm', 0)}",
                ),
            }

            # Update the preset metadata
            if preset_id and preset_id in preset_metadata:
                preset_metadata[preset_id]["modified_at"] = datetime.now().isoformat()

            # Update the preset in the collection
            presets[preset_index] = updated_preset

            # Update the collection metadata
            collection["metadata"]["modified_at"] = datetime.now().isoformat()

            # Update the device data
            device["preset_collections"][collection_name]["presets"] = presets
            device["preset_collections"][collection_name][
                "preset_metadata"
            ] = preset_metadata
            device["preset_collections"][collection_name]["metadata"] = collection[
                "metadata"
            ]

            # Save the device data
            device_path = os.path.join(self.devices_folder, manufacturer, device_name)
            json_files = [f for f in os.listdir(device_path) if f.endswith(".json")]

            if not json_files:
                return False, f"No JSON file found for device '{device_name}'"

            json_path = os.path.join(device_path, json_files[0])

            with open(json_path, "w") as f:
                json.dump(device, f, indent=2)

            logger.info(
                f"Updated preset '{preset_name}' in collection '{collection_name}' for device '{device_name}'"
            )

            return True, f"Preset '{preset_name}' updated successfully"
        except Exception as e:
            logger.error(f"Error updating preset: {str(e)}")
            return False, f"Error updating preset: {str(e)}"

    def delete_preset(
        self,
        manufacturer: str,
        device_name: str,
        collection_name: str,
        preset_name: str,
    ) -> Tuple[bool, str]:
        """
        Delete a preset from the specified collection

        Args:
            manufacturer: Name of the manufacturer
            device_name: Name of the device
            collection_name: Name of the collection
            preset_name: Name of the preset

        Returns:
            Tuple of (success, message)
        """
        # Check if manufacturer exists
        if manufacturer not in self.manufacturers:
            return False, f"Manufacturer '{manufacturer}' does not exist"

        # Check if device exists
        devices = self.get_devices_by_manufacturer(manufacturer)
        if device_name not in devices:
            return (
                False,
                f"Device '{device_name}' does not exist for manufacturer '{manufacturer}'",
            )

        # Get the device data
        device = self.get_device_by_name(device_name)
        if not device:
            return False, f"Device '{device_name}' not found"

        # Check if collection exists
        preset_collections = device.get("preset_collections", {})
        if collection_name not in preset_collections:
            return (
                False,
                f"Collection '{collection_name}' does not exist for device '{device_name}'",
            )

        # Get the collection data
        collection = preset_collections[collection_name]
        presets = collection.get("presets", [])
        preset_metadata = collection.get("preset_metadata", {})

        # Find the preset
        preset_index = None
        preset_id = None

        for i, preset in enumerate(presets):
            if preset.get("preset_name") == preset_name:
                preset_index = i
                preset_id = preset.get("preset_id")
                break

        if preset_index is None:
            return (
                False,
                f"Preset '{preset_name}' not found in collection '{collection_name}'",
            )

        # Delete the preset
        try:
            # Remove the preset from the collection
            del presets[preset_index]

            # Remove the preset metadata if it exists
            if preset_id and preset_id in preset_metadata:
                del preset_metadata[preset_id]

            # Update the collection metadata
            collection["metadata"]["preset_count"] = len(presets)
            collection["metadata"]["modified_at"] = datetime.now().isoformat()

            # Update the device data
            device["preset_collections"][collection_name]["presets"] = presets
            device["preset_collections"][collection_name][
                "preset_metadata"
            ] = preset_metadata
            device["preset_collections"][collection_name]["metadata"] = collection[
                "metadata"
            ]

            # Save the device data
            device_path = os.path.join(self.devices_folder, manufacturer, device_name)
            json_files = [f for f in os.listdir(device_path) if f.endswith(".json")]

            if not json_files:
                return False, f"No JSON file found for device '{device_name}'"

            json_path = os.path.join(device_path, json_files[0])

            with open(json_path, "w") as f:
                json.dump(device, f, indent=2)

            logger.info(
                f"Deleted preset '{preset_name}' from collection '{collection_name}' for device '{device_name}'"
            )

            return True, f"Preset '{preset_name}' deleted successfully"
        except Exception as e:
            logger.error(f"Error deleting preset: {str(e)}")
            return False, f"Error deleting preset: {str(e)}"
