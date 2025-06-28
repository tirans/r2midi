import asyncio
import json
import logging
import subprocess
import time
from typing import Any, Dict, List, Optional, Tuple

import httpx

from .models import Device, Preset, UIState

# Configure logger
logger = logging.getLogger("r2midi_client.api_client")


class CachedApiClient:
    """Enhanced API client with caching and retry logic"""

    def __init__(
        self, base_url: str = "http://localhost:7777", cache_timeout: int = 300
    ):
        """
        Initialize the API client with caching

        Args:
            base_url: Base URL of the server API
            cache_timeout: Cache timeout in seconds (default: 5 minutes)
        """
        self.base_url = base_url
        self.client = httpx.AsyncClient(base_url=base_url, timeout=10.0)
        self.ui_state = UIState()
        self._cache = {}
        self._cache_timeout = cache_timeout

    def _is_cache_valid(self, cache_key: str) -> bool:
        """Check if cache entry is still valid"""
        if cache_key not in self._cache:
            return False
        timestamp, _ = self._cache[cache_key]
        return time.time() - timestamp < self._cache_timeout

    def _get_from_cache(self, cache_key: str) -> Optional[Any]:
        """Get data from cache if valid"""
        if self._is_cache_valid(cache_key):
            _, data = self._cache[cache_key]
            logger.debug(f"Cache hit for {cache_key}")
            return data
        logger.debug(f"Cache miss for {cache_key}")
        return None

    def _set_cache(self, cache_key: str, data: Any) -> None:
        """Set data in cache"""
        self._cache[cache_key] = (time.time(), data)
        logger.debug(f"Cached {cache_key}")

    def clear_cache(self) -> None:
        """Clear all cache entries"""
        self._cache.clear()
        logger.info("Cache cleared")

    def clear_cache_for_prefix(self, prefix: str) -> None:
        """Clear cache entries with given prefix"""
        keys_to_remove = [k for k in self._cache.keys() if k.startswith(prefix)]
        for key in keys_to_remove:
            del self._cache[key]
        logger.info(f"Cleared {len(keys_to_remove)} cache entries with prefix {prefix}")

    async def _retry_request(self, func, max_retries: int = 3, delay: float = 1.0):
        """Retry a request function with exponential backoff"""
        for attempt in range(max_retries):
            try:
                return await func()
            except httpx.HTTPError as e:
                # Don't retry on HTTP errors
                logger.error(f"HTTP error occurred: {str(e)}")
                raise
            except Exception as e:
                if attempt < max_retries - 1:
                    wait_time = delay * (2**attempt)  # Exponential backoff
                    logger.warning(
                        f"Request failed (attempt {attempt + 1}/{max_retries}), retrying in {wait_time}s: {str(e)}"
                    )
                    await asyncio.sleep(wait_time)
                else:
                    raise

    async def get_manufacturers(self, force_refresh: bool = False) -> List[str]:
        """
        Fetch manufacturers from server with caching

        Args:
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of manufacturer names
        """
        cache_key = "manufacturers"

        # Check cache first if not forcing refresh
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info("Fetching manufacturers from server...")

            async def fetch():
                response = await self.client.get("/manufacturers")
                response.raise_for_status()
                return response.json()

            manufacturers = await self._retry_request(fetch)
            logger.info(f"Fetched {len(manufacturers)} manufacturers: {manufacturers}")

            # Cache the result
            self._set_cache(cache_key, manufacturers)
            return manufacturers

        except httpx.HTTPError as e:
            logger.error(f"Error fetching manufacturers: {str(e)}")
            return []

    async def get_devices_by_manufacturer(
        self, manufacturer: str, force_refresh: bool = False
    ) -> List[str]:
        """
        Fetch devices for a specific manufacturer from server with caching

        Args:
            manufacturer: Name of the manufacturer
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of device names
        """
        cache_key = f"devices_by_manufacturer_{manufacturer}"

        # Check cache first if not forcing refresh
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info(
                f"Fetching devices for manufacturer {manufacturer} from server..."
            )

            async def fetch():
                response = await self.client.get(f"/devices/{manufacturer}")
                response.raise_for_status()
                return response.json()

            devices = await self._retry_request(fetch)
            logger.info(
                f"Fetched {len(devices)} devices for manufacturer {manufacturer}: {devices}"
            )

            # Cache the result
            self._set_cache(cache_key, devices)
            return devices

        except httpx.HTTPError as e:
            logger.error(
                f"Error fetching devices for manufacturer {manufacturer}: {str(e)}"
            )
            return []

    async def get_devices(
        self, manufacturer: str, force_refresh: bool = False
    ) -> List[str]:
        """
        Alias for get_devices_by_manufacturer for backward compatibility

        Args:
            manufacturer: Name of the manufacturer
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of device names
        """
        logger.info(f"Using get_devices alias for manufacturer {manufacturer}")
        return await self.get_devices_by_manufacturer(manufacturer, force_refresh)

    async def get_device_info(
        self, manufacturer: str, force_refresh: bool = False
    ) -> List[Dict]:
        """
        Fetch device info for a specific manufacturer from server with caching

        Args:
            manufacturer: Name of the manufacturer
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of dictionaries containing device_info
        """
        cache_key = f"device_info_{manufacturer}"

        # Check cache first if not forcing refresh
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info(
                f"Fetching device info for manufacturer {manufacturer} from server..."
            )

            async def fetch():
                response = await self.client.post(
                    "/device_info", json={"manufacturer": manufacturer}
                )
                response.raise_for_status()
                return response.json()

            device_info = await self._retry_request(fetch)
            logger.info(
                f"Fetched device info for {len(device_info)} devices for manufacturer {manufacturer}"
            )

            # Cache the result
            self._set_cache(cache_key, device_info)
            return device_info

        except httpx.HTTPError as e:
            logger.error(
                f"Error fetching device info for manufacturer {manufacturer}: {str(e)}"
            )
            return []

    async def get_community_folders(
        self, device_name: str, force_refresh: bool = False
    ) -> List[str]:
        """
        Fetch community folders for a specific device from server with caching

        Args:
            device_name: Name of the device
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of community folder names
        """
        cache_key = f"community_folders_{device_name}"

        # Check cache first if not forcing refresh
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info(
                f"Fetching community folders for device {device_name} from server..."
            )

            async def fetch():
                response = await self.client.get(f"/community_folders/{device_name}")
                response.raise_for_status()
                return response.json()

            folders = await self._retry_request(fetch)
            logger.info(
                f"Fetched {len(folders)} community folders for device {device_name}: {folders}"
            )

            # Cache the result
            self._set_cache(cache_key, folders)
            return folders

        except httpx.HTTPError as e:
            logger.error(
                f"Error fetching community folders for device {device_name}: {str(e)}"
            )
            return []

    async def get_presets(
        self,
        device_name: Optional[str] = None,
        community_folder: Optional[str] = None,
        manufacturer: Optional[str] = None,
        force_refresh: bool = False,
    ) -> List[Preset]:
        """
        Fetch presets from server with caching

        Args:
            device_name: Optional name of the device to get presets from
            community_folder: Optional name of the community folder to get presets from
            manufacturer: Optional name of the manufacturer to filter devices by
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of Preset objects
        """
        # Both manufacturer and device_name are required for the specific endpoint
        if not (manufacturer and device_name):
            logger.warning(
                f"Both manufacturer and device_name are required, got manufacturer={manufacturer}, device_name={device_name}"
            )
            return []

        # Create cache key based on parameters
        cache_key = (
            f"presets_{manufacturer}_{device_name}_{community_folder or 'default'}"
        )

        # Check cache first if not forcing refresh
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info(
                f"Fetching presets from server for {manufacturer}/{device_name} (folder: {community_folder})..."
            )

            # Use the specific endpoint with manufacturer and device_name
            url = f"/presets/{manufacturer}/{device_name}"
            params = {}
            if community_folder:
                params["community_folder"] = community_folder

            async def fetch():
                response = await self.client.get(url, params=params)
                response.raise_for_status()
                return response.json()

            presets_data = await self._retry_request(fetch)
            presets = [
                Preset(
                    preset_name=preset.get("preset_name", ""),
                    category=preset.get("category", ""),
                    characters=preset.get("characters"),
                    sendmidi_command=preset.get("sendmidi_command"),
                    cc_0=preset.get("cc_0"),
                    pgm=preset.get("pgm"),
                    source=preset.get("source"),
                )
                for preset in presets_data
            ]
            logger.info(f"Fetched {len(presets)} presets")

            # Cache the result
            self._set_cache(cache_key, presets)
            return presets

        except httpx.HTTPError as e:
            logger.error(f"Error fetching presets: {str(e)}")
            return []

    async def run_git_sync(self, sync_enabled: bool = True) -> Tuple[bool, str]:
        """
        Run git sync to update the midi-presets submodule by calling the server REST API

        Args:
            sync_enabled: Whether to perform the sync operation (default: True)

        Returns:
            Tuple of (success, message)
        """
        try:
            logger.info(
                f"Calling server REST API for git sync (sync_enabled={sync_enabled})..."
            )

            async def fetch():
                response = await self.client.get(
                    "/git/sync", params={"sync_enabled": sync_enabled}
                )
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(fetch)

            if result.get("status") == "success":
                logger.info("Git sync completed successfully via REST API")

                # Clear cache after sync as data might have changed
                self.clear_cache()

                return True, result.get("message", "Git sync completed successfully")
            else:
                error_msg = result.get("message", "Unknown error during git sync")
                logger.error(f"Git sync failed via REST API: {error_msg}")
                return False, error_msg
        except Exception as e:
            logger.error(f"Error calling git sync REST API: {str(e)}")
            return False, f"Error calling git sync REST API: {str(e)}"

    async def run_git_remote_sync(self) -> Tuple[bool, str]:
        """
        Add, commit, and push changes to the midi-presets repository by calling the server REST API

        This function calls the /git/remote_sync endpoint on the server, which:
        1. Determines the mode (submodule or clone) based on R2MIDI_ROLE
        2. Adds all changes with git add .
        3. Commits the changes with the message "new presets"
        4. Pushes the changes to the remote repository
        5. If in submodule mode, updates the submodule reference in the parent repository

        Returns:
            Tuple of (success, message)
        """
        try:
            logger.info("Calling server REST API for git remote sync...")

            async def fetch():
                response = await self.client.get("/git/remote_sync")
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(fetch)

            if result.get("status") == "success":
                logger.info("Git remote sync completed successfully via REST API")

                # Clear cache after sync as data might have changed
                self.clear_cache()

                return True, result.get(
                    "message", "Git remote sync completed successfully"
                )
            else:
                error_msg = result.get(
                    "message", "Unknown error during git remote sync"
                )
                logger.error(f"Git remote sync failed via REST API: {error_msg}")
                return False, error_msg
        except Exception as e:
            error_msg = f"Error calling git remote sync REST API: {str(e)}"
            logger.error(error_msg)
            return False, error_msg

    def save_ui_state(self, state: UIState) -> None:
        """
        Save the UI state

        Args:
            state: UI state to save
        """
        self.ui_state = state
        logger.info(f"Saved UI state: {state}")

        # Also persist to file for next session
        try:
            import os

            state_file = os.path.join(os.path.expanduser("~"), ".r2midi_ui_state.json")
            with open(state_file, "w") as f:
                json.dump(
                    {
                        "manufacturer": state.manufacturer,
                        "device": state.device,
                        "community_folder": state.community_folder,
                        "midi_in_port": state.midi_in_port,
                        "midi_out_port": state.midi_out_port,
                        "sequencer_port": state.sequencer_port,
                        "midi_channel": state.midi_channel,
                        "sync_enabled": state.sync_enabled,
                    },
                    f,
                )
            logger.debug(f"Persisted UI state to {state_file}")
        except Exception as e:
            logger.warning(f"Could not persist UI state: {str(e)}")

    def get_ui_state(self) -> UIState:
        """
        Get the saved UI state

        Returns:
            Saved UI state
        """
        # Try to load from file if not in memory
        if not any([self.ui_state.manufacturer, self.ui_state.device]):
            try:
                import os

                state_file = os.path.join(
                    os.path.expanduser("~"), ".r2midi_ui_state.json"
                )
                if os.path.exists(state_file):
                    with open(state_file, "r") as f:
                        data = json.load(f)
                        self.ui_state = UIState(**data)
                        logger.debug(f"Loaded UI state from {state_file}")
            except Exception as e:
                logger.warning(f"Could not load persisted UI state: {str(e)}")

        logger.info(f"Retrieved UI state: {self.ui_state}")
        return self.ui_state

    async def get_midi_ports(self, force_refresh: bool = False) -> Dict[str, List[str]]:
        """
        Fetch MIDI ports from server with caching

        Args:
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            Dictionary with 'in' and 'out' keys containing lists of port names
        """
        cache_key = "midi_ports"

        # Check cache first if not forcing refresh - MIDI ports don't change often
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info("Fetching MIDI ports from server...")

            async def fetch():
                response = await self.client.get("/midi_ports")
                response.raise_for_status()
                return response.json()

            ports = await self._retry_request(fetch)
            logger.info(
                f"Fetched MIDI ports: in={ports.get('in', [])}, out={ports.get('out', [])}"
            )

            # Cache the result
            self._set_cache(cache_key, ports)
            return ports

        except httpx.HTTPError as e:
            logger.error(f"Error fetching MIDI ports: {str(e)}")
            return {"in": [], "out": []}

    async def send_preset(
        self,
        preset_name: str,
        midi_port: str,
        midi_channel: int,
        sequencer_port: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Send preset selection to server

        Args:
            preset_name: Name of the preset to select
            midi_port: MIDI port to send the command to
            midi_channel: MIDI channel to use
            sequencer_port: Optional sequencer port to send the command to

        Returns:
            Response from the server
        """
        try:
            data = {
                "preset_name": preset_name,
                "midi_port": midi_port,
                "midi_channel": midi_channel,
            }

            if sequencer_port:
                data["sequencer_port"] = sequencer_port

            async def send():
                response = await self.client.post("/preset", json=data)
                response.raise_for_status()
                return response.json()

            return await self._retry_request(
                send, max_retries=2
            )  # Less retries for send operations

        except httpx.HTTPError as e:
            logger.error(f"Error sending preset: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def check_directory_structure(
        self, manufacturer: str, device: str, create_if_missing: bool = True
    ) -> Dict[str, Any]:
        """
        Check if the manufacturer and device directories exist, and if the device JSON file exists

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            create_if_missing: Whether to create the directories and file if they don't exist

        Returns:
            Dictionary with information about the directory structure
        """
        try:
            logger.info(f"Checking directory structure for {manufacturer}/{device}")

            async def check():
                response = await self.client.post(
                    "/directory_structure",
                    json={
                        "manufacturer": manufacturer,
                        "device": device,
                        "create_if_missing": create_if_missing,
                    },
                )
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(check)
            logger.info(f"Directory structure check result: {result}")
            return result
        except httpx.HTTPError as e:
            logger.error(f"Error checking directory structure: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {"error": error_data.get("detail", str(e))}
                except json.JSONDecodeError:
                    pass
            return {"error": str(e)}

    async def create_manufacturer(self, name: str) -> Dict[str, Any]:
        """
        Create a new manufacturer

        Args:
            name: Name of the manufacturer

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(f"Creating manufacturer: {name}")

            async def create():
                response = await self.client.post("/manufacturers", json={"name": name})
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(create)
            logger.info(f"Manufacturer creation result: {result}")

            # Clear cache for manufacturers
            self.clear_cache_for_prefix("manufacturers")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error creating manufacturer: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def delete_manufacturer(self, name: str) -> Dict[str, Any]:
        """
        Delete a manufacturer and all its devices

        Args:
            name: Name of the manufacturer

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(f"Deleting manufacturer: {name}")

            async def delete():
                response = await self.client.delete(f"/manufacturers/{name}")
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(delete)
            logger.info(f"Manufacturer deletion result: {result}")

            # Clear cache for manufacturers and devices
            self.clear_cache_for_prefix("manufacturers")
            self.clear_cache_for_prefix("devices_by_manufacturer")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error deleting manufacturer: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def create_device(self, device_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new device

        Args:
            device_data: Dictionary containing device data

        Returns:
            Dictionary with status, message, and json_path
        """
        try:
            logger.info(
                f"Creating device: {device_data.get('name')} for manufacturer {device_data.get('manufacturer')}"
            )

            async def create():
                response = await self.client.post("/devices", json=device_data)
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(create)
            logger.info(f"Device creation result: {result}")

            # Clear cache for devices
            manufacturer = device_data.get("manufacturer")
            if manufacturer:
                self.clear_cache_for_prefix(f"devices_by_manufacturer_{manufacturer}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error creating device: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def delete_device(
        self, manufacturer: str, device_name: str
    ) -> Dict[str, Any]:
        """
        Delete a device and all its presets

        Args:
            manufacturer: Name of the manufacturer
            device_name: Name of the device

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(
                f"Deleting device: {device_name} for manufacturer {manufacturer}"
            )

            async def delete():
                response = await self.client.delete(
                    f"/devices/{manufacturer}/{device_name}"
                )
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(delete)
            logger.info(f"Device deletion result: {result}")

            # Clear cache for devices and presets
            self.clear_cache_for_prefix(f"devices_by_manufacturer_{manufacturer}")
            self.clear_cache_for_prefix(f"presets_{manufacturer}_{device_name}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error deleting device: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def create_preset(self, preset_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new preset

        Args:
            preset_data: Dictionary containing preset data

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(
                f"Creating preset: {preset_data.get('preset_name')} for device {preset_data.get('device')}"
            )

            async def create():
                response = await self.client.post("/presets", json=preset_data)
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(create)
            logger.info(f"Preset creation result: {result}")

            # Clear cache for presets
            manufacturer = preset_data.get("manufacturer")
            device = preset_data.get("device")
            if manufacturer and device:
                self.clear_cache_for_prefix(f"presets_{manufacturer}_{device}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error creating preset: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def update_preset(self, preset_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update an existing preset

        Args:
            preset_data: Dictionary containing preset data

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(
                f"Updating preset: {preset_data.get('preset_name')} for device {preset_data.get('device')}"
            )

            async def update():
                response = await self.client.put("/presets", json=preset_data)
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(update)
            logger.info(f"Preset update result: {result}")

            # Clear cache for presets
            manufacturer = preset_data.get("manufacturer")
            device = preset_data.get("device")
            if manufacturer and device:
                self.clear_cache_for_prefix(f"presets_{manufacturer}_{device}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error updating preset: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def delete_preset(
        self, manufacturer: str, device: str, collection: str, preset_name: str
    ) -> Dict[str, Any]:
        """
        Delete a preset

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            collection: Name of the collection
            preset_name: Name of the preset

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(
                f"Deleting preset: {preset_name} from collection {collection} for device {device}"
            )

            async def delete():
                response = await self.client.delete(
                    f"/presets/{manufacturer}/{device}/{collection}/{preset_name}"
                )
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(delete)
            logger.info(f"Preset deletion result: {result}")

            # Clear cache for presets
            self.clear_cache_for_prefix(f"presets_{manufacturer}_{device}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error deleting preset: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def get_collections(
        self, manufacturer: str, device: str, force_refresh: bool = False
    ) -> List[str]:
        """
        Fetch collections for a device from server with caching

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            force_refresh: If True, bypass cache and fetch fresh data from server

        Returns:
            List of collection names
        """
        # Create cache key based on parameters
        cache_key = f"collections_{manufacturer}_{device}"

        # Check cache first if not forcing refresh
        if not force_refresh:
            cached_data = self._get_from_cache(cache_key)
            if cached_data is not None:
                return cached_data

        try:
            logger.info(
                f"Fetching collections from server for {manufacturer}/{device}..."
            )

            # Use the specific endpoint with manufacturer and device
            url = f"/collections/{manufacturer}/{device}"

            async def fetch():
                response = await self.client.get(url)
                response.raise_for_status()
                return response.json()

            collections_data = await self._retry_request(fetch)
            logger.info(f"Fetched {len(collections_data)} collections")

            # Cache the result
            self._set_cache(cache_key, collections_data)
            return collections_data

        except httpx.HTTPError as e:
            logger.error(f"Error fetching collections: {str(e)}")
            return ["default"]  # Return default collection on error

    async def create_collection(
        self, manufacturer: str, device: str, collection_name: str
    ) -> Dict[str, Any]:
        """
        Create a new collection

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            collection_name: Name of the collection to create

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(f"Creating collection: {collection_name} for device {device}")

            # Use the specific endpoint with manufacturer and device
            url = f"/collections/{manufacturer}/{device}/{collection_name}"

            async def create():
                response = await self.client.post(url)
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(create)
            logger.info(f"Collection creation result: {result}")

            # Clear cache for collections
            self.clear_cache_for_prefix(f"collections_{manufacturer}_{device}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error creating collection: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def update_collection(
        self, manufacturer: str, device: str, old_name: str, new_name: str
    ) -> Dict[str, Any]:
        """
        Rename a collection

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            old_name: Current name of the collection
            new_name: New name for the collection

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(
                f"Renaming collection: {old_name} to {new_name} for device {device}"
            )

            # Use the specific endpoint with manufacturer and device
            url = f"/collections/{manufacturer}/{device}/{old_name}"
            data = {"new_name": new_name}

            async def update():
                response = await self.client.put(url, json=data)
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(update)
            logger.info(f"Collection update result: {result}")

            # Clear cache for collections
            self.clear_cache_for_prefix(f"collections_{manufacturer}_{device}")
            # Also clear cache for presets as they might be affected
            self.clear_cache_for_prefix(f"presets_{manufacturer}_{device}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error updating collection: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def delete_collection(
        self, manufacturer: str, device: str, collection_name: str
    ) -> Dict[str, Any]:
        """
        Delete a collection

        Args:
            manufacturer: Name of the manufacturer
            device: Name of the device
            collection_name: Name of the collection to delete

        Returns:
            Dictionary with status and message
        """
        try:
            logger.info(f"Deleting collection: {collection_name} for device {device}")

            # Use the specific endpoint with manufacturer and device
            url = f"/collections/{manufacturer}/{device}/{collection_name}"

            async def delete():
                response = await self.client.delete(url)
                response.raise_for_status()
                return response.json()

            result = await self._retry_request(delete)
            logger.info(f"Collection deletion result: {result}")

            # Clear cache for collections
            self.clear_cache_for_prefix(f"collections_{manufacturer}_{device}")
            # Also clear cache for presets as they might be affected
            self.clear_cache_for_prefix(f"presets_{manufacturer}_{device}")

            return result
        except httpx.HTTPError as e:
            logger.error(f"Error deleting collection: {str(e)}")
            if hasattr(e, "response") and e.response is not None:
                try:
                    error_data = e.response.json()
                    return {
                        "status": "error",
                        "message": error_data.get("detail", str(e)),
                    }
                except json.JSONDecodeError:
                    pass
            return {"status": "error", "message": str(e)}

    async def close(self):
        """Close the HTTP client"""
        await self.client.aclose()
