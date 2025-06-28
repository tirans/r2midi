import logging
import os
import subprocess
import sys
import time
from typing import Optional

# Get logger
logger = logging.getLogger(__name__)


class UILauncher:
    """Responsible for launching the UI client"""

    def __init__(
        self, client_path: str = None, server_url: str = "http://localhost:7777"
    ):
        """
        Initialize the UI launcher

        Args:
            client_path: Path to the client directory (auto-calculated if None)
            server_url: URL of the server to pass to the client
        """
        if client_path is None:
            # Calculate path relative to project structure
            server_dir = os.path.dirname(__file__)
            project_root = os.path.dirname(server_dir)
            client_path = os.path.join(project_root, "r2midi_client")

        self.client_path = os.path.abspath(client_path)
        self.server_url = server_url
        self.client_process = None

    def launch_client(self) -> bool:
        """
        Launch the UI client application

        Returns:
            True if client was launched successfully, False otherwise
        """
        # Ensure the client directory exists
        if not os.path.exists(self.client_path):
            logger.info(f"Creating client directory: {self.client_path}")
            os.makedirs(self.client_path, exist_ok=True)

        # Check if client main.py exists
        client_main = os.path.join(self.client_path, "main.py")
        if not os.path.exists(client_main):
            logger.warning(f"Client main file not found at {client_main}")
            return False

        try:
            # Launch the client in a separate process
            # Add the parent directory to PYTHONPATH to allow importing r2midi_client
            env = os.environ.copy()
            # Set PYTHONPATH to the parent directory so the client can import r2midi_client
            parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            env["PYTHONPATH"] = parent_dir
            logger.info(f"Setting PYTHONPATH to: {parent_dir}")

            client_main = os.path.join(self.client_path, "main.py")
            cmd = [sys.executable, client_main, "--server-url", self.server_url]

            # Use subprocess.Popen to avoid blocking the server
            self.client_process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env
            )

            # Give the process a moment to start
            time.sleep(0.5)

            # Check if the process is still running
            if self.client_process.poll() is None:
                logger.info(
                    f"Client UI launched successfully with PID {self.client_process.pid}"
                )

                # Set a timeout for the client process to start
                start_time = time.time()
                timeout = 10  # 10 seconds timeout

                # Wait for the client process to start or timeout
                while (
                    self.client_process.poll() is None
                    and time.time() - start_time < timeout
                ):
                    time.sleep(0.1)

                # Check if the process is still running after the timeout
                if self.client_process.poll() is None:
                    logger.info(
                        "Client UI is still running after timeout, assuming it started successfully"
                    )
                    return True
                else:
                    stdout, stderr = self.client_process.communicate()
                    logger.error(f"Client UI failed to start within timeout: {stderr}")
                    return False
            else:
                stdout, stderr = self.client_process.communicate()
                logger.error(f"Client UI failed to start: {stderr}")
                return False

        except Exception as e:
            logger.error(f"Error launching client UI: {str(e)}")
            return False

    def shutdown_client(self) -> None:
        """Shutdown the client process if it's running"""
        if self.client_process and self.client_process.poll() is None:
            logger.info("Shutting down client UI...")
            self.client_process.terminate()
            try:
                self.client_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logger.warning("Client UI did not terminate gracefully, forcing kill")
                self.client_process.kill()
