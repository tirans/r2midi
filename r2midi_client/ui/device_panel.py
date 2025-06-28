import asyncio
import json
import logging
import os
from typing import Any, Callable, Coroutine, Dict, List, Optional

from PyQt6.QtCore import QTimer, pyqtSignal
from PyQt6.QtWidgets import (QCheckBox, QComboBox, QFormLayout, QGroupBox,
                             QHBoxLayout, QLabel, QMessageBox, QSpinBox,
                             QVBoxLayout, QWidget)

from ..models import Device, UIState

# Configure logger
logger = logging.getLogger("r2midi_client.ui.device_panel")


class DebouncedComboBox(QComboBox):
    """ComboBox with debounced signal emission to prevent rapid API calls"""

    # Custom signal that emits after debounce delay
    debouncedTextChanged = pyqtSignal(str)

    def __init__(self, delay_ms: int = 300, parent=None):
        super().__init__(parent)
        self.delay_ms = delay_ms
        self.timer = QTimer()
        self.timer.setSingleShot(True)
        self.timer.timeout.connect(self._emit_delayed)
        self.pending_text = None

        # Connect to the regular signal
        self.currentTextChanged.connect(self._on_text_changed)

    def _on_text_changed(self, text: str):
        """Handle text change with debouncing"""
        self.pending_text = text
        self.timer.stop()
        self.timer.start(self.delay_ms)

    def _emit_delayed(self):
        """Emit the debounced signal"""
        if self.pending_text is not None:
            self.debouncedTextChanged.emit(self.pending_text)


