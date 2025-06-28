"""
Keyboard shortcuts management for R2MIDI
"""

import logging
from typing import Callable, Dict, Optional

from PyQt6.QtCore import QObject, Qt, pyqtSignal
from PyQt6.QtGui import QKeySequence, QShortcut
from PyQt6.QtWidgets import QWidget

logger = logging.getLogger(__name__)


class ShortcutManager(QObject):
    """Manages keyboard shortcuts for the application"""

    # Signals for shortcuts
    send_preset = pyqtSignal()
    search_focus = pyqtSignal()
    clear_search = pyqtSignal()
    toggle_favorites = pyqtSignal()
    refresh_data = pyqtSignal()
    quit_app = pyqtSignal()
    show_preferences = pyqtSignal()

    # Navigation
    next_preset = pyqtSignal()
    previous_preset = pyqtSignal()
    next_category = pyqtSignal()
    previous_category = pyqtSignal()

    # MIDI channel shortcuts
    midi_channel_up = pyqtSignal()
    midi_channel_down = pyqtSignal()

    def __init__(self, parent_widget: QWidget):
        super().__init__(parent_widget)
        self.parent_widget = parent_widget
        self.shortcuts = {}
        self._setup_default_shortcuts()

    def _setup_default_shortcuts(self):
        """Set up default keyboard shortcuts"""
        # Main actions
        self._add_shortcut("Send Preset", "Return", self.send_preset)
        self._add_shortcut("Send Preset Alt", "Enter", self.send_preset)
        self._add_shortcut("Search", "Ctrl+F", self.search_focus)
        self._add_shortcut("Clear Search", "Escape", self.clear_search)
        self._add_shortcut("Toggle Favorites", "Ctrl+D", self.toggle_favorites)
        self._add_shortcut("Refresh", "F5", self.refresh_data)
        self._add_shortcut("Quit", "Ctrl+Q", self.quit_app)
        self._add_shortcut("Preferences", "Ctrl+,", self.show_preferences)

        # Navigation
        self._add_shortcut("Next Preset", "Down", self.next_preset)
        self._add_shortcut("Previous Preset", "Up", self.previous_preset)
        self._add_shortcut("Next Category", "Right", self.next_category)
        self._add_shortcut("Previous Category", "Left", self.previous_category)

        # Alternative navigation
        self._add_shortcut("Next Preset Alt", "J", self.next_preset)
        self._add_shortcut("Previous Preset Alt", "K", self.previous_preset)
        self._add_shortcut("Next Category Alt", "L", self.next_category)
        self._add_shortcut("Previous Category Alt", "H", self.previous_category)

        # MIDI channel control
        self._add_shortcut("MIDI Channel Up", "Ctrl+Up", self.midi_channel_up)
        self._add_shortcut("MIDI Channel Down", "Ctrl+Down", self.midi_channel_down)

        logger.info(f"Set up {len(self.shortcuts)} keyboard shortcuts")

    def _add_shortcut(self, name: str, key_sequence: str, signal: pyqtSignal):
        """Add a keyboard shortcut"""
        try:
            shortcut = QShortcut(QKeySequence(key_sequence), self.parent_widget)
            shortcut.activated.connect(signal.emit)
            self.shortcuts[name] = shortcut
            logger.debug(f"Added shortcut: {name} ({key_sequence})")
        except Exception as e:
            logger.error(f"Failed to add shortcut {name}: {e}")

    def set_enabled(self, enabled: bool):
        """Enable or disable all shortcuts"""
        for shortcut in self.shortcuts.values():
            shortcut.setEnabled(enabled)
        logger.info(f"Shortcuts {'enabled' if enabled else 'disabled'}")

    def update_shortcut(self, name: str, new_key_sequence: str):
        """Update a keyboard shortcut"""
        if name in self.shortcuts:
            try:
                self.shortcuts[name].setKey(QKeySequence(new_key_sequence))
                logger.info(f"Updated shortcut {name} to {new_key_sequence}")
            except Exception as e:
                logger.error(f"Failed to update shortcut {name}: {e}")
        else:
            logger.warning(f"Shortcut {name} not found")

    def get_shortcut_list(self) -> Dict[str, str]:
        """Get list of all shortcuts and their key sequences"""
        return {
            name: shortcut.key().toString() for name, shortcut in self.shortcuts.items()
        }

    def remove_shortcut(self, name: str):
        """Remove a keyboard shortcut"""
        if name in self.shortcuts:
            self.shortcuts[name].setEnabled(False)
            self.shortcuts[name].deleteLater()
            del self.shortcuts[name]
            logger.info(f"Removed shortcut: {name}")

    def reset_to_defaults(self):
        """Reset all shortcuts to defaults"""
        # Remove all current shortcuts
        for name in list(self.shortcuts.keys()):
            self.remove_shortcut(name)

        # Set up defaults again
        self._setup_default_shortcuts()
        logger.info("Reset shortcuts to defaults")


class ShortcutDisplay:
    """Helper class for displaying shortcuts in UI"""

    @staticmethod
    def get_formatted_shortcuts() -> str:
        """Get formatted list of shortcuts for display"""
        shortcuts = [
            (
                "Main Actions",
                [
                    ("Send Preset", "Enter/Return"),
                    ("Search Presetes", "Ctrl+F"),
                    ("Clear Search", "Esc"),
                    ("Toggle Favorites", "Ctrl+D"),
                    ("Refresh Data", "F5"),
                    ("Preferences", "Ctrl+,"),
                    ("Quit", "Ctrl+Q"),
                ],
            ),
            (
                "Navigation",
                [
                    ("Next Preset", "↓ or J"),
                    ("Previous Preset", "↑ or K"),
                    ("Next Category", "→ or L"),
                    ("Previous Category", "← or H"),
                ],
            ),
            (
                "MIDI Control",
                [("MIDI Channel Up", "Ctrl+↑"), ("MIDI Channel Down", "Ctrl+↓")],
            ),
        ]

        text = "Keyboard Shortcuts\n" + "=" * 30 + "\n\n"

        for section, items in shortcuts:
            text += f"{section}:\n"
            for action, keys in items:
                text += f"  {action:<20} {keys}\n"
            text += "\n"

        return text
