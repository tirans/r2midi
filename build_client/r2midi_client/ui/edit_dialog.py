import asyncio
import logging
from typing import Any, Callable, Dict, List, Optional

from PyQt6.QtCore import Qt, QTimer, pyqtSignal
from PyQt6.QtWidgets import (QComboBox, QDialog, QFormLayout, QGroupBox,
                             QHBoxLayout, QLabel, QLineEdit, QListWidget,
                             QListWidgetItem, QMessageBox, QPushButton,
                             QSpinBox, QTabWidget, QTextEdit, QVBoxLayout,
                             QWidget)

from ..api_client import CachedApiClient

# Configure logger
logger = logging.getLogger("r2midi_client.ui.edit_dialog")


class EditDialog(QDialog):
    """Dialog for editing manufacturers, devices, and presets"""

    # Signal emitted when changes are made
    changes_made = pyqtSignal()

    def __init__(self, api_client: CachedApiClient, parent=None):
        super().__init__(parent)
        self.api_client = api_client
        self.main_window = parent
        self.manufacturers = []
        self.devices = {}  # Map of manufacturer to list of devices
        self.collections = {}  # Map of manufacturer/device to list of collections
        self.presets = {}  # Map of manufacturer/device/collection to list of presets

        self.initUI()
        self.load_data()

    def initUI(self):
        """Initialize the UI components"""
        self.setWindowTitle("Edit Manufacturers, Devices, and Presets")
        self.setMinimumSize(800, 600)

        # Main layout
        main_layout = QVBoxLayout()
        self.setLayout(main_layout)

        # Tab widget
        self.tab_widget = QTabWidget()
        self.tab_widget.currentChanged.connect(self.on_tab_changed)
        main_layout.addWidget(self.tab_widget)

        # Create tabs
        self.create_manufacturer_tab()
        self.create_device_tab()
        self.create_preset_tab()

        # Button layout
        button_layout = QHBoxLayout()

        # Close button
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.accept)
        button_layout.addWidget(self.close_button)

        main_layout.addLayout(button_layout)

    def create_manufacturer_tab(self):
        """Create the manufacturer tab"""
        tab = QWidget()
        layout = QVBoxLayout()
        tab.setLayout(layout)

        # Manufacturer list
        list_group = QGroupBox("Manufacturers")
        list_layout = QVBoxLayout()
        list_group.setLayout(list_layout)

        self.manufacturer_list = QListWidget()
        self.manufacturer_list.itemClicked.connect(self.on_manufacturer_selected)
        list_layout.addWidget(self.manufacturer_list)

        layout.addWidget(list_group)

        # Add/Edit/Remove controls
        controls_group = QGroupBox("Add/Edit/Remove Manufacturer")
        controls_layout = QFormLayout()
        controls_group.setLayout(controls_layout)

        # Manufacturer name
        self.manufacturer_name = QLineEdit()
        controls_layout.addRow("Name:", self.manufacturer_name)

        # Buttons
        button_layout = QHBoxLayout()

        self.add_manufacturer_button = QPushButton("Add")
        self.add_manufacturer_button.clicked.connect(self.add_manufacturer)
        button_layout.addWidget(self.add_manufacturer_button)

        self.remove_manufacturer_button = QPushButton("Remove")
        self.remove_manufacturer_button.clicked.connect(self.remove_manufacturer)
        button_layout.addWidget(self.remove_manufacturer_button)

        controls_layout.addRow("", button_layout)

        layout.addWidget(controls_group)

        # Add tab
        self.tab_widget.addTab(tab, "Manufacturers")

    def create_device_tab(self):
        """Create the device tab"""
        tab = QWidget()
        layout = QVBoxLayout()
        tab.setLayout(layout)

        # Manufacturer selection
        manufacturer_layout = QHBoxLayout()
        manufacturer_layout.addWidget(QLabel("Manufacturer:"))
        self.device_manufacturer_combo = QComboBox()
        self.device_manufacturer_combo.currentTextChanged.connect(
            self.on_device_manufacturer_changed
        )
        manufacturer_layout.addWidget(self.device_manufacturer_combo)
        layout.addLayout(manufacturer_layout)

        # Device list
        list_group = QGroupBox("Devices")
        list_layout = QVBoxLayout()
        list_group.setLayout(list_layout)

        self.device_list = QListWidget()
        self.device_list.itemClicked.connect(self.on_device_selected)
        list_layout.addWidget(self.device_list)

        layout.addWidget(list_group)

        # Add/Edit/Remove controls
        controls_group = QGroupBox("Add/Edit/Remove Device")
        controls_layout = QFormLayout()
        controls_group.setLayout(controls_layout)

        # Device name
        self.device_name = QLineEdit()
        controls_layout.addRow("Name:", self.device_name)

        # Device version
        self.device_version = QLineEdit("1.0.0")
        controls_layout.addRow("Version:", self.device_version)

        # Manufacturer ID
        self.device_manufacturer_id = QSpinBox()
        self.device_manufacturer_id.setRange(0, 127)
        controls_layout.addRow("Manufacturer ID:", self.device_manufacturer_id)

        # Device ID
        self.device_id = QSpinBox()
        self.device_id.setRange(0, 127)
        controls_layout.addRow("Device ID:", self.device_id)

        # Buttons
        button_layout = QHBoxLayout()

        self.add_device_button = QPushButton("Add")
        self.add_device_button.clicked.connect(self.add_device)
        button_layout.addWidget(self.add_device_button)

        self.remove_device_button = QPushButton("Remove")
        self.remove_device_button.clicked.connect(self.remove_device)
        button_layout.addWidget(self.remove_device_button)

        controls_layout.addRow("", button_layout)

        layout.addWidget(controls_group)

        # Add tab
        self.tab_widget.addTab(tab, "Devices")

    def create_preset_tab(self):
        """Create the preset tab"""
        tab = QWidget()
        layout = QVBoxLayout()
        tab.setLayout(layout)

        # Manufacturer and device selection
        selection_layout = QFormLayout()

        self.preset_manufacturer_combo = QComboBox()
        self.preset_manufacturer_combo.currentTextChanged.connect(
            self.on_preset_manufacturer_changed
        )
        selection_layout.addRow("Manufacturer:", self.preset_manufacturer_combo)

        self.preset_device_combo = QComboBox()
        self.preset_device_combo.currentTextChanged.connect(
            self.on_preset_device_changed
        )
        selection_layout.addRow("Device:", self.preset_device_combo)

        self.preset_collection_combo = QComboBox()
        self.preset_collection_combo.currentTextChanged.connect(
            self.on_preset_collection_changed
        )
        selection_layout.addRow("Collection:", self.preset_collection_combo)

        # Collection name edit field
        self.collection_name_edit = QLineEdit()
        self.collection_name_edit.setPlaceholderText("Enter collection name")

        # Collection update button
        self.collection_update_button = QPushButton("Update Collection")
        self.collection_update_button.clicked.connect(self.update_collection)

        # Collection remove button
        self.collection_remove_button = QPushButton("Remove")
        self.collection_remove_button.clicked.connect(self.remove_collection)

        # Add collection name edit and update button to a horizontal layout
        collection_edit_layout = QHBoxLayout()
        collection_edit_layout.addWidget(self.collection_name_edit)
        collection_edit_layout.addWidget(self.collection_update_button)

        # Add the remove button to a separate layout
        collection_remove_layout = QHBoxLayout()
        collection_remove_layout.addStretch()
        collection_remove_layout.addWidget(self.collection_remove_button)

        # Add the layouts to the form
        selection_layout.addRow("Edit Collection:", collection_edit_layout)
        selection_layout.addRow("", collection_remove_layout)

        layout.addLayout(selection_layout)

        # Preset list
        list_group = QGroupBox("Presets")
        list_layout = QVBoxLayout()
        list_group.setLayout(list_layout)

        self.preset_list = QListWidget()
        self.preset_list.itemClicked.connect(self.on_preset_selected)
        list_layout.addWidget(self.preset_list)

        layout.addWidget(list_group)

        # Add/Edit/Remove controls
        controls_group = QGroupBox("Add/Edit/Remove Preset")
        controls_layout = QFormLayout()
        controls_group.setLayout(controls_layout)

        # Preset name
        self.preset_name = QLineEdit()
        controls_layout.addRow("Name:", self.preset_name)

        # Category
        self.preset_category = QLineEdit()
        controls_layout.addRow("Category:", self.preset_category)

        # CC 0
        self.preset_cc0 = QSpinBox()
        self.preset_cc0.setRange(0, 127)
        controls_layout.addRow("CC 0:", self.preset_cc0)

        # Program
        self.preset_pgm = QSpinBox()
        self.preset_pgm.setRange(0, 127)
        controls_layout.addRow("Program:", self.preset_pgm)

        # Characters
        self.preset_characters = QLineEdit()
        controls_layout.addRow("Characters (comma-separated):", self.preset_characters)

        # Buttons
        button_layout = QHBoxLayout()

        self.add_preset_button = QPushButton("Add")
        self.add_preset_button.clicked.connect(self.add_preset)
        button_layout.addWidget(self.add_preset_button)

        self.update_preset_button = QPushButton("Update")
        self.update_preset_button.clicked.connect(self.update_preset)
        button_layout.addWidget(self.update_preset_button)

        self.remove_preset_button = QPushButton("Remove")
        self.remove_preset_button.clicked.connect(self.remove_preset)
        button_layout.addWidget(self.remove_preset_button)

        controls_layout.addRow("", button_layout)

        layout.addWidget(controls_group)

        # Add tab
        self.tab_widget.addTab(tab, "Presets")

    def load_data(self):
        """Load data from the server"""
        # Start a timer to load data asynchronously
        QTimer.singleShot(0, self.load_manufacturers)

        # After manufacturers are loaded, load devices and presets
        QTimer.singleShot(500, self.load_initial_devices_and_presets)

    def load_initial_devices_and_presets(self):
        """Load initial devices and presets for the first manufacturer"""
        # Get the first manufacturer
        if self.preset_manufacturer_combo.count() > 0:
            manufacturer = self.preset_manufacturer_combo.itemText(0)
            if manufacturer:
                # Load devices for this manufacturer
                def on_devices_loaded(devices):
                    self.devices[manufacturer] = devices

                    # Update device lists
                    self.device_list.clear()

                    # Always update the device list in the device tab
                    for device in devices:
                        self.device_list.addItem(device)

                    # Update the preset device combo
                    self.preset_device_combo.clear()
                    for device in devices:
                        self.preset_device_combo.addItem(device)

                    # Load presets for the first device
                    if devices and len(devices) > 0:
                        device = devices[0]
                        # Load collections for this device
                        self.load_collections(manufacturer, device)
                        # Load presets for this device
                        self.load_presets(manufacturer, device)

                # Always force refresh to ensure we get fresh data from the server
                self.run_async(
                    self.api_client.get_devices_by_manufacturer(
                        manufacturer, force_refresh=True
                    ),
                    on_devices_loaded,
                    loading_message=f"Loading devices for {manufacturer}...",
                )

    def on_tab_changed(self, index):
        """Handle tab changes"""
        # If the devices tab is selected (index 1), ensure we have the latest data
        if index == 1:  # Devices tab
            # Get the current manufacturer
            manufacturer = self.device_manufacturer_combo.currentText()
            if manufacturer:
                logger.info(f"Loading devices for {manufacturer} on tab change")
                # Use a timer to delay loading to ensure the UI is fully updated
                QTimer.singleShot(100, lambda: self.load_devices(manufacturer))

        # If the presets tab is selected (index 2), ensure we have the latest data
        elif index == 2:  # Presets tab
            # Get the current selections
            manufacturer = self.preset_manufacturer_combo.currentText()
            device = self.preset_device_combo.currentText()

            if manufacturer and device:
                # Check if we need to refresh the presets
                key = f"{manufacturer}/{device}"
                if key not in self.presets:
                    # If we don't have presets for this manufacturer/device, load them
                    logger.info(
                        f"Loading presets for {manufacturer}/{device} on tab change"
                    )
                    # Use a timer to delay loading to ensure the UI is fully updated
                    QTimer.singleShot(
                        100, lambda: self.load_presets(manufacturer, device)
                    )
                else:
                    # If we already have presets, just update the list
                    logger.info(
                        f"Updating preset list for {manufacturer}/{device} on tab change"
                    )
                    self.update_preset_list()

    def run_async(
        self,
        coro,
        callback=None,
        error_callback=None,
        loading_message="Loading data...",
    ):
        """Run an async coroutine and call the callback with the result

        Args:
            coro: The coroutine to run
            callback: Optional callback to run with the result
            error_callback: Optional callback to run on error
            loading_message: Optional message to display in the loading indicator
        """
        if self.main_window and hasattr(self.main_window, "run_async_task"):
            # Use a try-except block to catch and log any asyncio errors
            try:
                # If no error callback is provided, use a default one that logs the error
                if error_callback is None:
                    error_callback = lambda error: logger.error(f"Async error: {error}")

                # Run the async task in the main window's event loop
                self.main_window.run_async_task(
                    coro, callback, error_callback, loading_message
                )
            except Exception as e:
                logger.error(f"Error running async task: {str(e)}")
                QMessageBox.warning(
                    self, "Error", f"Error running async task: {str(e)}"
                )
                # If an error callback was provided, call it
                if error_callback:
                    error_callback(str(e))
        else:
            error_msg = "Cannot run async operation without main window reference"
            logger.error(error_msg)
            # If an error callback was provided, call it
            if error_callback:
                error_callback(error_msg)

    # Keep track of ongoing manufacturer loading operations
    _loading_manufacturers = False

    def load_manufacturers(self):
        """Load manufacturers from the server"""
        # Check if we're already loading manufacturers
        if self._loading_manufacturers:
            logger.info("Already loading manufacturers, skipping duplicate request")
            return

        # Mark as loading
        self._loading_manufacturers = True

        def on_manufacturers_loaded(manufacturers):
            try:
                self.manufacturers = manufacturers

                # Update manufacturer lists
                self.manufacturer_list.clear()
                self.device_manufacturer_combo.clear()
                self.preset_manufacturer_combo.clear()

                for manufacturer in manufacturers:
                    self.manufacturer_list.addItem(manufacturer)
                    self.device_manufacturer_combo.addItem(manufacturer)
                    self.preset_manufacturer_combo.addItem(manufacturer)

                logger.info(f"Successfully loaded {len(manufacturers)} manufacturers")
            except Exception as e:
                logger.error(f"Error processing manufacturers: {str(e)}")
            finally:
                # Mark as no longer loading
                self._loading_manufacturers = False

        def on_error(error_msg):
            logger.error(f"Error loading manufacturers: {error_msg}")
            # Show error message to the user
            QMessageBox.warning(
                self, "Error", f"Error loading manufacturers: {error_msg}"
            )
            # Mark as no longer loading
            self._loading_manufacturers = False

        try:
            # Always force refresh to ensure we get fresh data from the server
            logger.info("Loading manufacturers")
            self.run_async(
                self.api_client.get_manufacturers(force_refresh=True),
                on_manufacturers_loaded,
                on_error,
                loading_message="Loading manufacturers...",
            )
        except Exception as e:
            logger.error(f"Error starting manufacturer load: {str(e)}")
            # Show error message to the user
            QMessageBox.warning(self, "Error", f"Error loading manufacturers: {str(e)}")
            # Mark as no longer loading
            self._loading_manufacturers = False

    # Keep track of ongoing device loading operations
    _loading_devices = set()

    def load_devices(self, manufacturer):
        """Load devices for a manufacturer from the server"""
        # Check if we're already loading devices for this manufacturer
        if manufacturer in self._loading_devices:
            logger.info(
                f"Already loading devices for {manufacturer}, skipping duplicate request"
            )
            return

        # Mark as loading
        self._loading_devices.add(manufacturer)

        def on_devices_loaded(devices):
            try:
                self.devices[manufacturer] = devices

                # Update device lists
                self.device_list.clear()

                # Always update the device list in the device tab
                for device in devices:
                    self.device_list.addItem(device)

                # Update the preset device combo if the current manufacturer matches
                if self.preset_manufacturer_combo.currentText() == manufacturer:
                    self.preset_device_combo.clear()
                    for device in devices:
                        self.preset_device_combo.addItem(device)

                logger.info(
                    f"Successfully loaded {len(devices)} devices for {manufacturer}"
                )
            except Exception as e:
                logger.error(f"Error processing devices: {str(e)}")
            finally:
                # Mark as no longer loading
                if manufacturer in self._loading_devices:
                    self._loading_devices.remove(manufacturer)

        def on_error(error_msg):
            logger.error(f"Error loading devices for {manufacturer}: {error_msg}")
            # Show error message to the user
            QMessageBox.warning(self, "Error", f"Error loading devices: {error_msg}")
            # Mark as no longer loading
            if manufacturer in self._loading_devices:
                self._loading_devices.remove(manufacturer)

        try:
            # Always force refresh to ensure we get fresh data from the server
            logger.info(f"Loading devices for {manufacturer}")
            self.run_async(
                self.api_client.get_devices_by_manufacturer(
                    manufacturer, force_refresh=True
                ),
                on_devices_loaded,
                on_error,
                loading_message=f"Loading devices for {manufacturer}...",
            )
        except Exception as e:
            logger.error(f"Error starting device load: {str(e)}")
            # Show error message to the user
            QMessageBox.warning(self, "Error", f"Error loading devices: {str(e)}")
            # Mark as no longer loading
            if manufacturer in self._loading_devices:
                self._loading_devices.remove(manufacturer)

    # Keep track of ongoing collection loading operations
    _loading_collections = set()

    def load_collections(self, manufacturer, device):
        """Load collections for a device from the server"""
        # Create a unique key for this loading operation
        load_key = f"{manufacturer}/{device}"

        # Check if we're already loading these collections
        if load_key in self._loading_collections:
            logger.info(
                f"Already loading collections for {load_key}, skipping duplicate request"
            )
            return

        # Mark as loading
        self._loading_collections.add(load_key)

        def on_collections_loaded(collections):
            try:
                # Store collections
                self.collections[f"{manufacturer}/{device}"] = collections

                # Update collection combo box
                self.preset_collection_combo.clear()
                for collection in collections:
                    self.preset_collection_combo.addItem(collection)

                # If no collections were found, add a default one
                if not collections:
                    self.preset_collection_combo.addItem("default")

                logger.info(
                    f"Successfully loaded {len(collections)} collections for {manufacturer}/{device}"
                )
            except Exception as e:
                logger.error(f"Error processing collections: {str(e)}")
                # Add default collection on error
                self.preset_collection_combo.clear()
                self.preset_collection_combo.addItem("default")
            finally:
                # Mark as no longer loading
                if load_key in self._loading_collections:
                    self._loading_collections.remove(load_key)

        def on_error(error_msg):
            logger.error(f"Error loading collections for {load_key}: {error_msg}")
            # Show error message to the user
            QMessageBox.warning(
                self, "Error", f"Error loading collections: {error_msg}"
            )
            # Add default collection on error
            self.preset_collection_combo.clear()
            self.preset_collection_combo.addItem("default")
            # Mark as no longer loading
            if load_key in self._loading_collections:
                self._loading_collections.remove(load_key)

        try:
            # Always force refresh to ensure we get fresh data from the server
            logger.info(f"Loading collections for {load_key}")
            self.run_async(
                self.api_client.get_collections(
                    manufacturer, device, force_refresh=True
                ),
                on_collections_loaded,
                on_error,
                loading_message=f"Loading collections for {manufacturer}/{device}...",
            )
        except Exception as e:
            logger.error(f"Error starting collection load: {str(e)}")
            # Show error message to the user
            QMessageBox.warning(self, "Error", f"Error loading collections: {str(e)}")
            # Add default collection on error
            self.preset_collection_combo.clear()
            self.preset_collection_combo.addItem("default")
            # Mark as no longer loading
            if load_key in self._loading_collections:
                self._loading_collections.remove(load_key)

    # Keep track of ongoing preset loading operations
    _loading_presets = set()

    def load_presets(self, manufacturer, device, collection=None):
        """Load presets for a device from the server"""
        # Create a unique key for this loading operation
        load_key = f"{manufacturer}/{device}/{collection or 'default'}"

        # Check if we're already loading these presets
        if load_key in self._loading_presets:
            logger.info(
                f"Already loading presets for {load_key}, skipping duplicate request"
            )
            return

        # Mark as loading
        self._loading_presets.add(load_key)

        def on_presets_loaded(presets):
            try:
                # Store presets by collection
                preset_by_collection = {}
                for preset in presets:
                    collection = preset.source or "default"
                    if collection not in preset_by_collection:
                        preset_by_collection[collection] = []
                    preset_by_collection[collection].append(preset)

                # Store all presets
                self.presets[f"{manufacturer}/{device}"] = preset_by_collection

                # Update preset list if the current selection matches
                if (
                    self.preset_manufacturer_combo.currentText() == manufacturer
                    and self.preset_device_combo.currentText() == device
                ):
                    self.update_preset_list()

                logger.info(
                    f"Successfully loaded {sum(len(presets) for presets in preset_by_collection.values())} presets for {manufacturer}/{device}"
                )
            except Exception as e:
                logger.error(f"Error processing presets: {str(e)}")
            finally:
                # Mark as no longer loading
                if load_key in self._loading_presets:
                    self._loading_presets.remove(load_key)

        def on_error(error_msg):
            logger.error(f"Error loading presets for {load_key}: {error_msg}")
            # Show error message to the user
            QMessageBox.warning(self, "Error", f"Error loading presets: {error_msg}")
            # Mark as no longer loading
            if load_key in self._loading_presets:
                self._loading_presets.remove(load_key)

        try:
            # Always force refresh to ensure we get fresh data from the server
            logger.info(f"Loading presets for {load_key}")
            self.run_async(
                self.api_client.get_presets(
                    device, collection, manufacturer, force_refresh=True
                ),
                on_presets_loaded,
                on_error,
                loading_message=f"Loading presets for {manufacturer}/{device}...",
            )
        except Exception as e:
            logger.error(f"Error starting preset load: {str(e)}")
            # Show error message to the user
            QMessageBox.warning(self, "Error", f"Error loading presets: {str(e)}")
            # Mark as no longer loading
            if load_key in self._loading_presets:
                self._loading_presets.remove(load_key)

    def update_preset_list(self):
        """Update the preset list based on the current selection"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        device = self.preset_device_combo.currentText()
        collection = self.preset_collection_combo.currentText()

        if not manufacturer or not device or not collection:
            return

        # Clear the list
        self.preset_list.clear()

        # Get presets for the selected collection
        key = f"{manufacturer}/{device}"
        if key in self.presets and collection in self.presets[key]:
            for preset in self.presets[key][collection]:
                self.preset_list.addItem(preset.preset_name)

    def on_manufacturer_selected(self, item):
        """Handle manufacturer selection in the manufacturer tab"""
        if item:
            self.manufacturer_name.setText(item.text())

    def on_device_manufacturer_changed(self, manufacturer):
        """Handle manufacturer selection change in the device tab"""
        if manufacturer:
            # Always load devices for this manufacturer to ensure fresh data
            self.load_devices(manufacturer)

    def on_device_selected(self, item):
        """Handle device selection in the device tab"""
        if item:
            self.device_name.setText(item.text())

            # Try to get device info
            manufacturer = self.device_manufacturer_combo.currentText()
            if manufacturer:

                def on_device_info_loaded(device_info):
                    for info in device_info:
                        if info.get("name") == item.text():
                            self.device_version.setText(info.get("version", "1.0.0"))
                            self.device_manufacturer_id.setValue(
                                info.get("manufacturer_id", 0)
                            )
                            self.device_id.setValue(info.get("device_id", 0))
                            break

                # Always force refresh to ensure we get fresh data from the server
                self.run_async(
                    self.api_client.get_device_info(manufacturer, force_refresh=True),
                    on_device_info_loaded,
                    loading_message=f"Loading device info for {manufacturer}...",
                )

    def on_preset_manufacturer_changed(self, manufacturer):
        """Handle manufacturer selection change in the preset tab"""
        if manufacturer:
            # Always load devices for this manufacturer to ensure fresh data
            self.load_devices(manufacturer)

            # Also load presets for the first device in the list after devices are loaded
            def on_devices_loaded():
                device = self.preset_device_combo.currentText()
                if device:
                    # Check if we need to refresh the presets
                    key = f"{manufacturer}/{device}"
                    if key not in self.presets:
                        # If we don't have presets for this manufacturer/device, load them
                        logger.info(
                            f"Loading presets for {manufacturer}/{device} on manufacturer change"
                        )
                        # Load presets for the selected device
                        self.load_presets(manufacturer, device)
                    else:
                        # If we already have presets, just update the list
                        logger.info(
                            f"Updating preset list for {manufacturer}/{device} on manufacturer change"
                        )
                        self.update_preset_list()

            # Use a timer to ensure devices are loaded first
            QTimer.singleShot(100, on_devices_loaded)

    def on_preset_device_changed(self, device):
        """Handle device selection change in the preset tab"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        if manufacturer and device:
            # Always load collections for this device to ensure fresh data
            self.load_collections(manufacturer, device)

            # Check if we need to refresh the presets
            key = f"{manufacturer}/{device}"
            if key not in self.presets:
                # If we don't have presets for this manufacturer/device, load them
                logger.info(
                    f"Loading presets for {manufacturer}/{device} on device change"
                )
                # Load presets for the selected device
                self.load_presets(manufacturer, device)
            else:
                # If we already have presets, just update the list
                logger.info(
                    f"Updating preset list for {manufacturer}/{device} on device change"
                )
                self.update_preset_list()

    def on_preset_collection_changed(self, collection):
        """Handle collection selection change in the preset tab"""
        if collection:
            # Update the collection name edit field with the selected collection name
            self.collection_name_edit.setText(collection)

            manufacturer = self.preset_manufacturer_combo.currentText()
            device = self.preset_device_combo.currentText()
            if manufacturer and device:
                # Check if we need to refresh the presets
                key = f"{manufacturer}/{device}"
                if key not in self.presets:
                    # If we don't have presets for this manufacturer/device, load them
                    logger.info(
                        f"Loading presets for {manufacturer}/{device} on collection change"
                    )
                    # Load presets for the selected device and collection
                    self.load_presets(manufacturer, device, collection)
                else:
                    # If we already have presets, just update the list
                    logger.info(
                        f"Updating preset list for {manufacturer}/{device} on collection change"
                    )
                    self.update_preset_list()
            else:
                # If no manufacturer or device selected, just update the list from cache
                self.update_preset_list()

    def update_collection(self):
        """Update the selected collection"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        device = self.preset_device_combo.currentText()
        current_collection = self.preset_collection_combo.currentText()
        new_collection_name = self.collection_name_edit.text().strip()

        if not manufacturer or not device:
            QMessageBox.warning(self, "Error", "No manufacturer or device selected")
            return

        # If the new collection name is empty, show error
        if not new_collection_name:
            QMessageBox.warning(self, "Error", "Collection name cannot be empty")
            return

        # Check if the collection exists in preset_collections
        key = f"{manufacturer}/{device}"
        if key in self.collections and new_collection_name in self.collections[key]:
            # Collection exists, update it
            if current_collection and current_collection != "default":
                # Rename the current collection
                def on_collection_updated(result):
                    if result.get("status") == "success":
                        QMessageBox.information(
                            self,
                            "Success",
                            result.get("message", "Collection renamed successfully"),
                        )
                        # Reload collections
                        self.load_collections(manufacturer, device)
                        self.changes_made.emit()
                    else:
                        QMessageBox.warning(
                            self,
                            "Error",
                            result.get("message", "Failed to rename collection"),
                        )

                self.run_async(
                    self.api_client.update_collection(
                        manufacturer, device, current_collection, new_collection_name
                    ),
                    on_collection_updated,
                    loading_message=f"Renaming collection {current_collection} to {new_collection_name}...",
                )
            else:
                # Just select the existing collection
                index = self.preset_collection_combo.findText(new_collection_name)
                if index >= 0:
                    self.preset_collection_combo.setCurrentIndex(index)
        else:
            # Collection doesn't exist, create it
            def on_collection_created(result):
                if result.get("status") == "success":
                    QMessageBox.information(
                        self,
                        "Success",
                        result.get("message", "Collection created successfully"),
                    )
                    # Reload collections
                    self.load_collections(manufacturer, device)
                    self.changes_made.emit()
                else:
                    QMessageBox.warning(
                        self,
                        "Error",
                        result.get("message", "Failed to create collection"),
                    )

            self.run_async(
                self.api_client.create_collection(
                    manufacturer, device, new_collection_name
                ),
                on_collection_created,
                loading_message=f"Creating collection {new_collection_name}...",
            )

    def remove_collection(self):
        """Remove the selected collection"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        device = self.preset_device_combo.currentText()
        collection = self.preset_collection_combo.currentText()

        if not manufacturer or not device:
            QMessageBox.warning(self, "Error", "No manufacturer or device selected")
            return

        if not collection or collection == "default":
            QMessageBox.warning(self, "Error", "Cannot remove the default collection")
            return

        # Confirm deletion
        reply = QMessageBox.question(
            self,
            "Confirm Deletion",
            f"Are you sure you want to delete collection '{collection}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:

            def on_collection_deleted(result):
                if result.get("status") == "success":
                    QMessageBox.information(
                        self,
                        "Success",
                        result.get("message", "Collection deleted successfully"),
                    )
                    # Reload collections
                    self.load_collections(manufacturer, device)
                    self.changes_made.emit()
                else:
                    QMessageBox.warning(
                        self,
                        "Error",
                        result.get("message", "Failed to delete collection"),
                    )

            self.run_async(
                self.api_client.delete_collection(manufacturer, device, collection),
                on_collection_deleted,
                loading_message=f"Deleting collection {collection}...",
            )

    def on_preset_selected(self, item):
        """Handle preset selection in the preset tab"""
        if item:
            manufacturer = self.preset_manufacturer_combo.currentText()
            device = self.preset_device_combo.currentText()
            collection = self.preset_collection_combo.currentText()

            if not manufacturer or not device or not collection:
                return

            # Find the preset
            key = f"{manufacturer}/{device}"
            if key in self.presets and collection in self.presets[key]:
                for preset in self.presets[key][collection]:
                    if preset.preset_name == item.text():
                        self.preset_name.setText(preset.preset_name)
                        self.preset_category.setText(preset.category)
                        self.preset_cc0.setValue(preset.cc_0 or 0)
                        self.preset_pgm.setValue(preset.pgm or 0)
                        self.preset_characters.setText(
                            ", ".join(preset.characters or [])
                        )
                        break

    def add_manufacturer(self):
        """Add a new manufacturer"""
        name = self.manufacturer_name.text().strip()
        if not name:
            QMessageBox.warning(self, "Error", "Manufacturer name cannot be empty")
            return

        def on_manufacturer_created(result):
            if result.get("status") == "success":
                QMessageBox.information(
                    self,
                    "Success",
                    result.get("message", "Manufacturer created successfully"),
                )
                self.load_manufacturers()
                self.changes_made.emit()
            else:
                QMessageBox.warning(
                    self,
                    "Error",
                    result.get("message", "Failed to create manufacturer"),
                )

        self.run_async(
            self.api_client.create_manufacturer(name),
            on_manufacturer_created,
            loading_message=f"Creating manufacturer {name}...",
        )

    def remove_manufacturer(self):
        """Remove a manufacturer"""
        item = self.manufacturer_list.currentItem()
        if not item:
            QMessageBox.warning(self, "Error", "No manufacturer selected")
            return

        name = item.text()

        # Confirm deletion
        reply = QMessageBox.question(
            self,
            "Confirm Deletion",
            f"Are you sure you want to delete manufacturer '{name}' and all its devices?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:

            def on_manufacturer_deleted(result):
                if result.get("status") == "success":
                    QMessageBox.information(
                        self,
                        "Success",
                        result.get("message", "Manufacturer deleted successfully"),
                    )
                    self.load_manufacturers()
                    self.changes_made.emit()
                else:
                    QMessageBox.warning(
                        self,
                        "Error",
                        result.get("message", "Failed to delete manufacturer"),
                    )

            self.run_async(
                self.api_client.delete_manufacturer(name),
                on_manufacturer_deleted,
                loading_message=f"Deleting manufacturer {name}...",
            )

    def add_device(self):
        """Add a new device"""
        manufacturer = self.device_manufacturer_combo.currentText()
        name = self.device_name.text().strip()
        version = self.device_version.text().strip()
        manufacturer_id = self.device_manufacturer_id.value()
        device_id = self.device_id.value()

        if not manufacturer:
            QMessageBox.warning(self, "Error", "No manufacturer selected")
            return

        if not name:
            QMessageBox.warning(self, "Error", "Device name cannot be empty")
            return

        # Create device data
        device_data = {
            "name": name,
            "manufacturer": manufacturer,
            "version": version,
            "manufacturer_id": manufacturer_id,
            "device_id": device_id,
            "midi_ports": {"IN": "", "OUT": ""},
            "midi_channels": {"IN": 1, "OUT": 1},
        }

        def on_device_created(result):
            if result.get("status") == "success":
                # Update status bar instead of showing a popup
                if self.main_window and hasattr(self.main_window, "status_bar"):
                    self.main_window.status_bar.showMessage(
                        result.get("message", "Device created successfully"), 3000
                    )
                self.load_devices(manufacturer)
                self.changes_made.emit()
            else:
                QMessageBox.warning(
                    self, "Error", result.get("message", "Failed to create device")
                )

        self.run_async(
            self.api_client.create_device(device_data),
            on_device_created,
            loading_message=f"Creating device {name}...",
        )

    def remove_device(self):
        """Remove a device"""
        manufacturer = self.device_manufacturer_combo.currentText()
        item = self.device_list.currentItem()

        if not manufacturer:
            QMessageBox.warning(self, "Error", "No manufacturer selected")
            return

        if not item:
            QMessageBox.warning(self, "Error", "No device selected")
            return

        device_name = item.text()

        # Confirm deletion
        reply = QMessageBox.question(
            self,
            "Confirm Deletion",
            f"Are you sure you want to delete device '{device_name}' and all its presets?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:

            def on_device_deleted(result):
                if result.get("status") == "success":
                    QMessageBox.information(
                        self,
                        "Success",
                        result.get("message", "Device deleted successfully"),
                    )
                    self.load_devices(manufacturer)
                    self.changes_made.emit()
                else:
                    QMessageBox.warning(
                        self, "Error", result.get("message", "Failed to delete device")
                    )

            self.run_async(
                self.api_client.delete_device(manufacturer, device_name),
                on_device_deleted,
                loading_message=f"Deleting device {device_name}...",
            )

    def add_preset(self):
        """Add a new preset"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        device = self.preset_device_combo.currentText()
        collection = self.preset_collection_combo.currentText()
        name = self.preset_name.text().strip()
        category = self.preset_category.text().strip()
        cc0 = self.preset_cc0.value()
        pgm = self.preset_pgm.value()
        characters_text = self.preset_characters.text().strip()

        if not manufacturer:
            QMessageBox.warning(self, "Error", "No manufacturer selected")
            return

        if not device:
            QMessageBox.warning(self, "Error", "No device selected")
            return

        if not collection:
            QMessageBox.warning(self, "Error", "No collection selected")
            return

        if not name:
            QMessageBox.warning(self, "Error", "Preset name cannot be empty")
            return

        if not category:
            QMessageBox.warning(self, "Error", "Category cannot be empty")
            return

        # Parse characters
        characters = [c.strip() for c in characters_text.split(",") if c.strip()]

        # Create preset data
        preset_data = {
            "preset_name": name,
            "category": category,
            "collection": collection,
            "device": device,
            "manufacturer": manufacturer,
            "cc_0": cc0,
            "pgm": pgm,
            "characters": characters,
        }

        def on_preset_created(result):
            if result.get("status") == "success":
                QMessageBox.information(
                    self,
                    "Success",
                    result.get("message", "Preset created successfully"),
                )
                self.load_presets(manufacturer, device)
                self.changes_made.emit()
            else:
                QMessageBox.warning(
                    self, "Error", result.get("message", "Failed to create preset")
                )

        self.run_async(
            self.api_client.create_preset(preset_data),
            on_preset_created,
            loading_message=f"Creating preset {name}...",
        )

    def update_preset(self):
        """Update an existing preset"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        device = self.preset_device_combo.currentText()
        collection = self.preset_collection_combo.currentText()
        name = self.preset_name.text().strip()
        category = self.preset_category.text().strip()
        cc0 = self.preset_cc0.value()
        pgm = self.preset_pgm.value()
        characters_text = self.preset_characters.text().strip()

        if not manufacturer:
            QMessageBox.warning(self, "Error", "No manufacturer selected")
            return

        if not device:
            QMessageBox.warning(self, "Error", "No device selected")
            return

        if not collection:
            QMessageBox.warning(self, "Error", "No collection selected")
            return

        if not name:
            QMessageBox.warning(self, "Error", "Preset name cannot be empty")
            return

        if not category:
            QMessageBox.warning(self, "Error", "Category cannot be empty")
            return

        # Check if a preset is selected
        item = self.preset_list.currentItem()
        if not item:
            QMessageBox.warning(self, "Error", "No preset selected")
            return

        # Parse characters
        characters = [c.strip() for c in characters_text.split(",") if c.strip()]

        # Create preset data
        preset_data = {
            "preset_name": name,
            "category": category,
            "collection": collection,
            "device": device,
            "manufacturer": manufacturer,
            "cc_0": cc0,
            "pgm": pgm,
            "characters": characters,
        }

        def on_preset_updated(result):
            if result.get("status") == "success":
                QMessageBox.information(
                    self,
                    "Success",
                    result.get("message", "Preset updated successfully"),
                )
                self.load_presets(manufacturer, device)
                self.changes_made.emit()
            else:
                QMessageBox.warning(
                    self, "Error", result.get("message", "Failed to update preset")
                )

        self.run_async(
            self.api_client.update_preset(preset_data),
            on_preset_updated,
            loading_message=f"Updating preset {name}...",
        )

    def remove_preset(self):
        """Remove a preset"""
        manufacturer = self.preset_manufacturer_combo.currentText()
        device = self.preset_device_combo.currentText()
        collection = self.preset_collection_combo.currentText()
        item = self.preset_list.currentItem()

        if not manufacturer:
            QMessageBox.warning(self, "Error", "No manufacturer selected")
            return

        if not device:
            QMessageBox.warning(self, "Error", "No device selected")
            return

        if not collection:
            QMessageBox.warning(self, "Error", "No collection selected")
            return

        if not item:
            QMessageBox.warning(self, "Error", "No preset selected")
            return

        preset_name = item.text()

        # Confirm deletion
        reply = QMessageBox.question(
            self,
            "Confirm Deletion",
            f"Are you sure you want to delete preset '{preset_name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:

            def on_preset_deleted(result):
                if result.get("status") == "success":
                    QMessageBox.information(
                        self,
                        "Success",
                        result.get("message", "Preset deleted successfully"),
                    )
                    self.load_presets(manufacturer, device)
                    self.changes_made.emit()
                else:
                    QMessageBox.warning(
                        self, "Error", result.get("message", "Failed to delete preset")
                    )

            self.run_async(
                self.api_client.delete_preset(
                    manufacturer, device, collection, preset_name
                ),
                on_preset_deleted,
                loading_message=f"Deleting preset {preset_name}...",
            )
