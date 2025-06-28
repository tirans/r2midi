import asyncio
import concurrent.futures
import logging
import sys
import threading
import time
import traceback
from typing import Any, Callable, Coroutine, Optional

from PyQt6.QtCore import (QEasingCurve, QObject, QPoint, QPropertyAnimation,
                          QSize, Qt, QThread, QTimer, pyqtProperty, pyqtSignal,
                          pyqtSlot)
from PyQt6.QtWidgets import (QApplication, QGraphicsOpacityEffect, QHBoxLayout,
                             QLabel, QMainWindow, QMessageBox, QProgressBar,
                             QPushButton, QSplitter, QStatusBar, QVBoxLayout,
                             QWidget)

from ..api_client import CachedApiClient
from ..config import get_config, get_config_manager
from ..models import Preset
from ..performance import PerformanceContext, get_monitor
from ..shortcuts import ShortcutManager
from ..themes import ThemeManager
from .device_panel import DevicePanel
from .edit_dialog import EditDialog
from .preferences_dialog import PreferencesDialog
from .preset_panel import PresetPanel

# Configure logger
logger = logging.getLogger("r2midi_client.ui.main_window")


class WIPAnimation(QLabel):
    """Widget for displaying a 'WIP' animation"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setText("WIP")
        self.setStyleSheet(
            """
            background-color: rgba(255, 204, 204, 180);
            color: #990000;
            border-radius: 5px;
            padding: 5px;
            font-weight: bold;
        """
        )
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setFixedSize(50, 30)
        self.setVisible(False)

        # Create animation
        self.animation = QPropertyAnimation(self, b"opacity")
        self.animation.setDuration(1000)
        self.animation.setStartValue(0.5)
        self.animation.setEndValue(1.0)
        self.animation.setLoopCount(-1)  # Infinite loop
        self.animation.setEasingCurve(QEasingCurve.Type.InOutQuad)

    def start_animation(self):
        """Start the animation"""
        self.setVisible(True)
        self.animation.start()

    def stop_animation(self):
        """Stop the animation"""
        self.animation.stop()
        self.setVisible(False)

    def set_opacity(self, opacity):
        """Set the opacity of the widget"""
        # Check if we're on the main thread
        if QThread.currentThread() is QApplication.instance().thread():
            # If we're on the main thread, set the effect directly
            opacity_effect = QGraphicsOpacityEffect(self)
            opacity_effect.setOpacity(opacity)
            self.setGraphicsEffect(opacity_effect)
        else:
            # If we're not on the main thread, use QTimer.singleShot to ensure thread safety
            QTimer.singleShot(0, lambda op=opacity: self._set_opacity_main_thread(op))

    def _set_opacity_main_thread(self, opacity):
        """Set the opacity of the widget on the main thread"""
        opacity_effect = QGraphicsOpacityEffect(self)
        opacity_effect.setOpacity(opacity)
        self.setGraphicsEffect(opacity_effect)

    # Property for animation
    opacity = pyqtProperty(float, fset=set_opacity)


class AsyncWorker(QThread):
    """Worker thread for running async operations"""

    result_ready = pyqtSignal(object)
    error_occurred = pyqtSignal(str)

    # Add signals for UI updates
    start_loading_signal = pyqtSignal(str)
    stop_loading_signal = pyqtSignal()

    def __init__(self, coro, main_window=None, loading_message="Loading data..."):
        super().__init__()
        self.coro = coro
        self.main_window = main_window
        self.loading_message = loading_message
        self.result = None
        self.error = None
        self.future = None

        # Connect signals to UI update methods if main_window is provided
        if main_window:
            # Use Qt.ConnectionType.QueuedConnection to ensure thread safety
            self.start_loading_signal.connect(
                main_window._start_loading_direct, Qt.ConnectionType.QueuedConnection
            )
            self.stop_loading_signal.connect(
                main_window._stop_loading_direct, Qt.ConnectionType.QueuedConnection
            )

    def emit_start_loading(self, message: str = "Loading..."):
        """Emit signal to start loading indicator"""
        self.start_loading_signal.emit(message)

    def emit_stop_loading(self):
        """Emit signal to stop loading indicator"""
        self.stop_loading_signal.emit()

    def run(self):
        try:
            # Show loading indicator automatically when starting the coroutine
            self.emit_start_loading(self.loading_message)

            # Get the main event loop from the main window
            main_window = self.main_window or QApplication.instance().activeWindow()
            if main_window and hasattr(main_window, "_async_loop"):
                loop = main_window._async_loop
                try:
                    # Run the coroutine directly in the main async loop
                    # This avoids creating a new event loop for each worker
                    self.future = asyncio.run_coroutine_threadsafe(self.coro, loop)

                    # Wait for the future to complete with a timeout
                    # This prevents blocking indefinitely if the coroutine hangs
                    try:
                        self.result = self.future.result(
                            timeout=60.0
                        )  # 60 second timeout
                        self.result_ready.emit(self.result)
                    except concurrent.futures.TimeoutError:
                        logger.error("Async operation timed out after 60 seconds")
                        self.error = "Operation timed out after 60 seconds"
                        self.error_occurred.emit(self.error)
                        # Cancel the future to prevent it from continuing to run
                        self.future.cancel()

                except asyncio.CancelledError:
                    logger.warning("Async operation was cancelled")
                    self.error = "Operation was cancelled"
                    self.error_occurred.emit(self.error)
                except Exception as e:
                    logger.error(f"Error in async worker: {str(e)}")
                    self.error = str(e)
                    self.error_occurred.emit(self.error)
            else:
                # Fallback to creating a new event loop if main loop not available
                # This should be avoided if possible as it can lead to event loop conflicts
                logger.warning("Main async loop not available - using fallback method")
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    self.result = loop.run_until_complete(self.coro)
                    self.result_ready.emit(self.result)
                except Exception as e:
                    logger.error(f"Error in async worker fallback: {str(e)}")
                    self.error = str(e)
                    self.error_occurred.emit(self.error)
                finally:
                    loop.close()
        except Exception as e:
            logger.error(f"Error in async worker: {str(e)}")
            self.error = str(e)
            self.error_occurred.emit(self.error)
        finally:
            # Stop loading indicator automatically when the coroutine is done
            self.emit_stop_loading()


class MainWindow(QMainWindow):
    """Main application window"""

    def __init__(self, server_url: str = None):
        super().__init__()

        # Load configuration
        self.config = get_config()
        self.config_manager = get_config_manager()

        # Use configured server URL if not provided
        if server_url is None:
            server_url = self.config.server_url

        self.server_url = server_url
        self.api_client = CachedApiClient(
            server_url, cache_timeout=self.config.cache_timeout
        )
        self.loading_count = 0
        self.selected_preset: Optional[Preset] = None
        self.selected_midi_out_port: Optional[str] = None
        self.selected_sequencer_port: Optional[str] = None
        self.selected_midi_channel: int = self.config.default_midi_channel
        self.selected_manufacturer: Optional[str] = None
        self.selected_device: Optional[str] = None
        self.selected_community_folder: Optional[str] = None
        self.sync_enabled: bool = True
        self.server_available = False
        self.server_check_retries = 0
        self.max_server_check_retries = self.config.server_check_retries

        # Flag to track if a refresh operation is in progress
        self._refresh_in_progress = False

        # List to keep references to active worker threads
        self._active_workers = []

        # Set up a dedicated thread with an event loop for async operations
        self._async_loop = None
        self._async_thread = None
        self._setup_async_loop()

        # Set up the UI
        self.initUI()

        # Set up keyboard shortcuts if enabled
        if self.config.enable_keyboard_shortcuts:
            self.setup_shortcuts()

        # Apply configuration
        self.apply_configuration()

        # Add a small delay before scheduling async tasks to ensure the async loop is fully ready
        # This helps prevent threading issues with Qt objects

        # Run git sync if enabled - with a delay to ensure async loop is ready
        if self.sync_enabled:
            QTimer.singleShot(500, lambda: self.run_async_task(self.run_git_sync()))

        # Wait for server to be available before loading data - with a delay to ensure async loop is ready
        QTimer.singleShot(1000, self.wait_for_server)

    def _setup_async_loop(self):
        """Set up a dedicated thread with an event loop for async operations"""
        # Create an event to signal when the loop is ready
        loop_ready = threading.Event()

        def run_loop():
            try:
                # Create a new event loop
                self._async_loop = asyncio.new_event_loop()

                # Set the event loop policy to prevent conflicts
                asyncio.set_event_loop(self._async_loop)

                # Set a larger default timeout for futures
                self._async_loop.set_default_executor(
                    concurrent.futures.ThreadPoolExecutor(max_workers=4)
                )

                # Signal that the loop is ready
                loop_ready.set()

                # Run the event loop forever
                self._async_loop.run_forever()
            except Exception as e:
                logger.error(f"Error in async loop thread: {str(e)}")
            finally:
                # Clean up the loop when it's done
                if self._async_loop and self._async_loop.is_running():
                    self._async_loop.stop()
                if self._async_loop and not self._async_loop.is_closed():
                    self._async_loop.close()
                logger.info("Async loop thread exiting")

        # Create and start the thread
        self._async_thread = threading.Thread(
            target=run_loop, daemon=True, name="AsyncLoopThread"
        )
        self._async_thread.start()

        # Wait for the loop to be ready, with a timeout
        # This ensures that the async loop is properly initialized before it's used
        # which prevents Qt threading violations
        if not loop_ready.wait(
            timeout=5.0
        ):  # Increased timeout for even slower systems
            logger.warning("Async loop thread may not have started properly")

        logger.info("Async loop thread started")

    def _remove_worker(self, worker):
        """Remove a worker from the active workers list"""
        if worker in self._active_workers:
            self._active_workers.remove(worker)
            logger.debug(
                f"Worker removed, {len(self._active_workers)} workers remaining"
            )

    def run_async_task(
        self,
        coro: Coroutine,
        callback=None,
        error_callback=None,
        loading_message="Loading data...",
    ) -> None:
        """
        Run an async coroutine in the dedicated async thread

        Args:
            coro: The coroutine to run
            callback: Optional callback to run with the result
            error_callback: Optional callback to run on error
            loading_message: Optional message to display in the loading indicator
        """
        # Check if we have a valid async loop
        if not self._async_loop or self._async_loop.is_closed():
            error_msg = "Async loop is not available or is closed"
            logger.error(error_msg)
            if error_callback:
                error_callback(error_msg)
            else:
                self.show_error(f"Error: {error_msg}")
            return

        # Limit the number of concurrent workers to prevent overload
        if len(self._active_workers) > 10:  # Arbitrary limit, adjust as needed
            logger.warning(
                f"Too many active workers ({len(self._active_workers)}), delaying new task"
            )
            # Use a timer to retry after a short delay
            QTimer.singleShot(
                500,
                lambda: self.run_async_task(
                    coro, callback, error_callback, loading_message
                ),
            )
            return

        try:
            # Create a worker using QThread instead of a regular Python thread
            worker = AsyncWorker(
                coro, main_window=self, loading_message=loading_message
            )

            # Connect signals with QueuedConnection to ensure thread safety
            if callback:
                worker.result_ready.connect(
                    lambda result: callback(result), Qt.ConnectionType.QueuedConnection
                )

            # Connect error signal with QueuedConnection
            if error_callback:
                worker.error_occurred.connect(
                    lambda error: error_callback(error),
                    Qt.ConnectionType.QueuedConnection,
                )
            else:
                worker.error_occurred.connect(
                    lambda error: self.show_error(f"Error: {error}"),
                    Qt.ConnectionType.QueuedConnection,
                )

            # Connect finished signal to remove worker from active workers list
            worker.finished.connect(
                lambda: self._remove_worker(worker), Qt.ConnectionType.QueuedConnection
            )

            # Add to active workers list to prevent garbage collection
            self._active_workers.append(worker)
            logger.debug(
                f"Added worker, now {len(self._active_workers)} active workers"
            )

            # Start the worker thread
            worker.start()
        except Exception as e:
            logger.error(f"Error creating async worker: {str(e)}")
            if error_callback:
                error_callback(str(e))
            else:
                self.show_error(f"Error creating async worker: {str(e)}")

    def setup_shortcuts(self):
        """Set up keyboard shortcuts"""
        self.shortcut_manager = ShortcutManager(self)

        # Connect shortcut signals
        self.shortcut_manager.send_preset.connect(self.on_send_button_clicked)
        self.shortcut_manager.search_focus.connect(self.focus_search)
        self.shortcut_manager.clear_search.connect(self.clear_search)
        self.shortcut_manager.toggle_favorites.connect(self.toggle_favorites_filter)
        self.shortcut_manager.refresh_data.connect(self.refresh_all_data)
        self.shortcut_manager.quit_app.connect(self.close)
        self.shortcut_manager.show_preferences.connect(self.show_preferences)

        # Navigation
        self.shortcut_manager.next_preset.connect(self.select_next_preset)
        self.shortcut_manager.previous_preset.connect(self.select_previous_preset)
        self.shortcut_manager.next_category.connect(self.select_next_category)
        self.shortcut_manager.previous_category.connect(self.select_previous_category)

        # MIDI control
        self.shortcut_manager.midi_channel_up.connect(self.increment_midi_channel)
        self.shortcut_manager.midi_channel_down.connect(self.decrement_midi_channel)

        logger.info("Keyboard shortcuts configured")

    def apply_configuration(self):
        """Apply configuration settings"""
        # Set window size
        self.resize(self.config.window_width, self.config.window_height)

        # Set debug logging if enabled
        if self.config.debug_mode:
            logging.getLogger().setLevel(getattr(logging, self.config.log_level))

        # Allow user to choose theme
        # self.config.dark_mode = False  # Commented out to allow user preference

        # Apply theme
        app = QApplication.instance()
        if app:
            ThemeManager.apply_theme(app, self.config.dark_mode)

        # Start performance monitoring if in debug mode
        if self.config.debug_mode:
            monitor = get_monitor()
            # Just mark as monitoring, the actual async task will be started later
            monitor.start_monitoring(interval=2.0)
            # Start the async monitoring task using the dedicated async thread
            self.run_async_task(monitor.start_monitoring_async(interval=2.0))

    def initUI(self):
        """Initialize the UI components"""
        # Set window properties
        self.setWindowTitle("r2midi")
        self.setMinimumSize(800, 600)

        # Create central widget and layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        main_layout = QVBoxLayout()
        central_widget.setLayout(main_layout)

        # Create a splitter for resizable panels
        splitter = QSplitter(Qt.Orientation.Vertical)
        main_layout.addWidget(splitter)

        # Device panel (top)
        self.device_panel = DevicePanel(api_client=self.api_client, main_window=self)
        splitter.addWidget(self.device_panel)

        # Connect device panel signals
        self.device_panel.manufacturer_changed.connect(self.on_manufacturer_changed)
        self.device_panel.device_changed.connect(self.on_device_changed)
        self.device_panel.community_folder_changed.connect(
            self.on_community_folder_changed
        )
        self.device_panel.midi_out_port_changed.connect(self.on_midi_out_port_changed)
        self.device_panel.sequencer_port_changed.connect(self.on_sequencer_port_changed)
        self.device_panel.midi_channel_changed.connect(self.on_midi_channel_changed)
        self.device_panel.sync_changed.connect(self.on_sync_changed)

        # Preset panel (bottom)
        self.preset_panel = PresetPanel()
        splitter.addWidget(self.preset_panel)

        # Connect preset panel signals
        self.preset_panel.preset_selected.connect(self.on_preset_selected)
        self.preset_panel.preset_double_clicked.connect(self.on_preset_double_clicked)

        # Set initial splitter sizes (30% top, 70% bottom)
        splitter.setSizes([300, 700])

        # Button layout
        button_layout = QHBoxLayout()

        # Send button
        self.send_button = QPushButton("Send MIDI")
        self.send_button.setToolTip(
            "Send the selected preset to the MIDI device (Enter)"
        )
        self.send_button.clicked.connect(self.on_send_button_clicked)
        button_layout.addWidget(self.send_button)

        # Refresh button
        self.refresh_button = QPushButton("Refresh")
        self.refresh_button.setToolTip("Refresh all data (F5)")
        self.refresh_button.clicked.connect(self.refresh_all_data)
        button_layout.addWidget(self.refresh_button)

        # Preferences button
        self.preferences_button = QPushButton("Preferences")
        self.preferences_button.setToolTip("Open preferences (Ctrl+,)")
        self.preferences_button.clicked.connect(self.show_preferences)
        button_layout.addWidget(self.preferences_button)

        # Edit button
        self.edit_button = QPushButton("Edit")
        self.edit_button.setToolTip("Edit manufacturers, devices, and presets")
        self.edit_button.clicked.connect(self.show_edit_dialog)
        button_layout.addWidget(self.edit_button)

        # Devices Remote GitHub Sync button
        self.git_remote_sync_button = QPushButton("Pull Presets from GitHub")
        self.git_remote_sync_button.setToolTip(
            "Pull the latest changes from the midi-presets GitHub repo"
        )
        self.git_remote_sync_button.clicked.connect(
            self.on_git_remote_sync_button_clicked
        )
        button_layout.addWidget(self.git_remote_sync_button)

        button_layout.addStretch()
        main_layout.addLayout(button_layout)

        # Status bar with progress indicator
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("Ready")

        # Add progress bar to status bar
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        self.progress_bar.setMaximumWidth(200)
        self.status_bar.addPermanentWidget(self.progress_bar)

        # Loading label
        self.loading_label = QLabel("")
        self.loading_label.setVisible(False)
        self.status_bar.addPermanentWidget(self.loading_label)

        # WIP animation
        self.wip_animation = WIPAnimation(self)
        self.wip_animation.setGeometry(10, 10, 50, 30)  # Position in top-left corner

    def _set_status_bar_loading_style(self, is_loading: bool):
        """Set the status bar style for loading state"""
        if is_loading:
            # Light red background for loading state
            self.status_bar.setStyleSheet("background-color: #ffcccc; color: #990000;")
        else:
            # Reset to default style
            self.status_bar.setStyleSheet("")

    def _start_loading_direct(self, message: str = "Loading..."):
        """Start loading indicator directly on the main thread"""
        self.loading_count += 1
        self.progress_bar.setRange(0, 0)  # Indeterminate progress
        self.progress_bar.setVisible(True)
        self.loading_label.setText(message)
        self.loading_label.setVisible(True)
        self.status_bar.showMessage(message)
        # Set loading style
        self._set_status_bar_loading_style(True)
        # Start WIP animation
        self.wip_animation.start_animation()

    def _stop_loading_direct(self):
        """Stop loading indicator directly on the main thread"""
        self.loading_count = max(0, self.loading_count - 1)
        if self.loading_count == 0:
            self.progress_bar.setVisible(False)
            self.loading_label.setVisible(False)
            self.progress_bar.setRange(0, 100)
            self.progress_bar.setValue(0)
            # Reset loading style
            self._set_status_bar_loading_style(False)
            # Stop WIP animation
            self.wip_animation.stop_animation()

    def _start_loading(self, message: str = "Loading..."):
        """Start loading indicator - safe to call from any thread"""
        # Check if we're on the main thread
        if QThread.currentThread() is QApplication.instance().thread():
            # If we're on the main thread, call the direct method
            self._start_loading_direct(message)
        else:
            # If we're not on the main thread, always use QTimer.singleShot
            # This is the most reliable way to ensure the method is called on the main thread
            # We don't need to search for the worker thread anymore
            QTimer.singleShot(0, lambda msg=message: self._start_loading_direct(msg))

    def _stop_loading(self):
        """Stop loading indicator - safe to call from any thread"""
        # Check if we're on the main thread
        if QThread.currentThread() is QApplication.instance().thread():
            # If we're on the main thread, call the direct method
            self._stop_loading_direct()
        else:
            # If we're not on the main thread, always use QTimer.singleShot
            # This is the most reliable way to ensure the method is called on the main thread
            # We don't need to search for the worker thread anymore
            QTimer.singleShot(0, self._stop_loading_direct)

    # Shortcut actions
    def focus_search(self):
        """Focus the search input"""
        if hasattr(self.preset_panel, "search_input"):
            self.preset_panel.search_input.setFocus()
            self.preset_panel.search_input.selectAll()

    def clear_search(self):
        """Clear the search input"""
        if hasattr(self.preset_panel, "clear_search"):
            self.preset_panel.clear_search()

    def toggle_favorites_filter(self):
        """Toggle favorites filter"""
        if hasattr(self.preset_panel, "favorites_checkbox"):
            current = self.preset_panel.favorites_checkbox.isChecked()
            self.preset_panel.favorites_checkbox.setChecked(not current)

    def refresh_all_data(self):
        """Refresh all data from server"""
        # Check if a refresh operation is already in progress
        if self._refresh_in_progress:
            logger.info("Refresh operation already in progress, ignoring request")
            self.status_bar.showMessage(
                "Refresh already in progress, please wait...", 3000
            )
            return

        logger.info("Refreshing all data...")

        # Set the flag to indicate a refresh operation is in progress
        self._refresh_in_progress = True

        # Disable the refresh button to prevent multiple clicks
        if hasattr(self, "refresh_button"):
            self.refresh_button.setEnabled(False)

        # Clear cache
        self.api_client.clear_cache()

        # Define a callback to reset the flag when the operation is complete
        def on_refresh_complete(*args):
            logger.info("Refresh operation completed")
            self._refresh_in_progress = False
            # Re-enable the refresh button
            if hasattr(self, "refresh_button"):
                self.refresh_button.setEnabled(True)

        def on_refresh_error(error):
            logger.error(f"Error during refresh: {error}")
            self._refresh_in_progress = False
            # Re-enable the refresh button
            if hasattr(self, "refresh_button"):
                self.refresh_button.setEnabled(True)
            self.status_bar.showMessage(f"Refresh failed: {error}", 5000)

        # Reload data with callbacks
        try:
            # Use run_async_task directly with the _load_data_async coroutine
            self.run_async_task(
                self._load_data_async(),
                callback=on_refresh_complete,
                error_callback=on_refresh_error,
                loading_message="Refreshing data from server...",
            )
        except Exception as e:
            logger.error(f"Error starting refresh: {str(e)}")
            self._refresh_in_progress = False
            # Re-enable the refresh button
            if hasattr(self, "refresh_button"):
                self.refresh_button.setEnabled(True)
            self.status_bar.showMessage(f"Refresh failed: {str(e)}", 5000)

    def show_preferences(self):
        """Show preferences dialog"""
        dialog = PreferencesDialog(self)
        dialog.preferences_saved.connect(self.on_preferences_saved)
        dialog.exec()

    def show_edit_dialog(self):
        """Show edit dialog for manufacturers, devices, and presets"""
        dialog = EditDialog(self.api_client, self)
        dialog.changes_made.connect(self.refresh_all_data)
        dialog.exec()

    def on_preferences_saved(self):
        """Handle preferences saved"""
        # Reload configuration
        self.config = get_config()

        # Update API client cache timeout
        self.api_client._cache_timeout = self.config.cache_timeout

        # Update shortcuts
        if hasattr(self, "shortcut_manager"):
            self.shortcut_manager.set_enabled(self.config.enable_keyboard_shortcuts)

        # Apply theme change
        app = QApplication.instance()
        if app:
            ThemeManager.apply_theme(app, self.config.dark_mode)

        # Apply other configuration changes
        self.apply_configuration()

        # Show message
        self.status_bar.showMessage("Preferences saved", 3000)

    def select_next_preset(self):
        """Select next preset in list"""
        if hasattr(self.preset_panel, "preset_list"):
            current = self.preset_panel.preset_list.currentRow()
            if current < self.preset_panel.preset_list.count() - 1:
                self.preset_panel.preset_list.setCurrentRow(current + 1)
                item = self.preset_panel.preset_list.currentItem()
                if item:
                    self.preset_panel.on_preset_clicked(item)

    def select_previous_preset(self):
        """Select previous preset in list"""
        if hasattr(self.preset_panel, "preset_list"):
            current = self.preset_panel.preset_list.currentRow()
            if current > 0:
                self.preset_panel.preset_list.setCurrentRow(current - 1)
                item = self.preset_panel.preset_list.currentItem()
                if item:
                    self.preset_panel.on_preset_clicked(item)

    def select_next_category(self):
        """Select next category"""
        if hasattr(self.preset_panel, "category_combo"):
            current = self.preset_panel.category_combo.currentIndex()
            if current < self.preset_panel.category_combo.count() - 1:
                self.preset_panel.category_combo.setCurrentIndex(current + 1)

    def select_previous_category(self):
        """Select previous category"""
        if hasattr(self.preset_panel, "category_combo"):
            current = self.preset_panel.category_combo.currentIndex()
            if current > 0:
                self.preset_panel.category_combo.setCurrentIndex(current - 1)

    def increment_midi_channel(self):
        """Increment MIDI channel"""
        if self.selected_midi_channel < 16:
            self.selected_midi_channel += 1
            self.device_panel.channel_spin.setValue(self.selected_midi_channel)

    def decrement_midi_channel(self):
        """Decrement MIDI channel"""
        if self.selected_midi_channel > 1:
            self.selected_midi_channel -= 1
            self.device_panel.channel_spin.setValue(self.selected_midi_channel)

    async def _load_data_async(self):
        """Load data from the server asynchronously"""
        # Monitor performance
        with PerformanceContext(get_monitor(), "load_data"):
            # Show loading message immediately
            self._start_loading("Loading data from server...")

            # Check if server is available
            if not self.server_available:
                logger.warning("Server is not available, cannot load data")
                self.status_bar.showMessage("Server is not available, cannot load data")
                # Try to check server availability again
                available = await self.check_server_availability()
                if not available:
                    logger.error("Server is still not available, aborting data loading")
                    self.status_bar.showMessage(
                        "Server is not available, aborting data loading"
                    )
                    self.show_error(
                        "Server is not available. Please check your connection and try again."
                    )
                    self._stop_loading()
                    return
                else:
                    # Server is now available, update flag
                    self.server_available = True
                    logger.info("Server is now available, continuing with data loading")
                    self.status_bar.showMessage(
                        "Server is now available, continuing with data loading"
                    )

            try:
                # Load manufacturers first
                logger.info("Loading manufacturers from server...")
                manufacturers = await self.api_client.get_manufacturers()
                logger.info(
                    f"Loaded {len(manufacturers)} manufacturers: {manufacturers}"
                )

                if not manufacturers:
                    logger.warning(
                        "No manufacturers found, UI dropdowns may not display correctly"
                    )
                    self.status_bar.showMessage("Warning: No manufacturers found")
                    self._stop_loading()
                    return

                # Set manufacturers in the device panel immediately - no QTimer delay
                logger.info("Setting manufacturers in device panel...")
                self.device_panel.set_manufacturers(manufacturers)
                logger.info("Manufacturers set successfully")

                # Load MIDI ports
                logger.info("Loading MIDI ports from server...")
                midi_ports = await self.api_client.get_midi_ports()
                logger.info(
                    f"Loaded MIDI ports: in={len(midi_ports.get('in', []))}, out={len(midi_ports.get('out', []))}"
                )

                # Set MIDI ports in the device panel immediately
                self.device_panel.set_midi_ports(midi_ports)
                logger.info("MIDI ports set successfully")

                # Get the selected manufacturer and trigger device load if available
                manufacturer = self.device_panel.get_selected_manufacturer()
                logger.info(f"Selected manufacturer after loading: {manufacturer}")

                if manufacturer:
                    logger.info(
                        f"Triggering device load for manufacturer: {manufacturer}"
                    )
                    # Trigger manufacturer changed to load devices
                    # Use a proper async approach instead of sleep
                    await self.load_devices_for_manufacturer(manufacturer)

                # Load UI state after manufacturers and devices are loaded
                logger.info("Loading UI state after manufacturers and devices...")
                self.device_panel.load_ui_state()
                logger.info("UI state loaded successfully")

                # Load presets based on selected device and community folder
                logger.info(
                    "Loading presets based on selected device and community folder..."
                )
                await self.load_presets()

                # Update status
                self.status_bar.showMessage("presets loaded")
            except Exception as e:
                logger.error(f"Error loading data: {str(e)}")
                self.status_bar.showMessage(f"Error loading data: {str(e)}")
                self.show_error(f"Error loading data: {str(e)}")
            finally:
                # Stop loading indicator immediately
                self._stop_loading()

    async def load_presets(self):
        """Load presets based on selected manufacturer, device, and community folder"""
        # Monitor performance
        with PerformanceContext(get_monitor(), "load_presets"):
            # Start loading indicator immediately
            self._start_loading("Loading presets...")

            # Check if server is available
            if not self.server_available:
                logger.warning("Server is not available, cannot load presets")
                self.status_bar.showMessage(
                    "Server is not available, cannot load presets"
                )
                # Try to check server availability again
                available = await self.check_server_availability()
                if not available:
                    logger.error(
                        "Server is still not available, aborting preset loading"
                    )
                    self.status_bar.showMessage(
                        "Server is not available, aborting preset loading"
                    )
                    # Still set empty presets to clear any previous data
                    self.preset_panel.set_presets([])
                    self._stop_loading()
                    return
                else:
                    # Server is now available, update flag
                    self.server_available = True
                    logger.info(
                        "Server is now available, continuing with preset loading"
                    )
                    self.status_bar.showMessage(
                        "Server is now available, continuing with preset loading"
                    )

            try:
                manufacturer = self.device_panel.get_selected_manufacturer()
                device = self.device_panel.get_selected_device()
                community_folder = self.device_panel.get_selected_community_folder()

                logger.info(
                    f"Loading presets for manufacturer: {manufacturer}, device: {device}, community folder: {community_folder}"
                )

                if not manufacturer or not device:
                    logger.info(
                        "No manufacturer or device selected, showing empty preset list"
                    )
                    self.status_bar.showMessage(
                        "Please select a manufacturer and device to load presets"
                    )
                    # Set empty presets to clear any previous data
                    presets = []
                else:
                    # Load presets based on selected manufacturer, device, and community folder
                    presets = await self.api_client.get_presets(
                        device, community_folder, manufacturer
                    )

                logger.info(f"Loaded {len(presets)} presets")

                # Set presets in the preset panel immediately
                self.preset_panel.set_presets(presets)

                # Update status
                if manufacturer and device:
                    self.status_bar.showMessage(
                        f"Loaded {len(presets)} presets for {manufacturer} {device}"
                    )
                elif manufacturer:
                    self.status_bar.showMessage(
                        f"Loaded {len(presets)} presets for {manufacturer}"
                    )
                elif device:
                    self.status_bar.showMessage(
                        f"Loaded {len(presets)} presets for {device}"
                    )
                else:
                    self.status_bar.showMessage(
                        "Please select a manufacturer and device to load presets"
                    )
            except Exception as e:
                logger.error(f"Error loading presets: {str(e)}")
                self.status_bar.showMessage(f"Error loading presets: {str(e)}")
                # Set empty presets on error to clear any previous data
                self.preset_panel.set_presets([])
            finally:
                # Stop loading indicator immediately
                self._stop_loading()

    async def run_git_sync(self):
        """Run git submodule sync if enabled"""
        if not self.sync_enabled:
            logger.info("Sync is disabled, skipping git sync")
            return

        # Monitor performance
        with PerformanceContext(get_monitor(), "run_git_sync"):
            # Start loading indicator immediately
            self._start_loading("Running git sync...")

            # Check if server is available
            if not self.server_available:
                logger.info("Server is not available, skipping git sync")
                self.status_bar.showMessage(
                    "Server is not available, skipping git sync"
                )
                # Don't show an error, just quietly skip the git sync
                self._stop_loading()
                return

            try:
                logger.info("Running git sync...")
                self.status_bar.showMessage("Running git sync...")

                # Pass the sync_enabled parameter to the API client
                success, message = await self.api_client.run_git_sync(
                    sync_enabled=self.sync_enabled
                )

                # Update status bar with result
                if success:
                    logger.info("Git sync completed successfully")
                    self.status_bar.showMessage("Git sync completed successfully")
                else:
                    logger.warning(f"Git sync failed: {message}")
                    self.status_bar.showMessage(f"Git sync failed: {message}")
                    # Don't show an error dialog for git sync failures
                    # Just log it and show in the status bar
            except Exception as e:
                logger.warning(f"Error during git sync: {str(e)}")
                self.status_bar.showMessage(f"Error during git sync: {str(e)}")
                # Don't show an error dialog for git sync exceptions
            finally:
                # Stop loading indicator immediately
                self._stop_loading()

    def on_git_remote_sync_button_clicked(self):
        """Handle Devices Remote GitHub Sync button click"""
        try:
            # Check if sync is enabled
            if not self.sync_enabled:
                logger.info("Sync is disabled, skipping git sync")
                QMessageBox.information(
                    self,
                    "Sync Disabled",
                    "Sync is disabled. Please disable off-line mode to use this feature.",
                )
                return

            # Log at INFO level to ensure it's captured
            logger.info("SYNC BUTTON PRESSED: Pull Presets from GitHub button clicked")

            # Start loading indicator
            self._start_loading("Pulling presets from GitHub...")

            # Use the API client's run_git_sync method instead of run_git_remote_sync
            def on_sync_complete(result):
                success, message = result
                logger.info(f"Git sync completed: success={success}, message={message}")

                # Update status bar
                self.status_bar.showMessage(message)

                # Stop loading indicator immediately
                self._stop_loading()

                # Show message to user
                try:
                    if success:
                        QMessageBox.information(self, "Success", message)
                    else:
                        QMessageBox.warning(self, "Warning", message)
                except Exception as dialog_error:
                    logger.error(f"Failed to show dialog: {str(dialog_error)}")

            # Run the API client's run_git_sync method asynchronously
            self.run_async_task(
                self.api_client.run_git_sync(sync_enabled=self.sync_enabled),
                callback=on_sync_complete,
                loading_message="Pulling presets from GitHub...",
            )

        except Exception as e:
            # Log any exceptions that occur
            error_msg = f"SYNC BUTTON ERROR: {str(e)}"
            logger.error(error_msg)
            logger.error(f"Exception type: {type(e).__name__}")
            logger.error(f"Traceback: {traceback.format_exc()}")

            # Show an error message to the user
            try:
                QMessageBox.critical(self, "Error", error_msg)
            except Exception as dialog_error:
                logger.error(f"Failed to show error dialog: {str(dialog_error)}")

            # Stop loading indicator if it was started
            try:
                self._stop_loading()
            except Exception as stop_error:
                logger.error(f"Failed to stop loading indicator: {str(stop_error)}")

    # The async version of run_git_remote_sync has been replaced by a direct QThread implementation
    # in the on_git_remote_sync_button_clicked method

    async def check_server_availability(self) -> bool:
        """
        Check if the server is available by querying the manufacturers endpoint

        Returns:
            True if the server is available, False otherwise
        """
        try:
            logger.info("Checking server availability...")
            self.status_bar.showMessage("Checking server availability...")

            # Try to get manufacturers from the server
            manufacturers = await self.api_client.get_manufacturers()

            # If we get a response, the server is available
            if manufacturers is not None:
                logger.info("Server is available")
                self.status_bar.showMessage("Server is available")
                return True
            else:
                logger.info("Server is not available (no manufacturers returned)")
                self.status_bar.showMessage(
                    "Server is not available (no manufacturers returned)"
                )
                return False

        except Exception as e:
            logger.error(f"Error checking server availability: {str(e)}")
            self.status_bar.showMessage(f"Error checking server availability: {str(e)}")
            return False

    async def load_devices_for_manufacturer(self, manufacturer: str):
        """
        Load devices for a specific manufacturer asynchronously

        This replaces the sleep workaround with a proper async implementation
        that waits for devices to be loaded before proceeding.

        Args:
            manufacturer: The manufacturer to load devices for
        """
        try:
            logger.info(f"Loading devices for manufacturer: {manufacturer}")

            # Trigger the manufacturer changed event to load devices
            # This already fetches devices asynchronously, so we don't need to fetch them again
            self.device_panel.on_manufacturer_changed(manufacturer)

            # Wait a short time to allow the device panel to start its async operation
            await asyncio.sleep(0.1)

            # Return an empty list as the actual loading is handled by the device panel
            # The caller doesn't actually use the returned devices
            return []

        except Exception as e:
            logger.error(
                f"Error loading devices for manufacturer {manufacturer}: {str(e)}"
            )
            return []

    def wait_for_server(self):
        """
        Wait for the server to be available before loading data

        This method will repeatedly check if the server is available and
        only proceed with loading data once the server is confirmed available.
        It will timeout after max_server_check_retries attempts.
        """
        logger.info("Waiting for server to be available...")
        self.status_bar.showMessage("Waiting for server to be available...")

        # Check if we've exceeded the maximum number of retries
        if self.server_check_retries >= self.max_server_check_retries:
            logger.error(
                f"Server not available after {self.server_check_retries} retries, giving up"
            )
            self.status_bar.showMessage("Server not available, giving up")
            self.show_error(
                f"Server not available after {self.server_check_retries} retries. Please check your connection and restart the application."
            )
            # Even if server is not available, proceed with loading UI
            # This allows the user to see the UI and potentially retry later
            self.server_available = False
            self.load_data()
            return

        # Increment retry counter
        self.server_check_retries += 1

        # Check if the server is available
        def on_check_complete(available):
            if available:
                logger.info("Server is available, loading data...")
                self.server_available = True
                self.status_bar.showMessage("Server is available, loading data...")
                # Reset retry counter
                self.server_check_retries = 0
                # Now that the server is available, load data
                self.load_data()
            else:
                logger.info(
                    f"Server is not available (retry {self.server_check_retries}/{self.max_server_check_retries}), retrying in 1 second..."
                )
                self.status_bar.showMessage(
                    f"Server is not available (retry {self.server_check_retries}/{self.max_server_check_retries}), retrying in 1 second..."
                )
                # Retry after 1 second
                QTimer.singleShot(1000, self.wait_for_server)

        # Run the check asynchronously
        self.run_async_task(
            self.check_server_availability(), callback=on_check_complete
        )

    def load_data(self):
        """Load data from the server"""
        logger.info("Loading data from the server")

        # Define a callback to handle errors
        def on_load_error(error):
            logger.error(f"Error loading data: {error}")
            self.status_bar.showMessage(f"Error loading data: {error}", 5000)

        # Use run_async_task with error callback
        self.run_async_task(
            self._load_data_async(),
            error_callback=on_load_error,
            loading_message="Loading data from server...",
        )

    def on_manufacturer_changed(self, manufacturer: str):
        """Handle manufacturer selection change"""
        self.selected_manufacturer = manufacturer
        self.status_bar.showMessage(f"Selected manufacturer: {manufacturer}")
        logger.info(f"Manufacturer changed to: {manufacturer}")

    def on_device_changed(self, device: str):
        """Handle device selection change"""
        self.selected_device = device
        self.status_bar.showMessage(f"Selected device: {device}")
        logger.info(f"Device changed to: {device}")

        # Load presets for the selected device
        self.reload_presets()

    def on_community_folder_changed(self, folder: str):
        """Handle community folder selection change"""
        if folder == "Default":
            self.selected_community_folder = None
            self.status_bar.showMessage(f"Selected community folder: Default")
            logger.info("Community folder changed to: Default")
        else:
            self.selected_community_folder = folder
            self.status_bar.showMessage(f"Selected community folder: {folder}")
            logger.info(f"Community folder changed to: {folder}")

        # Load presets for the selected device and community folder
        self.reload_presets()

    def on_sync_changed(self, enabled: bool):
        """Handle sync checkbox state change"""
        self.sync_enabled = enabled
        logger.info(f"Sync changed to: {enabled}")

    def reload_presets(self):
        """Reload presets based on selected manufacturer, device, and community folder"""
        # Check if server is available
        if not self.server_available:
            logger.warning("Server is not available, cannot reload presets")
            self.status_bar.showMessage(
                "Server is not available, cannot reload presets"
            )

            # Try to check server availability again
            def on_check_complete(available):
                if available:
                    logger.info("Server is now available, reloading presets...")
                    self.server_available = True
                    self.status_bar.showMessage(
                        "Server is now available, reloading presets..."
                    )
                    # Now that the server is available, reload presets
                    self._do_reload_presets()
                else:
                    logger.error(
                        "Server is still not available, aborting preset reload"
                    )
                    self.status_bar.showMessage(
                        "Server is not available, aborting preset reload"
                    )

            # Run the check asynchronously
            self.run_async_task(
                self.check_server_availability(), callback=on_check_complete
            )
        else:
            # Server is available, proceed with reloading presets
            self._do_reload_presets()

    def _do_reload_presets(self):
        """Internal method to reload presets after server availability check"""
        try:
            manufacturer = self.device_panel.get_selected_manufacturer()
            device = self.device_panel.get_selected_device()
            community_folder = self.device_panel.get_selected_community_folder()

            logger.info(
                f"Reloading presets for manufacturer: {manufacturer}, device: {device}, community folder: {community_folder}"
            )
            self.status_bar.showMessage(f"Reloading presets...")

            # Run the load_presets method asynchronously
            self.run_async_task(self.load_presets())
        except Exception as e:
            logger.error(f"Error reloading presets: {str(e)}")
            self.status_bar.showMessage(f"Error reloading presets: {str(e)}")

    def on_preset_selected(self, preset: Preset):
        """Handle preset selection"""
        self.selected_preset = preset
        self.status_bar.showMessage(f"Selected preset: {preset.get_display_name()}")

    def on_preset_double_clicked(self, preset: Preset):
        """Handle preset double-click - same action as Send MIDI button"""
        # First make sure we have the necessary selections
        if not self.selected_midi_out_port:
            self.show_error(
                "No MIDI output port selected. Please select a MIDI output port first."
            )
            return

        # Call the send_preset method directly
        self.send_preset()

    def on_midi_out_port_changed(self, port_name: str):
        """Handle MIDI out port selection change"""
        self.selected_midi_out_port = port_name
        self.status_bar.showMessage(f"Selected MIDI out port: {port_name}")

    def on_sequencer_port_changed(self, port_name: str):
        """Handle sequencer port selection change"""
        self.selected_sequencer_port = port_name if port_name else None
        if port_name:
            self.status_bar.showMessage(f"Selected sequencer port: {port_name}")
            logger.info(f"Sequencer port changed to: {port_name}")
        else:
            self.status_bar.showMessage("No sequencer port selected")
            logger.info("Sequencer port cleared")

    def on_midi_channel_changed(self, channel: int):
        """Handle MIDI channel selection change"""
        self.selected_midi_channel = channel
        self.status_bar.showMessage(f"Selected MIDI channel: {channel}")

    def on_send_button_clicked(self):
        """Handle Send button click"""
        if not self.selected_preset:
            self.show_error("No preset selected. Please select a preset first.")
            return

        if not self.selected_midi_out_port:
            self.show_error(
                "No MIDI output port selected. Please select a MIDI output port first."
            )
            return

        self.send_preset()

    async def _send_preset_async(self):
        """Send the selected preset to the server asynchronously"""
        if not self.selected_preset or not self.selected_midi_out_port:
            return

        # Monitor performance
        with PerformanceContext(get_monitor(), "send_preset"):
            # Start loading indicator immediately
            self._start_loading(
                f"Sending preset: {self.selected_preset.get_display_name()}..."
            )

            # Check if server is available
            if not self.server_available:
                logger.warning("Server is not available, cannot send preset")
                self.status_bar.showMessage(
                    "Server is not available, cannot send preset"
                )
                # Try to check server availability again
                available = await self.check_server_availability()
                if not available:
                    logger.error("Server is still not available, aborting preset send")
                    self.status_bar.showMessage(
                        "Server is not available, aborting preset send"
                    )
                    self.show_error(
                        "Server is not available. Please check your connection and try again."
                    )
                    self._stop_loading()
                    return
                else:
                    # Server is now available, update flag
                    self.server_available = True
                    logger.info("Server is now available, continuing with preset send")
                    self.status_bar.showMessage(
                        "Server is now available, continuing with preset send"
                    )

            try:
                self.status_bar.showMessage(
                    f"Sending preset: {self.selected_preset.get_display_name()}..."
                )

                # Log debug information
                logger.info(
                    f"Sending preset: {self.selected_preset.get_display_name()}"
                )
                logger.info(f"MIDI out port: {self.selected_midi_out_port}")
                logger.info(f"MIDI channel: {self.selected_midi_channel}")
                logger.info(f"Sequencer port: {self.selected_sequencer_port}")

                result = await self.api_client.send_preset(
                    self.selected_preset.preset_name,
                    self.selected_midi_out_port,
                    self.selected_midi_channel,
                    self.selected_sequencer_port,
                )

                if result.get("status") == "success":
                    self.status_bar.showMessage(
                        f"Preset sent: {self.selected_preset.get_display_name()}"
                    )
                else:
                    self.show_error(
                        f"Error sending preset: {result.get('message', 'Unknown error')}"
                    )

            except Exception as e:
                self.show_error(f"Error sending preset: {str(e)}")
            finally:
                # Stop loading indicator immediately
                self._stop_loading()

    def send_preset(self):
        """Send the selected preset to the server"""
        logger.info("Sending preset")
        self.run_async_task(self._send_preset_async())

    def show_error(self, message: str):
        """Show an error message dialog"""
        try:
            # Log the error message
            logger.error(f"SHOW_ERROR: {message}")

            # Update status bar - this is thread-safe
            self.status_bar.showMessage(f"Error: {message}")

            # Force flush all handlers to ensure the log is written immediately
            for handler in logging.getLogger().handlers:
                handler.flush()

            # Use QTimer to ensure the QMessageBox is created and shown on the main thread
            def show_message_box():
                try:
                    # Log that we're about to create the QMessageBox
                    logger.error("SHOW_ERROR: Creating QMessageBox")
                    for handler in logging.getLogger().handlers:
                        handler.flush()

                    # Create and show the QMessageBox
                    error_box = QMessageBox()
                    error_box.setIcon(QMessageBox.Icon.Critical)
                    error_box.setWindowTitle("Error")
                    error_box.setText(message)

                    # Log that we're about to show the QMessageBox
                    logger.error("SHOW_ERROR: About to show QMessageBox")
                    for handler in logging.getLogger().handlers:
                        handler.flush()

                    # Show the QMessageBox
                    error_box.exec()

                    # Log that the QMessageBox was shown successfully
                    logger.error("SHOW_ERROR: QMessageBox shown successfully")
                    for handler in logging.getLogger().handlers:
                        handler.flush()
                except Exception as e:
                    # Log any exceptions that occur when showing the QMessageBox
                    error_msg = f"SHOW_ERROR: Failed to show error dialog: {str(e)}"
                    logger.error(error_msg)
                    logger.error(f"Exception type: {type(e).__name__}")
                    logger.error(f"Traceback: {traceback.format_exc()}")
                    # Force flush all handlers to ensure the log is written immediately
                    for handler in logging.getLogger().handlers:
                        handler.flush()

            # Use QTimer.singleShot to run on the main thread
            logger.error(
                "SHOW_ERROR: Scheduling QMessageBox creation with QTimer.singleShot"
            )
            for handler in logging.getLogger().handlers:
                handler.flush()

            QTimer.singleShot(0, show_message_box)

            # Log that QTimer.singleShot was called successfully
            logger.error("SHOW_ERROR: QTimer.singleShot called successfully")
            for handler in logging.getLogger().handlers:
                handler.flush()
        except Exception as e:
            # Log any exceptions that occur in the show_error method
            error_msg = f"SHOW_ERROR: Exception in show_error method: {str(e)}"
            logger.error(error_msg)
            logger.error(f"Exception type: {type(e).__name__}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            # Force flush all handlers to ensure the log is written immediately
            for handler in logging.getLogger().handlers:
                handler.flush()

    def closeEvent(self, event):
        """Handle window close event"""
        logger.info("Closing application")

        # Log performance summary if in debug mode
        if self.config.debug_mode:
            monitor = get_monitor()
            monitor.log_summary()
            monitor.stop_monitoring()

        try:
            # Close the API client
            if self._async_loop and self._async_loop.is_running():
                try:
                    # Try to close the API client
                    future = asyncio.run_coroutine_threadsafe(
                        self.api_client.close(), self._async_loop
                    )
                    # Wait for a short time to allow the client to close
                    future.result(timeout=1.0)
                except Exception as e:
                    logger.error(f"Error closing API client: {str(e)}")
                finally:
                    # Stop the event loop
                    self._async_loop.call_soon_threadsafe(self._async_loop.stop)
        except Exception as e:
            logger.error(f"Error during shutdown: {str(e)}")

        # Accept the close event
        event.accept()
