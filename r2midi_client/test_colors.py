#!/usr/bin/env python3
"""Test script to verify preset background colors are working"""

import json
import os


def clear_category_colors():
    """Clear saved category colors to force regeneration with new vibrant colors"""
    colors_file = os.path.join(os.path.expanduser("~"), ".r2midi_category_colors.json")
    if os.path.exists(colors_file):
        print(f"Removing existing category colors file: {colors_file}")
        os.remove(colors_file)
        print(
            "Category colors cleared. They will be regenerated with vibrant colors on next run."
        )
    else:
        print("No existing category colors file found.")


def view_category_colors():
    """View current saved category colors"""
    colors_file = os.path.join(os.path.expanduser("~"), ".r2midi_category_colors.json")
    if os.path.exists(colors_file):
        with open(colors_file, "r") as f:
            colors = json.load(f)
        print(f"\nCurrent category colors ({len(colors)} categories):")
        for category, color in colors.items():
            r, g, b, a = color
            print(f"  {category}: RGB({r}, {g}, {b})")
    else:
        print("No category colors file found.")


if __name__ == "__main__":
    print("MIDI Preset Client - Category Color Test\n")
    print("1. View current category colors")
    print("2. Clear category colors (force regeneration)")
    print("3. Exit")

    while True:
        choice = input("\nEnter your choice (1-3): ").strip()

        if choice == "1":
            view_category_colors()
        elif choice == "2":
            clear_category_colors()
        elif choice == "3":
            print("Exiting...")
            break
        else:
            print("Invalid choice. Please enter 1, 2, or 3.")
