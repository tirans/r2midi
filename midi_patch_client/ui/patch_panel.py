from typing import Dict, List, Optional, Set
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QListWidget, QListWidgetItem, 
    QLabel, QTextEdit, QComboBox, QGroupBox, QLineEdit, QPushButton,
    QCheckBox, QMenu
)
from PyQt6.QtCore import pyqtSignal, Qt, QTimer
from PyQt6.QtGui import QColor, QBrush, QIcon, QAction, QFont

from ..models import Patch
from ..config import get_config

import json
import os


class PatchPanel(QWidget):
    """Enhanced panel for displaying and selecting patches with search and favorites"""

    # Signal emitted when a patch is selected
    patch_selected = pyqtSignal(object)

    # Signal emitted when a patch is double-clicked
    patch_double_clicked = pyqtSignal(object)

    def __init__(self):
        super().__init__()
        self.patches = []
        self.filtered_patches = []
        self.current_category = None
        self.category_colors = {}
        self.search_text = ""
        self.show_favorites_only = False
        self.favorites = self._load_favorites()
        self.config = get_config()

        # Search debounce timer
        self.search_timer = QTimer()
        self.search_timer.setSingleShot(True)
        self.search_timer.timeout.connect(self._perform_search)

        self.initUI()

    def initUI(self):
        """Initialize the UI components"""
        # Main layout
        main_layout = QHBoxLayout()
        main_layout.setSpacing(12)  # Increase spacing between main components
        self.setLayout(main_layout)

        # Create a larger font for all components
        self.larger_font = QFont()
        self.larger_font.setPointSize(12)  # Increase font size

        # Left side - Patch selection
        left_panel = QWidget()
        left_layout = QVBoxLayout()
        left_layout.setSpacing(12)  # Increase spacing between components
        left_panel.setLayout(left_layout)

        # Search and filter controls
        controls_box = QGroupBox("Search and Filter")
        controls_box.setFont(self.larger_font)  # Set larger font for group box title
        controls_layout = QVBoxLayout()
        controls_layout.setSpacing(10)  # Increase spacing between controls
        controls_layout.setContentsMargins(10, 10, 10, 10)  # Add margins inside the group box
        controls_box.setLayout(controls_layout)

        # Search box
        if self.config.enable_search:
            search_layout = QHBoxLayout()
            self.search_input = QLineEdit()
            self.search_input.setFont(self.larger_font)  # Set larger font
            self.search_input.setPlaceholderText("Search patches...")
            self.search_input.textChanged.connect(self.on_search_text_changed)

            # Create label with larger font
            search_label = QLabel("Search:")
            search_label.setFont(self.larger_font)
            search_layout.addWidget(search_label)
            search_layout.addWidget(self.search_input)

            # Clear search button
            self.clear_search_btn = QPushButton("Clear")
            self.clear_search_btn.setFont(self.larger_font)  # Set larger font
            self.clear_search_btn.clicked.connect(self.clear_search)
            search_layout.addWidget(self.clear_search_btn)

            controls_layout.addLayout(search_layout)

        # Category filter
        filter_layout = QHBoxLayout()
        self.category_combo = QComboBox()
        self.category_combo.setFont(self.larger_font)  # Set larger font
        self.category_combo.addItem("All Categories", None)
        self.category_combo.currentIndexChanged.connect(self.on_category_changed)
        self.category_combo.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToContents)
        self.category_combo.setMinimumWidth(200)

        # Create label with larger font
        category_label = QLabel("Category:")
        category_label.setFont(self.larger_font)
        filter_layout.addWidget(category_label)
        filter_layout.addWidget(self.category_combo)
        controls_layout.addLayout(filter_layout)

        # Favorites checkbox
        if self.config.enable_favorites:
            self.favorites_checkbox = QCheckBox("Show Favorites Only")
            self.favorites_checkbox.stateChanged.connect(self.on_favorites_filter_changed)
            self.favorites_checkbox.setFont(self.larger_font)  # Set larger font

            # Add the checkbox with some spacing
            controls_layout.addWidget(self.favorites_checkbox)
            controls_layout.addSpacing(5)  # Add extra space after checkbox

        left_layout.addWidget(controls_box)

        # Patch list
        list_box = QGroupBox("Patches")
        list_box.setFont(self.larger_font)  # Set larger font for group box title
        list_layout = QVBoxLayout()
        list_layout.setSpacing(10)  # Increase spacing between list components
        list_layout.setContentsMargins(10, 10, 10, 10)  # Add margins inside the group box
        list_box.setLayout(list_layout)

        # Results count label
        self.results_label = QLabel("0 patches")
        self.results_label.setFont(self.larger_font)  # Set larger font
        list_layout.addWidget(self.results_label)

        self.patch_list = QListWidget()
        self.patch_list.setFont(self.larger_font)  # Set larger font
        self.patch_list.itemClicked.connect(self.on_patch_clicked)
        self.patch_list.itemDoubleClicked.connect(self.on_patch_double_clicked)

        # Enable context menu for favorites
        if self.config.enable_favorites:
            self.patch_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
            self.patch_list.customContextMenuRequested.connect(self.show_context_menu)

        list_layout.addWidget(self.patch_list)

        left_layout.addWidget(list_box)

        # Right side - Patch details and category legend
        right_panel = QWidget()
        right_layout = QVBoxLayout()
        right_layout.setSpacing(10)  # Increase spacing between components
        right_panel.setLayout(right_layout)

        # Category legend
        self.legend_box = QGroupBox("Category Colors")
        self.legend_box.setFont(self.larger_font)  # Set larger font for group box title
        legend_layout = QVBoxLayout()
        legend_layout.setSpacing(5)  # Spacing between legend items
        legend_layout.setContentsMargins(10, 10, 10, 10)  # Add margins inside the group box
        self.legend_box.setLayout(legend_layout)

        # Legend will be populated when patches are loaded
        self.legend_layout = legend_layout
        right_layout.addWidget(self.legend_box)

        # Patch details
        details_box = QGroupBox("Patch Details")
        details_box.setFont(self.larger_font)  # Set larger font for group box title
        details_layout = QVBoxLayout()
        details_layout.setSpacing(10)  # Increase spacing between components
        details_layout.setContentsMargins(10, 10, 10, 10)  # Add margins inside the group box
        details_box.setLayout(details_layout)

        self.details_text = QTextEdit()
        self.details_text.setFont(self.larger_font)  # Set larger font
        self.details_text.setReadOnly(True)
        details_layout.addWidget(self.details_text)

        right_layout.addWidget(details_box)

        # Add panels to main layout
        main_layout.addWidget(left_panel, 1)
        main_layout.addWidget(right_panel, 1)

    def set_patches(self, patches: List[Patch]):
        """Set the patches to display"""
        self.patches = patches

        # Extract unique categories and assign colors
        categories = sorted(set(patch.category for patch in patches))

        # Generate distinct colors for categories
        self.category_colors = {}

        # Predefined color palette for better visual distinction
        # Using a combination of varying hue, saturation, and value
        predefined_colors = [
            QColor(255, 153, 153),  # Light red
            QColor(153, 204, 255),  # Light blue
            QColor(153, 255, 153),  # Light green
            QColor(255, 204, 153),  # Light orange
            QColor(204, 153, 255),  # Light purple
            QColor(255, 255, 153),  # Light yellow
            QColor(153, 255, 204),  # Light teal
            QColor(255, 153, 204),  # Light pink
            QColor(204, 204, 153),  # Light olive
            QColor(204, 153, 153),  # Light brown
        ]

        # If we have more categories than predefined colors, generate additional colors
        if len(categories) > len(predefined_colors):
            hue_step = 360 / (len(categories) - len(predefined_colors) or 1)
            for i in range(len(predefined_colors), len(categories)):
                # Create additional colors with varying saturation and value
                hue = (i - len(predefined_colors)) * hue_step
                saturation = 150 + (i % 3) * 40  # Vary saturation between 150-230
                value = 200 + (i % 2) * 55       # Vary value between 200-255
                predefined_colors.append(QColor.fromHsv(int(hue), saturation, value))

        # Assign colors to categories
        for i, category in enumerate(categories):
            self.category_colors[category] = predefined_colors[i % len(predefined_colors)]

        # Update category combo box with color indicators
        self.category_combo.clear()
        self.category_combo.addItem("All Categories", None)

        # Add categories with color indicators
        for category in categories:
            # Create a colored square icon for the category
            pixmap_size = 16
            from PyQt6.QtGui import QPixmap, QPainter
            pixmap = QPixmap(pixmap_size, pixmap_size)
            pixmap.fill(self.category_colors[category])

            # Add the category with its color icon
            self.category_combo.addItem(QIcon(pixmap), category, category)

        # Update the category legend
        self._update_category_legend(categories)

        self.update_display()

    def filter_by_category(self, category: Optional[str]):
        """Filter patches by category"""
        self.current_category = category
        self.update_display()

    def on_search_text_changed(self, text: str):
        """Handle search text change with debouncing"""
        self.search_text = text
        # Cancel previous timer
        self.search_timer.stop()
        # Start new timer
        self.search_timer.start(300)  # 300ms delay

    def _perform_search(self):
        """Perform the actual search"""
        self.update_display()

    def clear_search(self):
        """Clear the search input"""
        self.search_input.clear()
        self.search_text = ""
        self.update_display()

    def on_favorites_filter_changed(self, state: int):
        """Handle favorites filter checkbox change"""
        self.show_favorites_only = state == Qt.CheckState.Checked.value
        self.update_display()

    def update_display(self):
        """Update the patch display based on current filters"""
        self.patch_list.clear()

        # Apply filters
        self.filtered_patches = self.patches.copy()  # Make a copy to avoid modifying the original

        # Category filter
        if self.current_category:
            self.filtered_patches = [p for p in self.filtered_patches if p.category == self.current_category]

        # Search filter
        if self.search_text:
            search_lower = self.search_text.lower()
            self.filtered_patches = [
                p for p in self.filtered_patches
                if search_lower in p.preset_name.lower()
            ]

        # Favorites filter
        if self.show_favorites_only:
            self.filtered_patches = [
                p for p in self.filtered_patches
                if self._is_favorite(p)
            ]

        # Update results count
        self.results_label.setText(f"{len(self.filtered_patches)} patches")

        # Add patches to list widget
        for patch in self.filtered_patches:
            item = QListWidgetItem(self._get_patch_display_name(patch))

            # Set background color based on category with increased opacity for better visibility
            if patch.category in self.category_colors:
                color = self.category_colors[patch.category]
                # Make the color more visible by increasing its opacity
                color.setAlpha(200)  # 0-255, where 255 is fully opaque
                item.setBackground(QBrush(color))

                # Set text color to ensure good contrast with background
                # Use dark text for light backgrounds and light text for dark backgrounds
                brightness = (color.red() * 299 + color.green() * 587 + color.blue() * 114) / 1000
                if brightness > 128:
                    item.setForeground(QBrush(QColor(0, 0, 0)))  # Black text for light backgrounds
                else:
                    item.setForeground(QBrush(QColor(255, 255, 255)))  # White text for dark backgrounds

            # Add star icon for favorites
            if self._is_favorite(patch):
                item.setText("★ " + item.text())

            # Store the patch object with the item
            item.setData(Qt.ItemDataRole.UserRole, patch)

            self.patch_list.addItem(item)

    def _get_patch_display_name(self, patch: Patch) -> str:
        """Get display name for a patch with category"""
        # Include category in the display name for better identification
        display_name = f"{patch.preset_name} - {patch.category}"

        # Add source information if it's not the default
        if patch.source and patch.source != "default":
            display_name += f" [{patch.source}]"

        return display_name

    def on_category_changed(self, index):
        """Handle category selection change"""
        category = self.category_combo.itemData(index)
        self.current_category = category
        self.update_display()

    def on_patch_clicked(self, item):
        """Handle patch selection"""
        patch = item.data(Qt.ItemDataRole.UserRole)
        if patch:
            # Update details display
            self.details_text.setText(self._get_patch_details(patch))

            # Emit signal
            self.patch_selected.emit(patch)

    def on_patch_double_clicked(self, item):
        """Handle patch double-click"""
        patch = item.data(Qt.ItemDataRole.UserRole)
        if patch:
            # Update details display (same as single click)
            self.details_text.setText(self._get_patch_details(patch))

            # Emit both signals - first select the patch, then emit double-click
            self.patch_selected.emit(patch)
            self.patch_double_clicked.emit(patch)

    def _get_patch_details(self, patch: Patch) -> str:
        """Get detailed information about the patch"""
        details = [f"Name: {patch.preset_name}", f"Category: {patch.category}"]

        if self._is_favorite(patch):
            details.append("★ Favorite")

        if patch.source:
            details.append(f"Source: {patch.source}")

        if patch.characters:
            details.append(f"Characters: {', '.join(patch.characters)}")

        if patch.cc_0 is not None and patch.pgm is not None:
            details.append(f"CC 0: {patch.cc_0}, Program: {patch.pgm}")

        if patch.sendmidi_command:
            details.append(f"\nSendMIDI Command:\n{patch.sendmidi_command}")

        return "\n".join(details)

    def show_context_menu(self, position):
        """Show context menu for patch items"""
        item = self.patch_list.itemAt(position)
        if not item:
            return

        patch = item.data(Qt.ItemDataRole.UserRole)
        if not patch:
            return

        menu = QMenu(self)

        # Toggle favorite action
        if self._is_favorite(patch):
            action = QAction("Remove from Favorites", self)
            action.triggered.connect(lambda: self.remove_from_favorites(patch))
        else:
            action = QAction("Add to Favorites", self)
            action.triggered.connect(lambda: self.add_to_favorites(patch))

        menu.addAction(action)
        menu.exec(self.patch_list.mapToGlobal(position))

    def _is_favorite(self, patch: Patch) -> bool:
        """Check if a patch is in favorites"""
        return self._get_patch_id(patch) in self.favorites

    def _get_patch_id(self, patch: Patch) -> str:
        """Get unique identifier for a patch"""
        return f"{patch.preset_name}_{patch.category}_{patch.source or 'default'}"

    def add_to_favorites(self, patch: Patch):
        """Add a patch to favorites"""
        patch_id = self._get_patch_id(patch)
        self.favorites.add(patch_id)
        self._save_favorites()
        self.update_display()

    def remove_from_favorites(self, patch: Patch):
        """Remove a patch from favorites"""
        patch_id = self._get_patch_id(patch)
        self.favorites.discard(patch_id)
        self._save_favorites()
        self.update_display()

    def _load_favorites(self) -> Set[str]:
        """Load favorites from file"""
        favorites_file = os.path.join(os.path.expanduser("~"), ".r2midi_favorites.json")
        if os.path.exists(favorites_file):
            try:
                with open(favorites_file, 'r') as f:
                    return set(json.load(f))
            except Exception:
                pass
        return set()

    def _save_favorites(self):
        """Save favorites to file"""
        favorites_file = os.path.join(os.path.expanduser("~"), ".r2midi_favorites.json")
        try:
            with open(favorites_file, 'w') as f:
                json.dump(list(self.favorites), f)
        except Exception:
            pass

    def _update_category_legend(self, categories):
        """Update the category legend with color information"""
        # Clear existing legend items
        for i in reversed(range(self.legend_layout.count())):
            item = self.legend_layout.itemAt(i)
            if item.widget():
                item.widget().deleteLater()

        # If no categories, hide the legend
        if not categories:
            self.legend_box.setVisible(False)
            return

        # Show the legend
        self.legend_box.setVisible(True)

        # Add a label for each category with its color
        from PyQt6.QtGui import QPixmap, QPainter
        for category in categories:
            # Create a horizontal layout for this legend item
            from PyQt6.QtWidgets import QHBoxLayout
            item_layout = QHBoxLayout()

            # Create a colored square
            pixmap_size = 20
            pixmap = QPixmap(pixmap_size, pixmap_size)
            pixmap.fill(self.category_colors[category])

            # Create a label with the colored square
            from PyQt6.QtWidgets import QLabel
            color_label = QLabel()
            color_label.setPixmap(pixmap)
            color_label.setFixedSize(pixmap_size, pixmap_size)

            # Create a label with the category name
            text_label = QLabel(category)
            text_label.setFont(self.larger_font)

            # Add to layout
            item_layout.addWidget(color_label)
            item_layout.addWidget(text_label)
            item_layout.addStretch()

            # Add to legend layout
            self.legend_layout.addLayout(item_layout)

    def get_selected_patch(self) -> Optional[Patch]:
        """Get the currently selected patch"""
        current_item = self.patch_list.currentItem()
        if current_item:
            return current_item.data(Qt.ItemDataRole.UserRole)
        return None

    def select_patch_by_name(self, preset_name: str):
        """Select a patch by its preset name"""
        for i in range(self.patch_list.count()):
            item = self.patch_list.item(i)
            patch = item.data(Qt.ItemDataRole.UserRole)
            if patch and patch.preset_name == preset_name:
                self.patch_list.setCurrentItem(item)
                self.on_patch_clicked(item)
                break
