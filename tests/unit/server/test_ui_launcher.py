import os
import subprocess
import sys
import time
import unittest
from unittest.mock import MagicMock, call, patch

import pytest
from server.ui_launcher import UILauncher

pytestmark = pytest.mark.server


class TestUILauncher(unittest.TestCase):
    """Test cases for the UILauncher class"""

    def setUp(self):
        """Set up test fixtures"""
        # Use a fixed path for testing
        self.test_client_path = "test_client_path"
        self.test_client_path_abs = os.path.abspath(self.test_client_path)
        self.test_client_main = os.path.join(self.test_client_path_abs, "main.py")

        self.ui_launcher = UILauncher(
            client_path=self.test_client_path, server_url="http://localhost:8888"
        )

    def test_init(self):
        """Test initialization of UILauncher"""
        self.assertEqual(
            self.ui_launcher.client_path, os.path.abspath("test_client_path")
        )
        self.assertEqual(self.ui_launcher.server_url, "http://localhost:8888")
        self.assertIsNone(self.ui_launcher.client_process)

    @patch("os.path.exists")
    @patch("os.makedirs")
    @patch("os.path.dirname")
    @patch("os.path.abspath")
    @patch("subprocess.Popen")
    @patch("time.sleep")
    def test_launch_client_success(
        self,
        mock_sleep,
        mock_popen,
        mock_abspath,
        mock_dirname,
        mock_makedirs,
        mock_exists,
    ):
        """Test launching the client successfully"""

        # Set up mocks
        def exists_side_effect(path):
            if path == self.test_client_path_abs or path == self.test_client_main:
                return True
            return True  # Default to True for any other paths

        mock_exists.side_effect = exists_side_effect
        mock_abspath.return_value = "/abs/path/to/ui_launcher.py"
        mock_dirname.return_value = "/abs/path/to"

        # Mock the subprocess.Popen to return a process that's still running
        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Process is still running
        mock_popen.return_value = mock_process

        # Call the method under test
        result = self.ui_launcher.launch_client()

        # Verify the results
        self.assertTrue(result)
        self.assertEqual(self.ui_launcher.client_process, mock_process)

        # Verify that the necessary methods were called
        mock_exists.assert_has_calls(
            [call(self.test_client_path_abs), call(self.test_client_main)]
        )
        mock_makedirs.assert_not_called()  # Should not be called since the directory exists
        # The actual call is os.path.abspath(__file__), which returns the absolute path
        mock_abspath.assert_called()
        # Check that dirname was called with the expected argument, ignoring other calls
        self.assertIn(call("/abs/path/to/ui_launcher.py"), mock_dirname.call_args_list)

        # Verify that Popen was called with the correct arguments
        mock_popen.assert_called_once()
        args, kwargs = mock_popen.call_args
        self.assertEqual(
            args[0],
            [
                sys.executable,
                self.test_client_main,
                "--server-url",
                "http://localhost:8888",
            ],
        )
        self.assertEqual(kwargs["stdout"], subprocess.PIPE)
        self.assertEqual(kwargs["stderr"], subprocess.PIPE)
        self.assertEqual(kwargs["text"], True)
        self.assertEqual(kwargs["env"]["PYTHONPATH"], "/abs/path/to")

    @patch("os.path.exists")
    @patch("os.makedirs")
    @patch("os.path.dirname")
    @patch("os.path.abspath")
    def test_launch_client_no_client_main(
        self, mock_abspath, mock_dirname, mock_makedirs, mock_exists
    ):
        """Test launching the client when the client main file doesn't exist"""

        # Set up mocks
        def exists_side_effect(path):
            if path == self.test_client_path_abs:
                return True
            if path == self.test_client_main:
                return False
            return True  # Default to True for any other paths

        mock_exists.side_effect = exists_side_effect
        mock_abspath.return_value = "/abs/path/to/ui_launcher.py"
        mock_dirname.return_value = "/abs/path/to"

        # Call the method under test
        result = self.ui_launcher.launch_client()

        # Verify the results
        self.assertFalse(result)
        self.assertIsNone(self.ui_launcher.client_process)

        # Verify that the necessary methods were called
        mock_exists.assert_has_calls(
            [call(self.test_client_path_abs), call(self.test_client_main)],
            any_order=False,
        )
        mock_makedirs.assert_not_called()  # Should not be called since the directory exists

    @patch("os.path.exists")
    @patch("os.makedirs")
    @patch("os.path.dirname")
    @patch("os.path.abspath")
    @patch("subprocess.Popen")
    @patch("time.sleep")
    def test_launch_client_process_fails(
        self,
        mock_sleep,
        mock_popen,
        mock_abspath,
        mock_dirname,
        mock_makedirs,
        mock_exists,
    ):
        """Test launching the client when the process fails to start"""

        # Set up mocks
        def exists_side_effect(path):
            if path == self.test_client_path_abs or path == self.test_client_main:
                return True
            return True  # Default to True for any other paths

        mock_exists.side_effect = exists_side_effect
        mock_abspath.return_value = "/abs/path/to/ui_launcher.py"
        mock_dirname.return_value = "/abs/path/to"

        # Mock the subprocess.Popen to return a process that failed to start
        mock_process = MagicMock()
        mock_process.poll.return_value = 1  # Process exited with error
        mock_process.communicate.return_value = ("", "Error starting process")
        mock_popen.return_value = mock_process

        # Call the method under test
        result = self.ui_launcher.launch_client()

        # Verify the results
        self.assertFalse(result)

        # Verify that the necessary methods were called
        mock_exists.assert_has_calls(
            [call(self.test_client_path_abs), call(self.test_client_main)],
            any_order=False,
        )
        mock_popen.assert_called_once()
        mock_process.communicate.assert_called_once()

    @patch("os.path.exists")
    @patch("os.makedirs")
    @patch("os.path.dirname")
    @patch("os.path.abspath")
    def test_launch_client_create_directory(
        self, mock_abspath, mock_dirname, mock_makedirs, mock_exists
    ):
        """Test launching the client when the client directory doesn't exist"""

        # Set up mocks
        # Use a function for side_effect to handle any number of calls
        def exists_side_effect(path):
            if path == self.test_client_path_abs or path == self.test_client_main:
                return False
            return True  # Default to True for any other paths

        mock_exists.side_effect = exists_side_effect
        mock_abspath.return_value = "/abs/path/to/ui_launcher.py"
        mock_dirname.return_value = "/abs/path/to"

        # Call the method under test
        result = self.ui_launcher.launch_client()

        # Verify the results
        self.assertFalse(result)

        # Verify that the necessary methods were called
        mock_exists.assert_has_calls(
            [call(self.test_client_path_abs), call(self.test_client_main)],
            any_order=True,
        )
        mock_makedirs.assert_called_once_with(self.test_client_path_abs, exist_ok=True)

    def test_shutdown_client_no_process(self):
        """Test shutting down the client when there's no process"""
        # Call the method under test
        self.ui_launcher.shutdown_client()

        # Verify that nothing happened (no exceptions)
        self.assertIsNone(self.ui_launcher.client_process)

    def test_shutdown_client_timeout(self):
        """Test shutting down the client when the process times out"""
        # Set up a mock process
        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Process is still running
        # Make wait raise TimeoutExpired when called with timeout=5
        mock_process.wait = MagicMock(side_effect=subprocess.TimeoutExpired("cmd", 5))
        self.ui_launcher.client_process = mock_process

        # Call the method under test
        self.ui_launcher.shutdown_client()

        # Verify that the process was terminated and then killed
        mock_process.terminate.assert_called_once()
        mock_process.wait.assert_called_once_with(timeout=5)
        mock_process.kill.assert_called_once()

    def test_shutdown_client_success(self):
        """Test shutting down the client successfully"""
        # Set up a mock process
        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Process is still running
        self.ui_launcher.client_process = mock_process

        # Call the method under test
        self.ui_launcher.shutdown_client()

        # Verify that the process was terminated
        mock_process.terminate.assert_called_once()
        mock_process.wait.assert_called_once_with(timeout=5)
        mock_process.kill.assert_not_called()  # Should not be called since wait didn't time out


if __name__ == "__main__":
    unittest.main()
