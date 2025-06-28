import json
import subprocess
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from r2midi_client.api_client import CachedApiClient as ApiClient
from r2midi_client.models import Device, Preset

pytestmark = pytest.mark.client


class TestApiClient:
    """Test cases for the ApiClient class"""

    @pytest.fixture
    def api_client(self):
        """Create an ApiClient instance for testing"""
        return ApiClient(base_url="http://test-server:8000")

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient")
    async def test_init(self, mock_async_client):
        """Test initialization of ApiClient"""
        # Create an ApiClient
        client = ApiClient(base_url="http://test-server:8000")

        # Verify the client was initialized correctly
        assert client.base_url == "http://test-server:8000"
        mock_async_client.assert_called_once_with(
            base_url="http://test-server:8000", timeout=10.0
        )

    # The get_devices method has been removed as per the issue requirements
    # Devices should only be fetched via GET to /devices/{manufacturer}

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_presets(self, mock_get, api_client):
        """Test getting presets from the server"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = [
            {"preset_name": "Preset 1", "category": "Category 1", "source": "default"},
            {
                "preset_name": "Preset 2",
                "category": "Category 2",
                "source": "community_folder",
            },
        ]
        mock_get.return_value = mock_response

        # Call the method under test with required manufacturer and device_name parameters
        presets = await api_client.get_presets(
            manufacturer="Manufacturer 1", device_name="Device 1"
        )

        # Verify the results
        assert len(presets) == 2
        assert isinstance(presets[0], Preset)
        assert presets[0].preset_name == "Preset 1"
        assert presets[0].category == "Category 1"
        assert presets[0].source == "default"
        assert presets[1].source == "community_folder"

        # Verify that the API was called correctly with the new endpoint
        mock_get.assert_called_once_with("/presets/Manufacturer 1/Device 1", params={})
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_presets_error(self, mock_get, api_client):
        """Test getting presets with an error"""
        # Set up mock to raise an exception
        mock_get.side_effect = httpx.HTTPError("Test error")

        # Call the method under test with required manufacturer and device_name parameters
        presets = await api_client.get_presets(
            manufacturer="Manufacturer 1", device_name="Device 1"
        )

        # Verify the results
        assert len(presets) == 0

        # Verify that the API was called correctly with the new endpoint
        mock_get.assert_called_once_with("/presets/Manufacturer 1/Device 1", params={})

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_presets_with_params(self, mock_get, api_client):
        """Test getting presets with manufacturer, device_name, and community_folder parameters"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = [
            {"preset_name": "Preset 1", "category": "Category 1", "source": "default"},
            {
                "preset_name": "Preset 2",
                "category": "Category 2",
                "source": "community_folder",
            },
        ]
        mock_get.return_value = mock_response

        # Call the method under test with manufacturer and device_name parameters
        presets = await api_client.get_presets(
            manufacturer="Manufacturer 1", device_name="Device 1"
        )

        # Verify the results
        assert len(presets) == 2

        # Verify that the API was called correctly with the new endpoint
        mock_get.assert_called_once_with("/presets/Manufacturer 1/Device 1", params={})
        mock_response.raise_for_status.assert_called_once()

        # Reset mocks
        mock_get.reset_mock()
        mock_response.raise_for_status.reset_mock()

        # Call the method under test with manufacturer, device_name, and community_folder parameters
        presets = await api_client.get_presets(
            manufacturer="Manufacturer 1",
            device_name="Device 1",
            community_folder="folder1",
        )

        # Verify the results
        assert len(presets) == 2

        # Verify that the API was called correctly with the new endpoint and community_folder parameter
        mock_get.assert_called_once_with(
            "/presets/Manufacturer 1/Device 1", params={"community_folder": "folder1"}
        )
        mock_response.raise_for_status.assert_called_once()

        # Reset mocks
        mock_get.reset_mock()
        mock_response.raise_for_status.reset_mock()

        # Test with missing manufacturer parameter
        presets = await api_client.get_presets(device_name="Device 1")

        # Verify the results - should be empty because both parameters are required
        assert len(presets) == 0

        # Verify that the API was not called
        mock_get.assert_not_called()

        # Reset mocks
        mock_get.reset_mock()

        # Test with missing device_name parameter
        presets = await api_client.get_presets(manufacturer="Manufacturer 1")

        # Verify the results - should be empty because both parameters are required
        assert len(presets) == 0

        # Verify that the API was not called
        mock_get.assert_not_called()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_manufacturers(self, mock_get, api_client):
        """Test getting manufacturers from the server"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = ["Manufacturer 1", "Manufacturer 2"]
        mock_get.return_value = mock_response

        # Call the method under test
        manufacturers = await api_client.get_manufacturers()

        # Verify the results
        assert len(manufacturers) == 2
        assert "Manufacturer 1" in manufacturers
        assert "Manufacturer 2" in manufacturers

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/manufacturers")
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_manufacturers_error(self, mock_get, api_client):
        """Test getting manufacturers with an error"""
        # Set up mock to raise an exception
        mock_get.side_effect = httpx.HTTPError("Test error")

        # Call the method under test
        manufacturers = await api_client.get_manufacturers()

        # Verify the results
        assert len(manufacturers) == 0

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/manufacturers")

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_devices_by_manufacturer(self, mock_get, api_client):
        """Test getting devices by manufacturer from the server"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = ["Device 1", "Device 2"]
        mock_get.return_value = mock_response

        # Call the method under test
        devices = await api_client.get_devices_by_manufacturer("Manufacturer 1")

        # Verify the results
        assert len(devices) == 2
        assert "Device 1" in devices
        assert "Device 2" in devices

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/devices/Manufacturer 1")
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_devices_by_manufacturer_error(self, mock_get, api_client):
        """Test getting devices by manufacturer with an error"""
        # Set up mock to raise an exception
        mock_get.side_effect = httpx.HTTPError("Test error")

        # Call the method under test
        devices = await api_client.get_devices_by_manufacturer("Manufacturer 1")

        # Verify the results
        assert len(devices) == 0

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/devices/Manufacturer 1")

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_community_folders(self, mock_get, api_client):
        """Test getting community folders from the server"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = ["folder1", "folder2"]
        mock_get.return_value = mock_response

        # Call the method under test
        folders = await api_client.get_community_folders("Device 1")

        # Verify the results
        assert len(folders) == 2
        assert "folder1" in folders
        assert "folder2" in folders

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/community_folders/Device 1")
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_community_folders_error(self, mock_get, api_client):
        """Test getting community folders with an error"""
        # Set up mock to raise an exception
        mock_get.side_effect = httpx.HTTPError("Test error")

        # Call the method under test
        folders = await api_client.get_community_folders("Device 1")

        # Verify the results
        assert len(folders) == 0

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/community_folders/Device 1")

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_midi_ports(self, mock_get, api_client):
        """Test getting MIDI ports from the server"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "in": ["In Port 1", "In Port 2"],
            "out": ["Out Port 1", "Out Port 2"],
        }
        mock_get.return_value = mock_response

        # Call the method under test
        ports = await api_client.get_midi_ports()

        # Verify the results
        assert len(ports["in"]) == 2
        assert len(ports["out"]) == 2
        assert ports["in"][0] == "In Port 1"
        assert ports["out"][0] == "Out Port 1"

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/midi_ports")
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_get_midi_ports_error(self, mock_get, api_client):
        """Test getting MIDI ports with an error"""
        # Set up mock to raise an exception
        mock_get.side_effect = httpx.HTTPError("Test error")

        # Call the method under test
        ports = await api_client.get_midi_ports()

        # Verify the results
        assert len(ports["in"]) == 0
        assert len(ports["out"]) == 0

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/midi_ports")

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.post")
    async def test_send_preset(self, mock_post, api_client):
        """Test sending a preset to the server"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "success",
            "message": "Command executed successfully",
        }
        mock_post.return_value = mock_response

        # Call the method under test
        result = await api_client.send_preset(
            preset_name="Test Preset", midi_port="Port 1", midi_channel=1
        )

        # Verify the results
        assert result["status"] == "success"
        assert result["message"] == "Command executed successfully"

        # Verify that the API was called correctly
        mock_post.assert_called_once_with(
            "/preset",
            json={
                "preset_name": "Test Preset",
                "midi_port": "Port 1",
                "midi_channel": 1,
            },
        )
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.post")
    async def test_send_preset_with_sequencer(self, mock_post, api_client):
        """Test sending a preset with a sequencer port"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "success",
            "message": "Command executed successfully",
        }
        mock_post.return_value = mock_response

        # Call the method under test
        result = await api_client.send_preset(
            preset_name="Test Preset",
            midi_port="Port 1",
            midi_channel=1,
            sequencer_port="Sequencer Port",
        )

        # Verify the results
        assert result["status"] == "success"
        assert result["message"] == "Command executed successfully"

        # Verify that the API was called correctly
        mock_post.assert_called_once_with(
            "/preset",
            json={
                "preset_name": "Test Preset",
                "midi_port": "Port 1",
                "midi_channel": 1,
                "sequencer_port": "Sequencer Port",
            },
        )
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.post")
    async def test_send_preset_error(self, mock_post, api_client):
        """Test sending a preset with an error"""
        # Set up mock to raise an exception with a response
        mock_response = MagicMock()
        mock_response.json.return_value = {"detail": "Test error"}
        mock_error = httpx.HTTPError("Test error")
        mock_error.response = mock_response
        mock_post.side_effect = mock_error

        # Call the method under test
        result = await api_client.send_preset(
            preset_name="Test Preset", midi_port="Port 1", midi_channel=1
        )

        # Verify the results
        assert result["status"] == "error"
        assert result["message"] == "Test error"

        # Verify that the API was called correctly
        mock_post.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.post")
    async def test_send_preset_error_no_json(self, mock_post, api_client):
        """Test sending a preset with an error that doesn't have JSON response"""
        # Set up mock to raise an exception without a valid JSON response
        mock_response = MagicMock()
        mock_response.json.side_effect = json.JSONDecodeError("Test error", "", 0)
        mock_error = httpx.HTTPError("Test error")
        mock_error.response = mock_response
        mock_post.side_effect = mock_error

        # Call the method under test
        result = await api_client.send_preset(
            preset_name="Test Preset", midi_port="Port 1", midi_channel=1
        )

        # Verify the results
        assert result["status"] == "error"
        assert "Test error" in result["message"]

        # Verify that the API was called correctly
        mock_post.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_run_git_sync(self, mock_get, api_client):
        """Test running git sync"""
        # Set up mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "success",
            "message": "Git sync completed successfully",
        }
        mock_get.return_value = mock_response

        # Call the method under test
        success, message = await api_client.run_git_sync()

        # Verify the results
        assert success is True
        assert "successfully" in message

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/git/sync", params={"sync_enabled": True})
        mock_response.raise_for_status.assert_called_once()

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.get")
    async def test_run_git_sync_error(self, mock_get, api_client):
        """Test running git sync with an error"""
        # Set up mock to raise an exception
        mock_error = httpx.HTTPError("Test error")
        mock_get.side_effect = mock_error

        # Call the method under test
        success, message = await api_client.run_git_sync()

        # Verify the results
        assert success is False
        assert "Error calling git sync REST API" in message

        # Verify that the API was called correctly
        mock_get.assert_called_once_with("/git/sync", params={"sync_enabled": True})

    def test_save_ui_state(self, api_client):
        """Test saving UI state"""
        # Create a UI state
        from r2midi_client.models import UIState

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

        # Call the method under test
        api_client.save_ui_state(ui_state)

        # Verify the results
        assert api_client.ui_state == ui_state

    def test_get_ui_state(self, api_client):
        """Test getting UI state"""
        # Set up a UI state
        from r2midi_client.models import UIState

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
        api_client.ui_state = ui_state

        # Call the method under test
        result = api_client.get_ui_state()

        # Verify the results
        assert result == ui_state

    @pytest.mark.asyncio
    @patch("httpx.AsyncClient.aclose")
    async def test_close(self, mock_aclose, api_client):
        """Test closing the API client"""
        # Call the method under test
        await api_client.close()

        # Verify that aclose was called
        mock_aclose.assert_called_once()
