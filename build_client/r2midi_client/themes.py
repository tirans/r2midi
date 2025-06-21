"""
Theme management for R2MIDI application
"""

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QPalette
from PyQt6.QtWidgets import QApplication, QWidget


class ThemeManager:
    """Manages application themes"""

    LIGHT_THEME = """
    QWidget {
        background-color: #f0f0f0;
        color: #333333;
        font-family: Arial, sans-serif;
        font-size: 13px;
    }

    QGroupBox {
        background-color: #ffffff;
        border: 1px solid #d0d0d0;
        border-radius: 5px;
        margin-top: 1ex;
        padding-top: 10px;
    }

    QGroupBox::title {
        subcontrol-origin: margin;
        left: 10px;
        padding: 0 5px 0 5px;
    }

    QPushButton {
        background-color: #007AFF;
        color: white;
        border: none;
        padding: 6px 12px;
        border-radius: 4px;
        font-weight: 500;
    }

    QPushButton:hover {
        background-color: #0051D5;
    }

    QPushButton:pressed {
        background-color: #0041A8;
    }

    QComboBox {
        background-color: white;
        border: 1px solid #d0d0d0;
        border-radius: 4px;
        padding: 4px 8px;
        min-height: 20px;
    }

    QComboBox:hover {
        border-color: #007AFF;
    }

    QComboBox::drop-down {
        border: none;
        width: 20px;
    }

    QLineEdit {
        background-color: white;
        border: 1px solid #d0d0d0;
        border-radius: 4px;
        padding: 4px 8px;
    }

    QLineEdit:focus {
        border-color: #007AFF;
        outline: none;
    }

    QListWidget {
        background-color: white;
        border: 1px solid #d0d0d0;
        border-radius: 4px;
        outline: none;
    }

    QListWidget::item {
        padding: 4px;
        border-bottom: 1px solid #f0f0f0;
    }

    QListWidget::item:selected {
        background-color: #007AFF;
        color: white !important;
    }

    QListWidget::item:hover:!selected {
        background-color: rgba(245, 245, 245, 120);
    }

    QTextEdit {
        background-color: white;
        border: 1px solid #d0d0d0;
        border-radius: 4px;
    }

    QStatusBar {
        background-color: #f8f8f8;
        border-top: 1px solid #d0d0d0;
    }

    QProgressBar {
        border: 1px solid #d0d0d0;
        border-radius: 3px;
        text-align: center;
        background-color: #f0f0f0;
    }

    QProgressBar::chunk {
        background-color: #007AFF;
        border-radius: 3px;
    }

    QTabWidget::pane {
        border: 1px solid #d0d0d0;
        background-color: white;
    }

    QTabBar::tab {
        background-color: #f0f0f0;
        padding: 8px 16px;
        margin-right: 2px;
        border-top-left-radius: 4px;
        border-top-right-radius: 4px;
    }

    QTabBar::tab:selected {
        background-color: white;
        border: 1px solid #d0d0d0;
        border-bottom: none;
    }

    QSpinBox {
        background-color: white;
        border: 1px solid #d0d0d0;
        border-radius: 4px;
        padding: 2px;
    }

    QCheckBox {
        spacing: 8px;
    }

    QCheckBox::indicator {
        width: 16px;
        height: 16px;
        border: 1px solid #d0d0d0;
        border-radius: 3px;
        background-color: white;
    }

    QCheckBox::indicator:checked {
        background-color: #007AFF;
        border-color: #007AFF;
    }

    QSplitter::handle {
        background-color: #e0e0e0;
    }

    QSplitter::handle:horizontal {
        width: 1px;
    }

    QSplitter::handle:vertical {
        height: 1px;
    }

    QMessageBox {
        background-color: white;
    }
    """

    DARK_THEME = """
    QWidget {
        background-color: #1e1e1e;
        color: #cccccc;
        font-family: Arial, sans-serif;
        font-size: 13px;
    }

    QGroupBox {
        background-color: #2d2d30;
        border: 1px solid #3e3e42;
        border-radius: 5px;
        margin-top: 1ex;
        padding-top: 10px;
    }

    QGroupBox::title {
        subcontrol-origin: margin;
        left: 10px;
        padding: 0 5px 0 5px;
        color: #cccccc;
    }

    QPushButton {
        background-color: #0e639c;
        color: white;
        border: none;
        padding: 6px 12px;
        border-radius: 4px;
        font-weight: 500;
    }

    QPushButton:hover {
        background-color: #1177bb;
    }

    QPushButton:pressed {
        background-color: #0d5d8f;
    }

    QComboBox {
        background-color: #3c3c3c;
        border: 1px solid #3e3e42;
        border-radius: 4px;
        padding: 4px 8px;
        min-height: 20px;
    }

    QComboBox:hover {
        border-color: #007ACC;
    }

    QComboBox::drop-down {
        border: none;
        width: 20px;
    }

    QComboBox QAbstractItemView {
        background-color: #252526;
        border: 1px solid #3e3e42;
        selection-background-color: #094771;
    }

    QLineEdit {
        background-color: #3c3c3c;
        border: 1px solid #3e3e42;
        border-radius: 4px;
        padding: 4px 8px;
        color: #cccccc;
    }

    QLineEdit:focus {
        border-color: #007ACC;
        outline: none;
    }

    QListWidget {
        background-color: #252526;
        border: 1px solid #3e3e42;
        border-radius: 4px;
        outline: none;
    }

    QListWidget::item {
        padding: 4px;
        border-bottom: 1px solid #1e1e1e;
    }

    QListWidget::item:selected {
        background-color: #094771;
        color: white !important;
    }

    QListWidget::item:hover:!selected {
        background-color: rgba(42, 45, 46, 120);
    }

    QTextEdit {
        background-color: #1e1e1e;
        border: 1px solid #3e3e42;
        border-radius: 4px;
        color: #cccccc;
    }

    QStatusBar {
        background-color: #007ACC;
        color: white;
        border: none;
    }

    QProgressBar {
        border: 1px solid #3e3e42;
        border-radius: 3px;
        text-align: center;
        background-color: #252526;
        color: #cccccc;
    }

    QProgressBar::chunk {
        background-color: #007ACC;
        border-radius: 3px;
    }

    QTabWidget::pane {
        border: 1px solid #3e3e42;
        background-color: #2d2d30;
    }

    QTabBar::tab {
        background-color: #2d2d30;
        color: #969696;
        padding: 8px 16px;
        margin-right: 2px;
        border-top-left-radius: 4px;
        border-top-right-radius: 4px;
    }

    QTabBar::tab:selected {
        background-color: #1e1e1e;
        color: #cccccc;
        border: 1px solid #3e3e42;
        border-bottom: none;
    }

    QTabBar::tab:hover {
        color: #cccccc;
    }

    QSpinBox {
        background-color: #3c3c3c;
        border: 1px solid #3e3e42;
        border-radius: 4px;
        padding: 2px;
        color: #cccccc;
    }

    QSpinBox::up-button, QSpinBox::down-button {
        background-color: #3c3c3c;
        border: none;
    }

    QSpinBox::up-arrow {
        image: none;
        border-left: 4px solid transparent;
        border-right: 4px solid transparent;
        border-bottom: 4px solid #cccccc;
        width: 0;
        height: 0;
    }

    QSpinBox::down-arrow {
        image: none;
        border-left: 4px solid transparent;
        border-right: 4px solid transparent;
        border-top: 4px solid #cccccc;
        width: 0;
        height: 0;
    }

    QCheckBox {
        spacing: 8px;
        color: #cccccc;
    }

    QCheckBox::indicator {
        width: 16px;
        height: 16px;
        border: 1px solid #3e3e42;
        border-radius: 3px;
        background-color: #3c3c3c;
    }

    QCheckBox::indicator:checked {
        background-color: #007ACC;
        border-color: #007ACC;
    }

    QSplitter::handle {
        background-color: #3e3e42;
    }

    QSplitter::handle:horizontal {
        width: 1px;
    }

    QSplitter::handle:vertical {
        height: 1px;
    }

    QMenu {
        background-color: #252526;
        border: 1px solid #3e3e42;
        padding: 4px;
    }

    QMenu::item {
        padding: 4px 20px;
        background-color: transparent;
    }

    QMenu::item:selected {
        background-color: #094771;
    }

    QMessageBox {
        background-color: #2d2d30;
    }

    QMessageBox QLabel {
        color: #cccccc;
    }

    QDialogButtonBox QPushButton {
        min-width: 80px;
    }

    QLabel {
        color: #cccccc;
    }

    /* Scrollbar styling */
    QScrollBar:vertical {
        background-color: #1e1e1e;
        width: 12px;
        border: none;
    }

    QScrollBar::handle:vertical {
        background-color: #5a5a5a;
        border-radius: 6px;
        min-height: 20px;
    }

    QScrollBar::handle:vertical:hover {
        background-color: #707070;
    }

    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0;
        border: none;
    }

    QScrollBar:horizontal {
        background-color: #1e1e1e;
        height: 12px;
        border: none;
    }

    QScrollBar::handle:horizontal {
        background-color: #5a5a5a;
        border-radius: 6px;
        min-width: 20px;
    }

    QScrollBar::handle:horizontal:hover {
        background-color: #707070;
    }

    QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
        width: 0;
        border: none;
    }
    """

    @staticmethod
    def apply_theme(app: QApplication, dark_mode: bool = False):
        """Apply theme to application"""
        if dark_mode:
            app.setStyleSheet(ThemeManager.DARK_THEME)

            # Also set the palette for better integration
            palette = QPalette()
            palette.setColor(QPalette.ColorRole.Window, QColor(30, 30, 30))
            palette.setColor(QPalette.ColorRole.WindowText, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.Base, QColor(45, 45, 48))
            palette.setColor(QPalette.ColorRole.AlternateBase, QColor(60, 60, 60))
            palette.setColor(QPalette.ColorRole.ToolTipBase, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.ToolTipText, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.Text, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.Button, QColor(45, 45, 48))
            palette.setColor(QPalette.ColorRole.ButtonText, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.BrightText, Qt.GlobalColor.red)
            palette.setColor(QPalette.ColorRole.Link, QColor(42, 130, 218))
            palette.setColor(QPalette.ColorRole.Highlight, QColor(42, 130, 218))
            palette.setColor(QPalette.ColorRole.HighlightedText, Qt.GlobalColor.black)

            app.setPalette(palette)
        else:
            app.setStyleSheet(ThemeManager.LIGHT_THEME)

            # Reset to default palette
            app.setPalette(app.style().standardPalette())

    @staticmethod
    def get_theme_style(dark_mode: bool = False) -> str:
        """Get the theme stylesheet"""
        return ThemeManager.DARK_THEME if dark_mode else ThemeManager.LIGHT_THEME