class DevicePanel(QWidget):
    """Enhanced panel for device and MIDI port selection with debouncing"""

    # Signals emitted when selections change
    manufacturer_changed = pyqtSignal(str)
    device_changed = pyqtSignal(str)
    community_folder_changed = pyqtSignal(str)
    midi_in_port_changed = pyqtSignal(str)
    midi_out_port_changed = pyqtSignal(str)
    sequencer_port_changed = pyqtSignal(str)
    midi_channel_changed = pyqtSignal(int)
    sync_changed = pyqtSignal(bool)

    def __init__(self, api_client=None, main_window=None):
        super().__init__()
        self.api_client = api_client
        self.main_window = main_window
        self.devices = []
        self.manufacturers = []
        self.community_folders = []
        self.midi_ports = {"in": [], "out": []}
        self.current_manufacturer = None
        self.current_device = None
        self.current_community_folder = None
        self._event_loop = None
        self._updating_programmatically = False
        self.initUI()

        # UI state will be loaded after MIDI ports are fetched
        # This is now handled by the MainWindow after loading data

    def run_async(
        self,
        coro: Coroutine,
        callback=None,
        error_callback=None,
        loading_message="Loading data...",
    ) -> None:
        """
        Safely run an async coroutine

        Args:
            coro: The coroutine to run
            callback: Optional callback to run with the result
            error_callback: Optional callback to run on error
            loading_message: Optional message to display in the loading indicator
        """
        # If we have a reference to the main window, use its run_async_task method
        if self.main_window and hasattr(self.main_window, "run_async_task"):
            self.main_window.run_async_task(
                coro, callback, error_callback, loading_message
            )
            return

        # Otherwise, log an error - we need the main window for async operations
        logger.error("Cannot run async operation without main window reference")

    def initUI(self):
        """Initialize the UI components"""
        # Main layout
        main_layout = QVBoxLayout()
        self.setLayout(main_layout)

        # Device selection
        device_box = QGroupBox("Device Selection")
        device_layout = QFormLayout()
        device_box.setLayout(device_layout)

        # Manufacturer dropdown with debouncing
        self.manufacturer_combo = DebouncedComboBox(delay_ms=300)
        self.manufacturer_combo.debouncedTextChanged.connect(
            self.on_manufacturer_changed
        )
        self.manufacturer_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        self.manufacturer_combo.setMinimumWidth(200)
        device_layout.addRow("Manufacturer:", self.manufacturer_combo)

        # Device dropdown with debouncing
        self.device_combo = DebouncedComboBox(delay_ms=300)
        self.device_combo.debouncedTextChanged.connect(self.on_device_changed)
        self.device_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        self.device_combo.setMinimumWidth(200)
        device_layout.addRow("Device:", self.device_combo)

        # Community folder dropdown with debouncing
        self.community_combo = DebouncedComboBox(delay_ms=300)
        self.community_combo.addItem("Default", None)
        self.community_combo.debouncedTextChanged.connect(
            self.on_community_folder_changed
        )
        self.community_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        self.community_combo.setMinimumWidth(200)
        device_layout.addRow("Community Folder:", self.community_combo)

        # Off-line mode checkbox
        self.sync_checkbox = QCheckBox("Off-line mode")
        self.sync_checkbox.setChecked(False)
        self.sync_checkbox.stateChanged.connect(self.on_sync_changed)
        self.sync_checkbox.setToolTip(
            "Enable to work without syncing to the remote repository"
        )
        device_layout.addRow("", self.sync_checkbox)

        main_layout.addWidget(device_box)

        # MIDI port selection
        port_box = QGroupBox("MIDI Port Configuration")
        port_layout = QFormLayout()
        port_box.setLayout(port_layout)

        self.midi_in_combo = DebouncedComboBox(delay_ms=200)
        self.midi_in_combo.debouncedTextChanged.connect(self.on_midi_in_port_changed)
        self.midi_in_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        self.midi_in_combo.setMinimumWidth(200)
        port_layout.addRow("MIDI In Port:", self.midi_in_combo)

        self.midi_out_combo = DebouncedComboBox(delay_ms=200)
        self.midi_out_combo.debouncedTextChanged.connect(self.on_midi_out_port_changed)
        self.midi_out_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        self.midi_out_combo.setMinimumWidth(200)
        port_layout.addRow("MIDI Out Port:", self.midi_out_combo)

        self.sequencer_combo = DebouncedComboBox(delay_ms=200)
        self.sequencer_combo.addItem("None", None)
        self.sequencer_combo.debouncedTextChanged.connect(
            self.on_sequencer_port_changed
        )
        self.sequencer_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        self.sequencer_combo.setMinimumWidth(200)
        port_layout.addRow("Sequencer Port:", self.sequencer_combo)

        self.channel_spin = QSpinBox()
        self.channel_spin.setMinimum(1)
        self.channel_spin.setMaximum(16)
        self.channel_spin.setValue(1)
        self.channel_spin.valueChanged.connect(self.on_midi_channel_changed)
        port_layout.addRow("MIDI Channel:", self.channel_spin)

        main_layout.addWidget(port_box)

    def set_manufacturers(self, manufacturers: List[str]):
        """Set the available manufacturers"""
        logger.info(f"Setting manufacturers: {manufacturers}")
        self.manufacturers = manufacturers

        # Set flag to prevent triggering signals
        self._updating_programmatically = True

        try:
            # Update manufacturer combo box
            self.manufacturer_combo.clear()
            logger.info(
                f"Cleared manufacturer combo box, adding {len(manufacturers)} manufacturers"
            )

            for manufacturer in manufacturers:
                logger.info(f"Adding manufacturer to combo box: {manufacturer}")
                self.manufacturer_combo.addItem(manufacturer)

            # Select first manufacturer if available
            if manufacturers:
                if (
                    not self.current_manufacturer
                    or self.current_manufacturer not in manufacturers
                ):
                    self.current_manufacturer = manufacturers[0]
                    logger.info(
                        f"Selected first manufacturer: {self.current_manufacturer}"
                    )
                else:
                    logger.info(
                        f"Keeping current manufacturer: {self.current_manufacturer}"
                    )

                # Set the current manufacturer in the dropdown
                index = self.manufacturer_combo.findText(self.current_manufacturer)
                if index >= 0:
                    logger.info(
                        f"Setting manufacturer dropdown to index {index}: {self.current_manufacturer}"
                    )
                    self.manufacturer_combo.setCurrentIndex(index)
                else:
                    logger.warning(
                        f"Manufacturer {self.current_manufacturer} not found in dropdown, selecting first manufacturer"
                    )
                    self.current_manufacturer = manufacturers[0]
                    self.manufacturer_combo.setCurrentIndex(0)

                logger.info(
                    f"Final manufacturer combo state: count={self.manufacturer_combo.count()}, current={self.manufacturer_combo.currentText()}"
                )
            else:
                logger.warning("No manufacturers available")
                # Reset current manufacturer to avoid referencing a deleted manufacturer
                self.current_manufacturer = None
                # Clear device combo box as well since there are no manufacturers
                self.device_combo.clear()
                self.current_device = None

        finally:
            self._updating_programmatically = False

    def update_devices_by_manufacturer(self, devices: List[str]):
        """Update the device dropdown based on the selected manufacturer"""
        logger.info(
            f"Updating devices for manufacturer {self.current_manufacturer}: {devices}"
        )

        # Set flag to prevent triggering signals
        self._updating_programmatically = True

        try:
            # Update device combo box
            self.device_combo.clear()
            logger.info(f"Cleared device combo box, adding {len(devices)} devices")

            for device in devices:
                logger.info(f"Adding device to combo box: {device}")
                self.device_combo.addItem(device)

            # Select device if available
            if devices:
                # If we don't have a current device or it's not in the list, select the first one
                if (
                    not self.current_device
                    or (
                        isinstance(self.current_device, str)
                        and self.current_device not in devices
                    )
                    or (
                        hasattr(self.current_device, "name")
                        and self.current_device.name not in devices
                    )
                ):
                    self.current_device = devices[0]
                    logger.info(f"Selected first device: {self.current_device}")
                else:
                    # If we have a current device, keep it if it's in the list
                    if isinstance(self.current_device, str):
                        if self.current_device in devices:
                            logger.info(
                                f"Keeping current device (string): {self.current_device}"
                            )
                        else:
                            self.current_device = devices[0]
                            logger.info(
                                f"Current device not in list, selected first device: {self.current_device}"
                            )
                    elif hasattr(self.current_device, "name"):
                        if self.current_device.name in devices:
                            logger.info(
                                f"Keeping current device (object): {self.current_device.name}"
                            )
                        else:
                            self.current_device = devices[0]
                            logger.info(
                                f"Current device not in list, selected first device: {self.current_device}"
                            )
                    else:
                        self.current_device = devices[0]
                        logger.info(
                            f"Current device type unknown, selected first device: {self.current_device}"
                        )

                # Set the current device in the dropdown
                if isinstance(self.current_device, str):
                    device_name = self.current_device
                elif hasattr(self.current_device, "name"):
                    device_name = self.current_device.name
                else:
                    device_name = str(self.current_device)

                index = self.device_combo.findText(device_name)
                if index >= 0:
                    logger.info(
                        f"Setting device dropdown to index {index}: {device_name}"
                    )
                    self.device_combo.setCurrentIndex(index)
                else:
                    logger.warning(
                        f"Device {device_name} not found in dropdown, selecting first device"
                    )
                    if devices:
                        self.current_device = devices[0]
                        self.device_combo.setCurrentIndex(0)

                logger.info(
                    f"Final device combo state: count={self.device_combo.count()}, current={self.device_combo.currentText()}"
                )
            else:
                logger.warning(
                    f"No devices available for manufacturer {self.current_manufacturer}"
                )
                # Reset current device to avoid referencing a deleted device
                self.current_device = None
                # Clear community folder combo box as well since there are no devices
                self.community_folder_combo.clear()
                self.current_community_folder = None
        finally:
            self._updating_programmatically = False

    def update_community_folders(self, folders: List[str]):
        """Update the community folder dropdown based on the selected device"""
        try:
            if isinstance(self.current_device, str):
                device_name = self.current_device
            elif hasattr(self.current_device, "name"):
                device_name = self.current_device.name
            else:
                device_name = str(self.current_device)

            logger.info(
                f"Updating community folders for device {device_name}: {folders}"
            )

            # Set flag to prevent triggering signals
            self._updating_programmatically = True

            try:
                # Update community folder combo box
                self.community_combo.clear()
                self.community_combo.addItem("Default", None)

                for folder in folders:
                    logger.info(f"Adding community folder to combo box: {folder}")
                    self.community_combo.addItem(folder, folder)

                # Select community folder
                if not self.current_community_folder:
                    logger.info("No current community folder, selecting Default")
                    self.community_combo.setCurrentIndex(0)
                else:
                    # Try to select the previously selected folder
                    index = self.community_combo.findText(self.current_community_folder)
                    if index >= 0:
                        logger.info(
                            f"Setting community folder dropdown to index {index}: {self.current_community_folder}"
                        )
                        self.community_combo.setCurrentIndex(index)
                    else:
                        logger.warning(
                            f"Community folder {self.current_community_folder} not found in dropdown, selecting Default"
                        )
                        self.current_community_folder = None
                        self.community_combo.setCurrentIndex(0)

                # Ensure the dropdown is visible and enabled
                self.community_combo.setVisible(True)
                self.community_combo.setEnabled(True)

                logger.info(
                    f"Final community combo state: count={self.community_combo.count()}, current={self.community_combo.currentText()}"
                )
            except Exception as e:
                logger.error(f"Error updating community folder combo box: {str(e)}")
            finally:
                self._updating_programmatically = False
        except Exception as e:
            logger.error(f"Error in update_community_folders: {str(e)}")
            # Continue execution to prevent UI crash

    def set_devices(self, devices: List[Device]):
        """Set the available devices"""
        logger.info(f"Setting devices: {[d.name for d in devices]}")
        self.devices = devices

        # Extract manufacturers from devices
        manufacturers = sorted(
            set(device.manufacturer for device in devices if device.manufacturer)
        )
        self.set_manufacturers(manufacturers)

        # The rest will be handled by on_manufacturer_changed and on_device_changed

    def set_devices_without_manufacturers(self, devices: List[Device]):
        """Set the available devices without updating manufacturers"""
        logger.info(
            f"Setting devices without updating manufacturers: {[d.name for d in devices]}"
        )
        self.devices = devices

        # If a manufacturer is already selected, update the device dropdown
        if self.current_manufacturer:
            logger.info(
                f"Manufacturer already selected: {self.current_manufacturer}, updating devices"
            )
            # Get devices for this manufacturer
            devices_for_manufacturer = [
                d.name for d in devices if d.manufacturer == self.current_manufacturer
            ]
            self.update_devices_by_manufacturer(devices_for_manufacturer)
        # Otherwise, if there are manufacturers in the dropdown, select the first one
        elif self.manufacturer_combo.count() > 0:
            logger.info("No manufacturer selected, selecting the first one")
            self.manufacturer_combo.setCurrentIndex(0)
            # on_manufacturer_changed will be called automatically
        # If no manufacturer is selected and no manufacturers in dropdown,
        # but we have devices, show all devices
        elif devices:
            logger.info(
                "No manufacturer selected and no manufacturers in dropdown, showing all devices"
            )
            all_device_names = [d.name for d in devices]
            self.update_devices_by_manufacturer(all_device_names)

        # The rest will be handled by on_manufacturer_changed and on_device_changed

    def set_midi_ports(self, ports: Dict[str, List[str]]):
        """Set the available MIDI ports"""
        logger.info(
            f"Setting MIDI ports: in={ports.get('in', [])}, out={ports.get('out', [])}"
        )
        self.midi_ports = ports

        # Set flag to prevent triggering signals
        self._updating_programmatically = True

        try:
            # Update MIDI in port combo box
            self.midi_in_combo.clear()
            for port in ports.get("in", []):
                logger.info(f"Adding MIDI in port to combo box: {port}")
                self.midi_in_combo.addItem(port)

            # Update MIDI out port combo box
            self.midi_out_combo.clear()
            for port in ports.get("out", []):
                logger.info(f"Adding MIDI out port to combo box: {port}")
                self.midi_out_combo.addItem(port)

            # Update sequencer port combo box (use out ports)
            self.sequencer_combo.clear()
            self.sequencer_combo.addItem("None", None)
            for port in ports.get("out", []):
                logger.info(f"Adding sequencer port to combo box: {port}")
                self.sequencer_combo.addItem(port)

            logger.info(
                f"MIDI ports set successfully: in={self.midi_in_combo.count()}, out={self.midi_out_combo.count()}, sequencer={self.sequencer_combo.count()}"
            )
        finally:
            self._updating_programmatically = False

        # Force UI update to ensure MIDI ports are displayed
        self.midi_in_combo.update()
        self.midi_out_combo.update()
        self.sequencer_combo.update()

        # Now that MIDI ports are loaded, update the ports based on the selected device
        if self.current_device:
            logger.info(
                f"Updating MIDI ports from device: {self.current_device.name if hasattr(self.current_device, 'name') else self.current_device}"
            )
            self.update_midi_ports_from_device()

    def update_midi_channels(self):
        """Update MIDI channel based on selected device"""
        try:
            # Check if current_device is a string, which would indicate an error
            if isinstance(self.current_device, str):
                logger.warning(
                    f"Current device is a string ({self.current_device}), not a Device object. Cannot update MIDI channels."
                )
                return

            # Check if current_device is a Device object
            if (
                self.current_device
                and hasattr(self.current_device, "midi_channel")
                and self.current_device.midi_channel
            ):
                # Use the OUT channel if available
                channel = self.current_device.midi_channel.get("OUT", 1)
                self.channel_spin.setValue(channel)
        except Exception as e:
            logger.error(f"Error in update_midi_channels: {str(e)}")
            # Continue execution to prevent UI crash

    def update_midi_ports_from_device(self):
        """Update MIDI ports based on selected device"""
        try:
            if not self.current_device:
                logger.info("No current device selected, cannot update MIDI ports")
                return

            # Check if current_device is a string, which would indicate an error
            if isinstance(self.current_device, str):
                logger.warning(
                    f"Current device is a string ({self.current_device}), not a Device object. Cannot update MIDI ports."
                )
                return

            if (
                not hasattr(self.current_device, "midi_port")
                or not self.current_device.midi_port
            ):
                logger.info(
                    f"Device {self.current_device.name if hasattr(self.current_device, 'name') else self.current_device} has no MIDI ports defined"
                )
                return

            device_name = (
                self.current_device.name
                if hasattr(self.current_device, "name")
                else str(self.current_device)
            )
            logger.info(
                f"Updating MIDI ports from device: {device_name}, ports: {self.current_device.midi_port}"
            )

            # Set MIDI in port if available
            try:
                in_port = self.current_device.midi_port.get("IN")
                if in_port and self.midi_in_combo.count() > 0:
                    logger.info(f"Setting MIDI in port to: {in_port}")
                    index = self.midi_in_combo.findText(in_port)
                    if index >= 0:
                        logger.info(f"Found MIDI in port at index {index}")
                        self.midi_in_combo.setCurrentIndex(index)
                    else:
                        logger.info(f"MIDI in port {in_port} not found in combo box")
            except Exception as e:
                logger.error(f"Error setting MIDI in port: {str(e)}")

            # Set MIDI out port if available
            try:
                out_port = self.current_device.midi_port.get("OUT")
                if out_port and self.midi_out_combo.count() > 0:
                    logger.info(f"Setting MIDI out port to: {out_port}")
                    index = self.midi_out_combo.findText(out_port)
                    if index >= 0:
                        logger.info(f"Found MIDI out port at index {index}")
                        self.midi_out_combo.setCurrentIndex(index)
                    else:
                        logger.info(f"MIDI out port {out_port} not found in combo box")
            except Exception as e:
                logger.error(f"Error setting MIDI out port: {str(e)}")

            # Set sequencer port if available (use OUT port by default)
            try:
                out_port = self.current_device.midi_port.get("OUT")
                sequencer_port = self.current_device.midi_port.get(
                    "SEQUENCER", out_port
                )
                if sequencer_port and self.sequencer_combo.count() > 0:
                    logger.info(f"Setting sequencer port to: {sequencer_port}")
                    index = self.sequencer_combo.findText(sequencer_port)
                    if index >= 0:
                        logger.info(f"Found sequencer port at index {index}")
                        self.sequencer_combo.setCurrentIndex(index)
                    else:
                        logger.info(
                            f"Sequencer port {sequencer_port} not found in combo box"
                        )
            except Exception as e:
                logger.error(f"Error setting sequencer port: {str(e)}")
        except Exception as e:
            logger.error(f"Error in update_midi_ports_from_device: {str(e)}")
            # Continue execution to prevent UI crash

    def get_selected_manufacturer(self) -> Optional[str]:
        """Get the name of the selected manufacturer"""
        return (
            self.manufacturer_combo.currentText()
            if self.manufacturer_combo.count() > 0
            else None
        )

    def get_selected_device(self) -> Optional[str]:
        """Get the name of the selected device"""
        return (
            self.device_combo.currentText() if self.device_combo.count() > 0 else None
        )

    def get_selected_community_folder(self) -> Optional[str]:
        """Get the name of the selected community folder"""
        text = self.community_combo.currentText()
        return None if text == "Default" else text

    def get_selected_midi_in_port(self) -> Optional[str]:
        """Get the selected MIDI in port"""
        return (
            self.midi_in_combo.currentText() if self.midi_in_combo.count() > 0 else None
        )

    def get_selected_midi_out_port(self) -> Optional[str]:
        """Get the selected MIDI out port"""
        return (
            self.midi_out_combo.currentText()
            if self.midi_out_combo.count() > 0
            else None
        )

    def get_selected_sequencer_port(self) -> Optional[str]:
        """Get the selected sequencer port"""
        text = self.sequencer_combo.currentText()
        return None if text == "None" else text

    def get_selected_midi_channel(self) -> int:
        """Get the selected MIDI channel"""
        return self.channel_spin.value()

    def is_sync_enabled(self) -> bool:
        """Check if sync is enabled"""
        return self.sync_checkbox.isChecked()

    def load_ui_state(self):
        """Load UI state from the API client"""
        if not self.api_client:
            return

        try:
            state = self.api_client.get_ui_state()
            logger.info(f"Loading UI state: {state}")

            self._updating_programmatically = True

            # Set manufacturer if available
            if state.manufacturer and self.manufacturer_combo.count() > 0:
                index = self.manufacturer_combo.findText(state.manufacturer)
                if index >= 0:
                    self.manufacturer_combo.setCurrentIndex(index)
                    self.current_manufacturer = state.manufacturer

            # Set device if available
            if state.device and self.device_combo.count() > 0:
                index = self.device_combo.findText(state.device)
                if index >= 0:
                    self.device_combo.setCurrentIndex(index)

                    # Try to find the Device object instead of just the name
                    device_found = False
                    for device in self.devices:
                        if device.name == state.device:
                            self.current_device = device
                            device_found = True
                            logger.info(f"Found Device object for {state.device}")
                            break

                    # If not found, just use the name
                    if not device_found:
                        self.current_device = state.device
                        logger.info(
                            f"Using device name {state.device} (Device object not found)"
                        )

            # Set community folder if available
            if state.community_folder and self.community_combo.count() > 0:
                index = self.community_combo.findText(state.community_folder)
                if index >= 0:
                    self.community_combo.setCurrentIndex(index)
                    self.current_community_folder = state.community_folder

            # Set MIDI in port if available
            if state.midi_in_port and self.midi_in_combo.count() > 0:
                index = self.midi_in_combo.findText(state.midi_in_port)
                if index >= 0:
                    self.midi_in_combo.setCurrentIndex(index)

            # Set MIDI out port if available
            if state.midi_out_port and self.midi_out_combo.count() > 0:
                index = self.midi_out_combo.findText(state.midi_out_port)
                if index >= 0:
                    self.midi_out_combo.setCurrentIndex(index)

            # Set sequencer port if available
            if state.sequencer_port and self.sequencer_combo.count() > 0:
                index = self.sequencer_combo.findText(state.sequencer_port)
                if index >= 0:
                    self.sequencer_combo.setCurrentIndex(index)

            # Set MIDI channel if available
            if state.midi_channel:
                self.channel_spin.setValue(state.midi_channel)

            # Set sync checkbox (inverted logic: sync_enabled=True means offline_mode=False)
            self.sync_checkbox.setChecked(not state.sync_enabled)

            self._updating_programmatically = False

            # Explicitly update MIDI ports from device if we have a Device object
            try:
                if isinstance(self.current_device, str):
                    logger.warning(
                        f"Current device is a string ({self.current_device}), not a Device object. Cannot update MIDI ports."
                    )
                elif (
                    hasattr(self.current_device, "midi_port")
                    and self.current_device.midi_port
                ):
                    logger.info(
                        "Explicitly updating MIDI ports from device after loading UI state"
                    )
                    self.update_midi_ports_from_device()
                else:
                    logger.info(
                        "Cannot update MIDI ports from device (no Device object or no midi_port attribute)"
                    )
            except Exception as e:
                logger.error(f"Error checking device for MIDI ports: {str(e)}")
                # Continue execution to prevent UI crash

                # If we have MIDI port information in the UI state, set it directly
                if state.midi_in_port and self.midi_in_combo.count() > 0:
                    index = self.midi_in_combo.findText(state.midi_in_port)
                    if index >= 0:
                        logger.info(
                            f"Setting MIDI in port directly to: {state.midi_in_port}"
                        )
                        self.midi_in_combo.setCurrentIndex(index)

                if state.midi_out_port and self.midi_out_combo.count() > 0:
                    index = self.midi_out_combo.findText(state.midi_out_port)
                    if index >= 0:
                        logger.info(
                            f"Setting MIDI out port directly to: {state.midi_out_port}"
                        )
                        self.midi_out_combo.setCurrentIndex(index)

                if state.sequencer_port and self.sequencer_combo.count() > 0:
                    index = self.sequencer_combo.findText(state.sequencer_port)
                    if index >= 0:
                        logger.info(
                            f"Setting sequencer port directly to: {state.sequencer_port}"
                        )
                        self.sequencer_combo.setCurrentIndex(index)

            # Trigger device_changed signal to ensure presets are loaded
            if self.current_device:
                device_name = (
                    self.current_device.name
                    if hasattr(self.current_device, "name")
                    else self.current_device
                )
                logger.info(f"Triggering device_changed signal for {device_name}")
                self.device_changed.emit(device_name)

            logger.info("UI state loaded successfully")
        except Exception as e:
            logger.error(f"Error loading UI state: {str(e)}")
            self._updating_programmatically = False

    def save_ui_state(self):
        """Save UI state to the API client"""
        if not self.api_client:
            return

        try:
            state = UIState(
                manufacturer=self.get_selected_manufacturer(),
                device=self.get_selected_device(),
                community_folder=self.get_selected_community_folder(),
                midi_in_port=self.get_selected_midi_in_port(),
                midi_out_port=self.get_selected_midi_out_port(),
                sequencer_port=self.get_selected_sequencer_port(),
                midi_channel=self.get_selected_midi_channel(),
                sync_enabled=self.is_sync_enabled(),
            )

            self.api_client.save_ui_state(state)
            logger.info(f"UI state saved: {state}")
        except Exception as e:
            logger.error(f"Error saving UI state: {str(e)}")

    # Event handlers
    def on_manufacturer_changed(self, manufacturer: str):
        """Handle manufacturer selection change"""
        if not manufacturer or self._updating_programmatically:
            return

        self.current_manufacturer = manufacturer
        logger.info(f"Manufacturer changed to: {manufacturer}")

        # Update devices for this manufacturer
        if self.api_client:
            # First, try to filter devices from the already loaded devices list
            devices_for_manufacturer = [
                d.name for d in self.devices if d.manufacturer == manufacturer
            ]
            if devices_for_manufacturer:
                logger.info(
                    f"Found {len(devices_for_manufacturer)} devices for manufacturer {manufacturer} in local cache"
                )
                self.update_devices_by_manufacturer(devices_for_manufacturer)

            # Then, asynchronously fetch the latest devices from the server
            def on_devices_loaded(devices):
                if devices:
                    logger.info(
                        f"Async loaded {len(devices)} devices for manufacturer {manufacturer}"
                    )
                    # Use QTimer to ensure UI update happens in main thread
                    QTimer.singleShot(
                        0, lambda: self.update_devices_by_manufacturer(devices)
                    )

            self.run_async(
                self._get_devices_for_manufacturer(manufacturer),
                callback=on_devices_loaded,
                loading_message=f"Loading devices for {manufacturer}...",
            )

        self.manufacturer_changed.emit(manufacturer)

        # Save UI state
        self.save_ui_state()

    async def _get_devices_for_manufacturer(self, manufacturer: str):
        """Get devices for a manufacturer asynchronously"""
        try:
            # Get devices directly from the server using the GET /devices/{manufacturer} endpoint
            devices = await self.api_client.get_devices_by_manufacturer(manufacturer)
            if devices:
                logger.info(
                    f"Found {len(devices)} devices for manufacturer {manufacturer}"
                )
                return devices
            else:
                logger.warning(f"No devices found for manufacturer {manufacturer}")
                return []
        except Exception as e:
            logger.error(
                f"Error getting devices for manufacturer {manufacturer}: {str(e)}"
            )
            return []

    def on_device_changed(self, device_name: str):
        """Handle device selection change"""
        try:
            if not device_name or self._updating_programmatically:
                return

            self.current_device = device_name
            logger.info(f"Device changed to: {device_name}")

            # Find the selected device
            device_found = False
            try:
                for device in self.devices:
                    if device.name == device_name:
                        # Set current_device to the Device object
                        self.current_device = device
                        device_found = True
                        logger.info(f"Found exact match for device: {device_name}")

                        # Update MIDI channels and ports
                        self.update_midi_channels()
                        self.update_midi_ports_from_device()

                        # Update community folders
                        try:
                            if (
                                self.api_client
                                and hasattr(device, "community_folders")
                                and device.community_folders
                            ):
                                logger.info(
                                    f"Updating community folders for device {device_name}: {device.community_folders}"
                                )
                                self.update_community_folders(device.community_folders)
                            else:
                                logger.info(
                                    f"No community folders found for device {device_name} in device object"
                                )
                                # Get community folders from the server
                                if self.api_client:

                                    def on_folders_loaded(folders):
                                        try:
                                            if folders:
                                                logger.info(
                                                    f"Async loaded {len(folders)} community folders"
                                                )
                                                QTimer.singleShot(
                                                    0,
                                                    lambda: self.update_community_folders(
                                                        folders
                                                    ),
                                                )
                                        except Exception as e:
                                            logger.error(
                                                f"Error in on_folders_loaded callback: {str(e)}"
                                            )

                                    self.run_async(
                                        self._get_community_folders(device_name),
                                        callback=on_folders_loaded,
                                        loading_message=f"Loading community folders for {device_name}...",
                                    )
                        except Exception as e:
                            logger.error(f"Error updating community folders: {str(e)}")
                        break
            except Exception as e:
                logger.error(f"Error searching for exact device match: {str(e)}")

            if not device_found:
                logger.warning(f"Device not found in devices list: {device_name}")
                # Try to find a device with a similar name
                try:
                    for device in self.devices:
                        try:
                            if (
                                device_name.lower() in device.name.lower()
                                or device.name.lower() in device_name.lower()
                            ):
                                logger.info(f"Found similar device: {device.name}")
                                # Set current_device to the Device object
                                self.current_device = device
                                device_found = True

                                # Update MIDI channels and ports
                                self.update_midi_channels()
                                self.update_midi_ports_from_device()

                                # Update community folders
                                try:
                                    if (
                                        self.api_client
                                        and hasattr(device, "community_folders")
                                        and device.community_folders
                                    ):
                                        logger.info(
                                            f"Updating community folders for similar device {device.name}: {device.community_folders}"
                                        )
                                        self.update_community_folders(
                                            device.community_folders
                                        )
                                    else:
                                        logger.info(
                                            f"No community folders found for similar device {device.name} in device object"
                                        )
                                        # Get community folders from the server
                                        if self.api_client:

                                            def on_folders_loaded(folders):
                                                try:
                                                    if folders:
                                                        logger.info(
                                                            f"Async loaded {len(folders)} community folders"
                                                        )
                                                        QTimer.singleShot(
                                                            0,
                                                            lambda: self.update_community_folders(
                                                                folders
                                                            ),
                                                        )
                                                except Exception as e:
                                                    logger.error(
                                                        f"Error in on_folders_loaded callback: {str(e)}"
                                                    )

                                            self.run_async(
                                                self._get_community_folders(
                                                    device_name
                                                ),
                                                callback=on_folders_loaded,
                                                loading_message=f"Loading community folders for {device.name}...",
                                            )
                                except Exception as e:
                                    logger.error(
                                        f"Error updating community folders for similar device: {str(e)}"
                                    )
                                break
                        except Exception as e:
                            logger.error(f"Error checking similar device: {str(e)}")
                            continue
                except Exception as e:
                    logger.error(f"Error searching for similar device: {str(e)}")

                # If still not found, keep the string value for filtering presets
                if not device_found:
                    logger.info(
                        f"No matching device found, using device name as string: {device_name}"
                    )
                    # Get community folders for this device if available
                    try:
                        if self.api_client:
                            logger.info(
                                f"Getting community folders for device {device_name} from server"
                            )

                            def on_folders_loaded(folders):
                                try:
                                    if folders:
                                        logger.info(
                                            f"Async loaded {len(folders)} community folders"
                                        )
                                        QTimer.singleShot(
                                            0,
                                            lambda: self.update_community_folders(
                                                folders
                                            ),
                                        )
                                except Exception as e:
                                    logger.error(
                                        f"Error in on_folders_loaded callback: {str(e)}"
                                    )

                            self.run_async(
                                self._get_community_folders(device_name),
                                callback=on_folders_loaded,
                                loading_message=f"Loading community folders for {device_name}...",
                            )
                    except Exception as e:
                        logger.error(
                            f"Error getting community folders from server: {str(e)}"
                        )

            self.device_changed.emit(device_name)

            # Save UI state
            self.save_ui_state()
        except Exception as e:
            logger.error(f"Error in on_device_changed: {str(e)}")
            # Continue execution to prevent UI crash

    async def _get_community_folders(self, device_name: str):
        """Get community folders for a device asynchronously"""
        try:
            logger.info(
                f"Getting community folders for device {device_name} from server"
            )
            folders = await self.api_client.get_community_folders(device_name)
            if folders:
                logger.info(
                    f"Found {len(folders)} community folders for device {device_name}: {folders}"
                )
                return folders
            else:
                logger.warning(
                    f"No community folders found for device {device_name} from server"
                )
                return []
        except Exception as e:
            logger.error(
                f"Error getting community folders for device {device_name}: {str(e)}"
            )
            return []

    def on_community_folder_changed(self, folder: str):
        """Handle community folder selection change"""
        if self._updating_programmatically:
            return

        if folder == "Default":
            self.current_community_folder = None
            logger.info("Community folder changed to: Default")
        else:
            self.current_community_folder = folder
            logger.info(f"Community folder changed to: {folder}")

        self.community_folder_changed.emit(folder)

        # Save UI state
        self.save_ui_state()

    def on_sync_changed(self, state: int):
        """Handle sync checkbox state change"""
        offline_mode = state > 0
        # Invert the logic: sync is enabled when offline mode is disabled
        sync_enabled = not offline_mode
        logger.info(
            f"Off-line mode changed to: {offline_mode}, sync enabled: {sync_enabled}"
        )

        self.sync_changed.emit(sync_enabled)

        # Save UI state
        self.save_ui_state()

    def on_midi_in_port_changed(self, port_name: str):
        """Handle MIDI in port selection change"""
        if not self._updating_programmatically:
            self.midi_in_port_changed.emit(port_name)
            self.save_ui_state()

    def on_midi_out_port_changed(self, port_name: str):
        """Handle MIDI out port selection change"""
        if not self._updating_programmatically:
            self.midi_out_port_changed.emit(port_name)
            self.save_ui_state()

    def on_sequencer_port_changed(self, port_name: str):
        """Handle sequencer port selection change"""
        if self._updating_programmatically:
            return

        if port_name == "None":
            self.sequencer_port_changed.emit("")
        else:
            self.sequencer_port_changed.emit(port_name)

        # Update the main window's selected_sequencer_port
        # This ensures the port is updated even if the signal is not connected
        if hasattr(self.parent(), "selected_sequencer_port"):
            if port_name == "None":
                self.parent().selected_sequencer_port = None
            else:
                self.parent().selected_sequencer_port = port_name

        self.save_ui_state()

    def on_midi_channel_changed(self, channel: int):
        """Handle MIDI channel selection change"""
        self.midi_channel_changed.emit(channel)
        self.save_ui_state()
