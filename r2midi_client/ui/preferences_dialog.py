"""
Preferences dialog for R2MIDI application
"""

import logging

from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QIntValidator
from PyQt6.QtWidgets import (QCheckBox, QComboBox, QDialog, QDialogButtonBox,
                             QFormLayout, QGroupBox, QHBoxLayout, QLabel,
                             QLineEdit, QMessageBox, QPushButton, QSpinBox,
                             QTabWidget, QTextEdit, QVBoxLayout, QWidget)

from ..config import AppConfig, get_config_manager
from ..shortcuts import ShortcutDisplay

logger = logging.getLogger(__name__)


class PreferencesDialog(QDialog):
    """Preferences dialog for application settings"""

    # Signal emitted when preferences are saved
    preferences_saved = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.config_manager = get_config_manager()
        self.original_config = AppConfig(**self.config_manager.config.to_dict())
        self.setWindowTitle("Preferences")
        self.setMinimumSize(600, 500)
        self.initUI()

    def initUI(self):
        """Initialize the UI"""
        layout = QVBoxLayout()
        self.setLayout(layout)

        # Tab widget for different preference categories
        self.tab_widget = QTabWidget()
        layout.addWidget(self.tab_widget)

        # Add tabs
        self.tab_widget.addTab(self._create_general_tab(), "General")
        self.tab_widget.addTab(self._create_midi_tab(), "MIDI")
        self.tab_widget.addTab(self._create_ui_tab(), "User Interface")
        self.tab_widget.addTab(self._create_performance_tab(), "Performance")
        self.tab_widget.addTab(self._create_shortcuts_tab(), "Shortcuts")
        self.tab_widget.addTab(self._create_advanced_tab(), "Advanced")

        # Dialog buttons
        button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel
            | QDialogButtonBox.StandardButton.Apply
            | QDialogButtonBox.StandardButton.RestoreDefaults
        )

        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        button_box.button(QDialogButtonBox.StandardButton.Apply).clicked.connect(
            self.apply_changes
        )
        button_box.button(
            QDialogButtonBox.StandardButton.RestoreDefaults
        ).clicked.connect(self.restore_defaults)

        layout.addWidget(button_box)

    def _create_general_tab(self) -> QWidget:
        """Create the general settings tab"""
        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        # Server settings
        server_group = QGroupBox("Server Settings")
        server_layout = QFormLayout()
        server_group.setLayout(server_layout)

        self.server_url_edit = QLineEdit(self.config_manager.config.server_url)
        server_layout.addRow("Server URL:", self.server_url_edit)

        self.server_timeout_spin = QSpinBox()
        self.server_timeout_spin.setRange(5, 300)
        self.server_timeout_spin.setValue(
            self.config_manager.config.server_check_timeout
        )
        self.server_timeout_spin.setSuffix(" seconds")
        server_layout.addRow("Connection Timeout:", self.server_timeout_spin)

        self.server_retries_spin = QSpinBox()
        self.server_retries_spin.setRange(1, 100)
        self.server_retries_spin.setValue(
            self.config_manager.config.server_check_retries
        )
        server_layout.addRow("Max Retries:", self.server_retries_spin)

        layout.addWidget(server_group)

        # Cache settings
        cache_group = QGroupBox("Cache Settings")
        cache_layout = QFormLayout()
        cache_group.setLayout(cache_layout)

        self.cache_enabled_check = QCheckBox()
        self.cache_enabled_check.setChecked(self.config_manager.config.cache_enabled)
        cache_layout.addRow("Enable Cache:", self.cache_enabled_check)

        self.cache_timeout_spin = QSpinBox()
        self.cache_timeout_spin.setRange(60, 3600)
        self.cache_timeout_spin.setValue(self.config_manager.config.cache_timeout)
        self.cache_timeout_spin.setSuffix(" seconds")
        cache_layout.addRow("Cache Timeout:", self.cache_timeout_spin)

        layout.addWidget(cache_group)
        layout.addStretch()

        return widget

    def _create_midi_tab(self) -> QWidget:
        """Create the MIDI settings tab"""
        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        midi_group = QGroupBox("MIDI Settings")
        midi_layout = QFormLayout()
        midi_group.setLayout(midi_layout)

        self.default_channel_spin = QSpinBox()
        self.default_channel_spin.setRange(1, 16)
        self.default_channel_spin.setValue(
            self.config_manager.config.default_midi_channel
        )
        midi_layout.addRow("Default MIDI Channel:", self.default_channel_spin)

        self.auto_select_ports_check = QCheckBox()
        self.auto_select_ports_check.setChecked(
            self.config_manager.config.auto_select_midi_ports
        )
        midi_layout.addRow("Auto-select MIDI Ports:", self.auto_select_ports_check)

        layout.addWidget(midi_group)
        layout.addStretch()

        return widget

    def _create_ui_tab(self) -> QWidget:
        """Create the UI settings tab"""
        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        # Window settings
        window_group = QGroupBox("Window Settings")
        window_layout = QFormLayout()
        window_group.setLayout(window_layout)

        self.window_width_spin = QSpinBox()
        self.window_width_spin.setRange(600, 2000)
        self.window_width_spin.setValue(self.config_manager.config.window_width)
        window_layout.addRow("Default Width:", self.window_width_spin)

        self.window_height_spin = QSpinBox()
        self.window_height_spin.setRange(400, 1500)
        self.window_height_spin.setValue(self.config_manager.config.window_height)
        window_layout.addRow("Default Height:", self.window_height_spin)

        layout.addWidget(window_group)

        # UI behavior
        behavior_group = QGroupBox("UI Behavior")
        behavior_layout = QFormLayout()
        behavior_group.setLayout(behavior_layout)

        self.debounce_delay_spin = QSpinBox()
        self.debounce_delay_spin.setRange(100, 1000)
        self.debounce_delay_spin.setValue(self.config_manager.config.debounce_delay_ms)
        self.debounce_delay_spin.setSuffix(" ms")
        behavior_layout.addRow("Debounce Delay:", self.debounce_delay_spin)

        self.dark_mode_check = QCheckBox()
        self.dark_mode_check.setChecked(self.config_manager.config.dark_mode)
        behavior_layout.addRow("Dark Mode:", self.dark_mode_check)

        layout.addWidget(behavior_group)

        # Features
        features_group = QGroupBox("Features")
        features_layout = QFormLayout()
        features_group.setLayout(features_layout)

        self.enable_search_check = QCheckBox()
        self.enable_search_check.setChecked(self.config_manager.config.enable_search)
        features_layout.addRow("Enable Search:", self.enable_search_check)

        self.enable_favorites_check = QCheckBox()
        self.enable_favorites_check.setChecked(
            self.config_manager.config.enable_favorites
        )
        features_layout.addRow("Enable Favorites:", self.enable_favorites_check)

        self.enable_shortcuts_check = QCheckBox()
        self.enable_shortcuts_check.setChecked(
            self.config_manager.config.enable_keyboard_shortcuts
        )
        features_layout.addRow(
            "Enable Keyboard Shortcuts:", self.enable_shortcuts_check
        )

        layout.addWidget(features_group)
        layout.addStretch()

        return widget

    def _create_performance_tab(self) -> QWidget:
        """Create the performance settings tab"""
        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        performance_group = QGroupBox("Performance Settings")
        performance_layout = QFormLayout()
        performance_group.setLayout(performance_layout)

        self.max_presets_spin = QSpinBox()
        self.max_presets_spin.setRange(100, 10000)
        self.max_presets_spin.setValue(self.config_manager.config.max_presets_display)
        performance_layout.addRow("Max Presets to Display:", self.max_presets_spin)

        self.lazy_loading_check = QCheckBox()
        self.lazy_loading_check.setChecked(
            self.config_manager.config.enable_lazy_loading
        )
        performance_layout.addRow("Enable Lazy Loading:", self.lazy_loading_check)

        layout.addWidget(performance_group)
        layout.addStretch()

        return widget

    def _create_shortcuts_tab(self) -> QWidget:
        """Create the keyboard shortcuts tab"""
        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        # Shortcuts display
        shortcuts_text = QTextEdit()
        shortcuts_text.setReadOnly(True)
        shortcuts_text.setPlainText(ShortcutDisplay.get_formatted_shortcuts())
        layout.addWidget(shortcuts_text)

        # Note about customization
        note_label = QLabel(
            "Note: Keyboard shortcut customization will be available in a future update."
        )
        note_label.setWordWrap(True)
        layout.addWidget(note_label)

        return widget

    def _create_advanced_tab(self) -> QWidget:
        """Create the advanced settings tab"""
        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        # Debug settings
        debug_group = QGroupBox("Debug Settings")
        debug_layout = QFormLayout()
        debug_group.setLayout(debug_layout)

        self.debug_mode_check = QCheckBox()
        self.debug_mode_check.setChecked(self.config_manager.config.debug_mode)
        debug_layout.addRow("Debug Mode:", self.debug_mode_check)

        self.log_level_combo = QComboBox()
        self.log_level_combo.addItems(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"])
        self.log_level_combo.setCurrentText(self.config_manager.config.log_level)
        debug_layout.addRow("Log Level:", self.log_level_combo)

        layout.addWidget(debug_group)

        # Config management
        config_group = QGroupBox("Configuration Management")
        config_layout = QVBoxLayout()
        config_group.setLayout(config_layout)

        export_button = QPushButton("Export Configuration...")
        export_button.clicked.connect(self.export_config)
        config_layout.addWidget(export_button)

        import_button = QPushButton("Import Configuration...")
        import_button.clicked.connect(self.import_config)
        config_layout.addWidget(import_button)

        layout.addWidget(config_group)
        layout.addStretch()

        return widget

    def apply_changes(self):
        """Apply the current changes"""
        # Update configuration
        self.config_manager.update_config(
            # General
            server_url=self.server_url_edit.text(),
            server_check_timeout=self.server_timeout_spin.value(),
            server_check_retries=self.server_retries_spin.value(),
            cache_enabled=self.cache_enabled_check.isChecked(),
            cache_timeout=self.cache_timeout_spin.value(),
            # MIDI
            default_midi_channel=self.default_channel_spin.value(),
            auto_select_midi_ports=self.auto_select_ports_check.isChecked(),
            # UI
            window_width=self.window_width_spin.value(),
            window_height=self.window_height_spin.value(),
            debounce_delay_ms=self.debounce_delay_spin.value(),
            dark_mode=self.dark_mode_check.isChecked(),
            enable_search=self.enable_search_check.isChecked(),
            enable_favorites=self.enable_favorites_check.isChecked(),
            enable_keyboard_shortcuts=self.enable_shortcuts_check.isChecked(),
            # Performance
            max_presets_display=self.max_presets_spin.value(),
            enable_lazy_loading=self.lazy_loading_check.isChecked(),
            # Advanced
            debug_mode=self.debug_mode_check.isChecked(),
            log_level=self.log_level_combo.currentText(),
        )

        # Save configuration
        if self.config_manager.save_config():
            self.preferences_saved.emit()
            logger.info("Preferences saved successfully")
        else:
            QMessageBox.warning(self, "Warning", "Failed to save preferences")

    def accept(self):
        """Accept and save changes"""
        self.apply_changes()
        super().accept()

    def reject(self):
        """Cancel changes and restore original configuration"""
        # Restore original configuration
        self.config_manager.config = self.original_config
        super().reject()

    def restore_defaults(self):
        """Restore all settings to defaults"""
        reply = QMessageBox.question(
            self,
            "Restore Defaults",
            "Are you sure you want to restore all settings to their default values?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:
            self.config_manager.reset_to_defaults()
            # Update UI to reflect defaults
            self._update_ui_from_config()

    def _update_ui_from_config(self):
        """Update UI elements from current configuration"""
        config = self.config_manager.config

        # General
        self.server_url_edit.setText(config.server_url)
        self.server_timeout_spin.setValue(config.server_check_timeout)
        self.server_retries_spin.setValue(config.server_check_retries)
        self.cache_enabled_check.setChecked(config.cache_enabled)
        self.cache_timeout_spin.setValue(config.cache_timeout)

        # MIDI
        self.default_channel_spin.setValue(config.default_midi_channel)
        self.auto_select_ports_check.setChecked(config.auto_select_midi_ports)

        # UI
        self.window_width_spin.setValue(config.window_width)
        self.window_height_spin.setValue(config.window_height)
        self.debounce_delay_spin.setValue(config.debounce_delay_ms)
        self.dark_mode_check.setChecked(config.dark_mode)
        self.enable_search_check.setChecked(config.enable_search)
        self.enable_favorites_check.setChecked(config.enable_favorites)
        self.enable_shortcuts_check.setChecked(config.enable_keyboard_shortcuts)

        # Performance
        self.max_presets_spin.setValue(config.max_presets_display)
        self.lazy_loading_check.setChecked(config.enable_lazy_loading)

        # Advanced
        self.debug_mode_check.setChecked(config.debug_mode)
        self.log_level_combo.setCurrentText(config.log_level)

    def export_config(self):
        """Export configuration to file"""
        from PyQt6.QtWidgets import QFileDialog

        filename, _ = QFileDialog.getSaveFileName(
            self, "Export Configuration", "r2midi_config.json", "JSON Files (*.json)"
        )

        if filename:
            if self.config_manager.export_config(filename):
                QMessageBox.information(
                    self, "Success", "Configuration exported successfully"
                )
            else:
                QMessageBox.warning(self, "Error", "Failed to export configuration")

    def import_config(self):
        """Import configuration from file"""
        from PyQt6.QtWidgets import QFileDialog

        filename, _ = QFileDialog.getOpenFileName(
            self, "Import Configuration", "", "JSON Files (*.json)"
        )

        if filename:
            if self.config_manager.import_config(filename):
                self._update_ui_from_config()
                QMessageBox.information(
                    self, "Success", "Configuration imported successfully"
                )
            else:
                QMessageBox.warning(self, "Error", "Failed to import configuration")
