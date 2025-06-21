#!/usr/bin/env python3
import argparse
import os
import sys

from PyQt6.QtWidgets import QApplication

# Add the project root to the Python path
sys.path.insert(0, os.path.abspath(os.path.dirname(os.path.dirname(__file__))))

# Import our fixed version of MainWindow (now copied to main_window.py)
from r2midi_client.ui.main_window import MainWindow


def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(description="MIDI Preset Selection Client")
    parser.add_argument(
        "--server-url",
        default="http://localhost:7777",
        help="URL of the MIDI Preset Selection server (default: http://localhost:7777)",
    )
    return parser.parse_args()


def main():
    """Main entry point for the application"""
    # Parse command-line arguments
    args = parse_args()

    # Create the Qt application
    app = QApplication(sys.argv)
    app.setApplicationName("MIDI Preset Selection")

    # Create and show the main window
    window = MainWindow(server_url=args.server_url)
    window.show()

    # Start the application event loop
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
