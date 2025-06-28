import asyncio
import os
import socket
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient as FastAPITestClient

# Import the app and functions from server.main
from server.main import app, find_available_port, is_port_in_use

pytestmark = pytest.mark.server


# Create a custom TestClient that's compatible with newer versions of httpx
class TestClient(FastAPITestClient):
    """Custom TestClient that's compatible with newer versions of httpx"""

    def get(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().get(*args, **kwargs)

    def post(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().post(*args, **kwargs)

    def put(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().put(*args, **kwargs)

    def delete(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().delete(*args, **kwargs)

    def patch(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().patch(*args, **kwargs)

    def options(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().options(*args, **kwargs)

    def head(self, *args, **kwargs):
        # Remove the 'extensions' parameter if it exists
        kwargs.pop("extensions", None)
        return super().head(*args, **kwargs)


class TestMainFunctions(unittest.TestCase):
    """Test cases for the utility functions in main.py"""

    @patch("socket.socket")
    def test_is_port_in_use_true(self, mock_socket):
        """Test is_port_in_use when port is in use"""
        # Set up mock to return 0 (success) for connect_ex
        mock_socket_instance = MagicMock()
        mock_socket_instance.connect_ex.return_value = 0
        mock_socket.return_value.__enter__.return_value = mock_socket_instance

        # Call the function
        result = is_port_in_use(8000)

        # Verify the result
        self.assertTrue(result)
        mock_socket_instance.connect_ex.assert_called_once_with(("localhost", 8000))

    @patch("socket.socket")
    def test_is_port_in_use_false(self, mock_socket):
        """Test is_port_in_use when port is not in use"""
        # Set up mock to return non-zero (failure) for connect_ex
        mock_socket_instance = MagicMock()
        mock_socket_instance.connect_ex.return_value = 1
        mock_socket.return_value.__enter__.return_value = mock_socket_instance

        # Call the function
        result = is_port_in_use(8000)

        # Verify the result
        self.assertFalse(result)
        mock_socket_instance.connect_ex.assert_called_once_with(("localhost", 8000))

    @patch("server.main.is_port_in_use")
    def test_find_available_port_first_available(self, mock_is_port_in_use):
        """Test find_available_port when the first port is available"""
        # Set up mock to return False (port not in use)
        mock_is_port_in_use.return_value = False

        # Call the function
        result = find_available_port(8000)

        # Verify the result
        self.assertEqual(result, 8000)
        mock_is_port_in_use.assert_called_once_with(8000)

    @patch("server.main.is_port_in_use")
    def test_find_available_port_second_available(self, mock_is_port_in_use):
        """Test find_available_port when the second port is available"""
        # Set up mock to return True for first port, False for second port
        mock_is_port_in_use.side_effect = [True, False]

        # Call the function
        result = find_available_port(8000)

        # Verify the result
        self.assertEqual(result, 8001)
        self.assertEqual(mock_is_port_in_use.call_count, 2)
        mock_is_port_in_use.assert_any_call(8000)
        mock_is_port_in_use.assert_any_call(8001)

    @patch("server.main.is_port_in_use")
    def test_find_available_port_none_available(self, mock_is_port_in_use):
        """Test find_available_port when no ports are available"""
        # Set up mock to always return True (all ports in use)
        mock_is_port_in_use.return_value = True

        # Call the function
        result = find_available_port(8000, max_attempts=3)

        # Verify the result
        self.assertEqual(result, 8000)  # Should return the original port
        self.assertEqual(mock_is_port_in_use.call_count, 3)


class TestFastAPIEndpoints:
    """Test cases for the FastAPI endpoints"""

    @pytest.fixture
    def client(self):
        """Create a TestClient for the FastAPI app"""
        return TestClient(app)

    @patch("server.device_manager.DeviceManager.get_manufacturers")
    @patch("server.device_manager.DeviceManager.get_device_info_by_manufacturer")
    def test_get_devices(self, mock_get_device_info, mock_get_manufacturers, client):
        """Test the combination of /manufacturers and /device_info endpoints that replace /devices"""
        # Set up mocks
        mock_get_manufacturers.return_value = ["Manufacturer 1", "Manufacturer 2"]

        # Mock device info for each manufacturer
        mock_get_device_info.side_effect = [
            [
                {
                    "name": "Device 1",
                    "manufacturer": "Manufacturer 1",
                    "midi_port": {"IN": "Port 1", "OUT": "Port 2"},
                    "midi_channel": {"IN": 1, "OUT": 2},
                    "community_folders": ["folder1", "folder2"],
                }
            ],
            [
                {
                    "name": "Device 2",
                    "manufacturer": "Manufacturer 2",
                    "midi_port": {"IN": "Port 3", "OUT": "Port 4"},
                    "midi_channel": {"IN": 3, "OUT": 4},
                    "community_folders": ["folder3"],
                }
            ],
        ]

        # Make the request to get manufacturers
        manufacturers_response = client.get("/manufacturers")

        # Verify the manufacturers response
        assert manufacturers_response.status_code == 200
        assert len(manufacturers_response.json()) == 2
        assert "Manufacturer 1" in manufacturers_response.json()
        assert "Manufacturer 2" in manufacturers_response.json()

        # Make requests to get device info for each manufacturer
        device_info_response1 = client.post(
            "/device_info", json={"manufacturer": "Manufacturer 1"}
        )
        device_info_response2 = client.post(
            "/device_info", json={"manufacturer": "Manufacturer 2"}
        )

        # Verify the device info responses
        assert device_info_response1.status_code == 200
        assert device_info_response2.status_code == 200

        # Verify the first manufacturer's device info
        assert len(device_info_response1.json()) == 1
        assert device_info_response1.json()[0]["name"] == "Device 1"
        assert device_info_response1.json()[0]["manufacturer"] == "Manufacturer 1"
        assert device_info_response1.json()[0]["community_folders"] == [
            "folder1",
            "folder2",
        ]

        # Verify the second manufacturer's device info
        assert len(device_info_response2.json()) == 1
        assert device_info_response2.json()[0]["name"] == "Device 2"
        assert device_info_response2.json()[0]["manufacturer"] == "Manufacturer 2"
        assert device_info_response2.json()[0]["community_folders"] == ["folder3"]

    @patch("server.device_manager.DeviceManager.get_manufacturers")
    @patch("server.device_manager.DeviceManager.get_device_info_by_manufacturer")
    def test_get_devices_error(
        self, mock_get_device_info, mock_get_manufacturers, client
    ):
        """Test error handling for the endpoints that replace /devices"""
        # Test error in get_manufacturers
        mock_get_manufacturers.side_effect = Exception("Test error in manufacturers")

        # Make the request to get manufacturers
        manufacturers_response = client.get("/manufacturers")

        # Verify the response
        assert manufacturers_response.status_code == 500
        assert "error" in manufacturers_response.json()["detail"].lower()

        # Reset the mock and set up for device_info error
        mock_get_manufacturers.side_effect = None
        mock_get_manufacturers.return_value = ["Manufacturer 1"]
        mock_get_device_info.side_effect = Exception("Test error in device info")

        # Make the request to get device info
        device_info_response = client.post(
            "/device_info", json={"manufacturer": "Manufacturer 1"}
        )

        # Verify the response
        assert device_info_response.status_code == 500
        assert "error" in device_info_response.json()["detail"].lower()

    @patch("server.device_manager.DeviceManager.get_manufacturers")
    def test_get_manufacturers(self, mock_get_manufacturers, client):
        """Test the GET /manufacturers endpoint"""
        # Set up mock to return a list of manufacturers
        mock_get_manufacturers.return_value = ["Manufacturer 1", "Manufacturer 2"]

        # Make the request
        response = client.get("/manufacturers")

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()) == 2
        assert "Manufacturer 1" in response.json()
        assert "Manufacturer 2" in response.json()

    @patch("server.device_manager.DeviceManager.get_manufacturers")
    def test_get_manufacturers_error(self, mock_get_manufacturers, client):
        """Test the GET /manufacturers endpoint with an error"""
        # Set up mock to raise an exception
        mock_get_manufacturers.side_effect = Exception("Test error")

        # Make the request
        response = client.get("/manufacturers")

        # Verify the response
        assert response.status_code == 500
        assert "error" in response.json()["detail"].lower()

    @patch("server.device_manager.DeviceManager.get_devices_by_manufacturer")
    def test_get_devices_by_manufacturer(
        self, mock_get_devices_by_manufacturer, client
    ):
        """Test the GET /devices/{manufacturer} endpoint"""
        # Set up mock to return a list of devices
        mock_get_devices_by_manufacturer.return_value = ["Device 1", "Device 2"]

        # Make the request
        response = client.get("/devices/Manufacturer%201")

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()) == 2
        assert "Device 1" in response.json()
        assert "Device 2" in response.json()

    @patch("server.device_manager.DeviceManager.get_devices_by_manufacturer")
    def test_get_devices_by_manufacturer_error(
        self, mock_get_devices_by_manufacturer, client
    ):
        """Test the GET /devices/{manufacturer} endpoint with an error"""
        # Set up mock to raise an exception
        mock_get_devices_by_manufacturer.side_effect = Exception("Test error")

        # Make the request
        response = client.get("/devices/Manufacturer%201")

        # Verify the response
        assert response.status_code == 500
        assert "error" in response.json()["detail"].lower()

    @patch("server.device_manager.DeviceManager.get_community_folders")
    def test_get_community_folders(self, mock_get_community_folders, client):
        """Test the GET /community_folders/{device_name} endpoint"""
        # Set up mock to return a list of community folders
        mock_get_community_folders.return_value = ["folder1", "folder2"]

        # Make the request
        response = client.get("/community_folders/Device%201")

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()) == 2
        assert "folder1" in response.json()
        assert "folder2" in response.json()

    @patch("server.device_manager.DeviceManager.get_community_folders")
    def test_get_community_folders_error(self, mock_get_community_folders, client):
        """Test the GET /community_folders/{device_name} endpoint with an error"""
        # Set up mock to raise an exception
        mock_get_community_folders.side_effect = Exception("Test error")

        # Make the request
        response = client.get("/community_folders/Device%201")

        # Verify the response
        assert response.status_code == 500
        assert "error" in response.json()["detail"].lower()

    @patch("server.device_manager.DeviceManager.get_all_presets")
    def test_get_presets(self, mock_get_all_presets, client):
        """Test the GET /presets/{manufacturer}/{device} endpoint that replaces /presets"""
        # Set up mock to return a list of Preset objects
        from server.models import Preset

        mock_get_all_presets.return_value = [
            Preset(preset_name="Preset 1", category="Category 1", source="default"),
            Preset(
                preset_name="Preset 2", category="Category 2", source="community_folder"
            ),
        ]

        # Make the request with manufacturer and device parameters
        response = client.get("/presets/Manufacturer%201/Device%201")

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()) == 2
        assert response.json()[0]["preset_name"] == "Preset 1"
        assert response.json()[0]["source"] == "default"
        assert response.json()[1]["preset_name"] == "Preset 2"
        assert response.json()[1]["source"] == "community_folder"

        # Verify that the mock was called with the correct parameters
        mock_get_all_presets.assert_called_with(
            device_name="Device 1", community_folder=None, manufacturer="Manufacturer 1"
        )

    @patch("server.device_manager.DeviceManager.get_all_presets")
    def test_get_presets_with_params(self, mock_get_all_presets, client):
        """Test the GET /presets/{manufacturer}/{device} endpoint with community_folder parameter"""
        # Set up mock to return a list of Preset objects
        from server.models import Preset

        mock_get_all_presets.return_value = [
            Preset(preset_name="Preset 1", category="Category 1", source="default"),
            Preset(
                preset_name="Preset 2", category="Category 2", source="community_folder"
            ),
        ]

        # Make the request with manufacturer and device parameters (no query params)
        response = client.get("/presets/Manufacturer%201/Device%201")

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()) == 2

        # Verify that the mock was called with the correct parameters
        mock_get_all_presets.assert_called_with(
            device_name="Device 1", community_folder=None, manufacturer="Manufacturer 1"
        )

        # Reset the mock
        mock_get_all_presets.reset_mock()

        # Make the request with manufacturer, device, and community_folder parameters
        response = client.get(
            "/presets/Manufacturer%201/Device%201?community_folder=folder1"
        )

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()) == 2

        # Verify that the mock was called with the correct parameters
        mock_get_all_presets.assert_called_with(
            device_name="Device 1",
            community_folder="folder1",
            manufacturer="Manufacturer 1",
        )

    @patch("server.device_manager.DeviceManager.get_all_presets")
    def test_get_presets_error(self, mock_get_all_presets, client):
        """Test the GET /presets/{manufacturer}/{device} endpoint with an error"""
        # Set up mock to raise an exception
        mock_get_all_presets.side_effect = Exception("Test error")

        # Make the request
        response = client.get("/presets/Manufacturer%201/Device%201")

        # Verify the response
        assert response.status_code == 500
        assert "error" in response.json()["detail"].lower()

    @patch("server.midi_utils.MidiUtils.get_midi_ports")
    def test_get_midi_ports(self, mock_get_midi_ports, client):
        """Test the GET /midi_ports endpoint"""
        # Set up mock to return a dictionary of ports
        mock_get_midi_ports.return_value = {
            "in": ["In Port 1", "In Port 2"],
            "out": ["Out Port 1", "Out Port 2"],
        }

        # Make the request
        response = client.get("/midi_ports")

        # Verify the response
        assert response.status_code == 200
        assert len(response.json()["in"]) == 2
        assert len(response.json()["out"]) == 2
        assert response.json()["in"][0] == "In Port 1"
        assert response.json()["out"][0] == "Out Port 1"

    @patch("server.midi_utils.MidiUtils.get_midi_ports")
    def test_get_midi_ports_error(self, mock_get_midi_ports, client):
        """Test the GET /midi_ports endpoint with an error"""
        # Set up mock to raise an exception
        mock_get_midi_ports.side_effect = Exception("Test error")

        # Make the request
        response = client.get("/midi_ports")

        # Verify the response
        assert response.status_code == 500
        assert "error" in response.json()["detail"].lower()

    @patch("server.device_manager.DeviceManager.get_preset_by_name")
    @patch("server.midi_utils.MidiUtils.asend_preset_select")
    def test_send_preset(
        self, mock_asend_preset_select, mock_get_preset_by_name, client
    ):
        """Test the POST /preset endpoint"""
        # Set up mocks
        mock_get_preset_by_name.return_value = {
            "preset_name": "Test Preset",
            "cc_0": 0,
            "pgm": 1,
        }
        mock_asend_preset_select.return_value = (True, "Command executed successfully")

        # Make the request
        response = client.post(
            "/preset",
            json={
                "preset_name": "Test Preset",
                "midi_port": "Port 1",
                "midi_channel": 1,
            },
        )

        # Verify the response
        assert response.status_code == 200
        assert response.json()["status"] == "success"

        # Verify that the mocks were called with the correct arguments
        mock_get_preset_by_name.assert_called_once_with("Test Preset")
        mock_asend_preset_select.assert_called_once_with(
            port_name="Port 1",
            channel=1,
            pgm_value=1,
            cc_value=0,
            cc_number=0,
            sequencer_port=None,
        )

    @patch("server.device_manager.DeviceManager.get_preset_by_name")
    def test_send_preset_not_found(self, mock_get_preset_by_name, client):
        """Test the POST /preset endpoint when the preset is not found"""
        # Set up mock to return None (preset not found)
        mock_get_preset_by_name.return_value = None

        # Make the request
        response = client.post(
            "/preset",
            json={
                "preset_name": "Non-existent Preset",
                "midi_port": "Port 1",
                "midi_channel": 1,
            },
        )

        # Verify the response
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()

    @patch("server.device_manager.DeviceManager.get_preset_by_name")
    def test_send_preset_missing_values(self, mock_get_preset_by_name, client):
        """Test the POST /preset endpoint when cc_0 or pgm values are missing"""
        # Set up mock to return a preset without cc_0 or pgm
        mock_get_preset_by_name.return_value = {"preset_name": "Test Preset"}

        # Make the request
        response = client.post(
            "/preset",
            json={
                "preset_name": "Test Preset",
                "midi_port": "Port 1",
                "midi_channel": 1,
            },
        )

        # Verify the response
        assert response.status_code == 400
        assert "missing" in response.json()["detail"].lower()


if __name__ == "__main__":
    unittest.main()
