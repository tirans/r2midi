import unittest

import pytest
from server.models import Device, Preset, PresetRequest, UIState

pytestmark = pytest.mark.server


class TestModels(unittest.TestCase):
    """Test cases for the models module"""

    def test_device_model(self):
        """Test the Device model"""
        # Test with minimal required fields
        device = Device(name="Test Device", manufacturer="Test Manufacturer")
        self.assertEqual(device.name, "Test Device")
        self.assertEqual(device.manufacturer, "Test Manufacturer")
        self.assertIsNone(device.midi_port)
        self.assertIsNone(device.midi_channel)
        self.assertIsNone(device.community_folders)

        # Test with all fields
        device = Device(
            name="Test Device",
            manufacturer="Test Manufacturer",
            midi_port={"main": "Port 1"},
            midi_channel={"main": 1},
            community_folders=["folder1", "folder2"],
        )
        self.assertEqual(device.name, "Test Device")
        self.assertEqual(device.midi_port, {"main": "Port 1"})
        self.assertEqual(device.midi_channel, {"main": 1})

    def test_preset_model(self):
        """Test the Preset model"""
        # Test with minimal required fields
        preset = Preset(preset_name="Test Preset", category="Test Category")
        self.assertEqual(preset.preset_name, "Test Preset")
        self.assertEqual(preset.category, "Test Category")
        self.assertIsNone(preset.characters)
        self.assertIsNone(preset.sendmidi_command)
        self.assertIsNone(preset.cc_0)
        self.assertIsNone(preset.pgm)
        self.assertIsNone(preset.source)

        # Test with all fields
        preset = Preset(
            preset_name="Test Preset",
            category="Test Category",
            characters=["Warm", "Bright"],
            sendmidi_command="sendmidi dev 'Port 1' ch 1 cc 0 0 pc 0",
            cc_0=0,
            pgm=0,
            source="default",
        )
        self.assertEqual(preset.preset_name, "Test Preset")
        self.assertEqual(preset.category, "Test Category")
        self.assertEqual(preset.characters, ["Warm", "Bright"])
        self.assertEqual(
            preset.sendmidi_command, "sendmidi dev 'Port 1' ch 1 cc 0 0 pc 0"
        )
        self.assertEqual(preset.cc_0, 0)
        self.assertEqual(preset.pgm, 0)
        self.assertEqual(preset.source, "default")

    def test_preset_request_model(self):
        """Test the PresetRequest model"""
        # Test with minimal required fields
        preset_request = PresetRequest(
            preset_name="Test Preset", midi_port="Port 1", midi_channel=1
        )
        self.assertEqual(preset_request.preset_name, "Test Preset")
        self.assertEqual(preset_request.midi_port, "Port 1")
        self.assertEqual(preset_request.midi_channel, 1)
        self.assertIsNone(preset_request.sequencer_port)

        # Test with all fields
        preset_request = PresetRequest(
            preset_name="Test Preset",
            midi_port="Port 1",
            midi_channel=1,
            sequencer_port="Port 2",
        )
        self.assertEqual(preset_request.preset_name, "Test Preset")
        self.assertEqual(preset_request.midi_port, "Port 1")
        self.assertEqual(preset_request.midi_channel, 1)
        self.assertEqual(preset_request.sequencer_port, "Port 2")

    def test_ui_state_model(self):
        """Test the UIState model"""
        # Test with default values
        ui_state = UIState()
        self.assertIsNone(ui_state.manufacturer)
        self.assertIsNone(ui_state.device)
        self.assertIsNone(ui_state.community_folder)
        self.assertIsNone(ui_state.midi_in_port)
        self.assertIsNone(ui_state.midi_out_port)
        self.assertIsNone(ui_state.sequencer_port)
        self.assertIsNone(ui_state.midi_channel)
        self.assertTrue(ui_state.sync_enabled)

        # Test with all fields
        ui_state = UIState(
            manufacturer="Test Manufacturer",
            device="Test Device",
            community_folder="Test Folder",
            midi_in_port="In Port",
            midi_out_port="Out Port",
            sequencer_port="Seq Port",
            midi_channel=5,
            sync_enabled=False,
        )
        self.assertEqual(ui_state.manufacturer, "Test Manufacturer")
        self.assertEqual(ui_state.device, "Test Device")
        self.assertEqual(ui_state.community_folder, "Test Folder")
        self.assertEqual(ui_state.midi_in_port, "In Port")
        self.assertEqual(ui_state.midi_out_port, "Out Port")
        self.assertEqual(ui_state.sequencer_port, "Seq Port")
        self.assertEqual(ui_state.midi_channel, 5)
        self.assertFalse(ui_state.sync_enabled)


if __name__ == "__main__":
    unittest.main()
