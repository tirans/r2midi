"""
Configuration management for R2MIDI application
"""

import json
import logging
import os
from dataclasses import asdict, dataclass
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


@dataclass
class AppConfig:
    """Application configuration settings"""

    # Server settings
    server_url: str = "http://localhost:7777"
    server_check_timeout: int = 30
    server_check_retries: int = 30

    # Cache settings
    cache_enabled: bool = True
    cache_timeout: int = 300  # 5 minutes

    # UI settings
    debounce_delay_ms: int = 300
    window_width: int = 800
    window_height: int = 600
    dark_mode: bool = False

    # MIDI settings
    default_midi_channel: int = 1
    auto_select_midi_ports: bool = True

    # Performance settings
    max_presets_display: int = 1000
    enable_lazy_loading: bool = True

    # Debug settings
    debug_mode: bool = False
    log_level: str = "INFO"

    # Feature flags
    enable_favorites: bool = True
    enable_search: bool = True
    enable_keyboard_shortcuts: bool = True

    def to_dict(self) -> Dict[str, Any]:
        """Convert config to dictionary"""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "AppConfig":
        """Create config from dictionary"""
        # Handle legacy config parameter names
        if "max_patches_display" in data:
            data["max_presets_display"] = data.pop("max_patches_display")
        return cls(**data)


class ConfigManager:
    """Manages application configuration with file persistence"""

    DEFAULT_CONFIG_FILENAME = ".r2midi_config.json"

    def __init__(self, config_path: Optional[str] = None):
        """
        Initialize config manager

        Args:
            config_path: Optional path to config file. If not provided,
                        uses ~/.r2midi_config.json
        """
        if config_path is None:
            config_path = os.path.join(
                os.path.expanduser("~"), self.DEFAULT_CONFIG_FILENAME
            )

        self.config_path = config_path
        self.config = self.load_config()

    def load_config(self) -> AppConfig:
        """Load configuration from file or create default"""
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r") as f:
                    data = json.load(f)
                    config = AppConfig.from_dict(data)
                    logger.info(f"Loaded configuration from {self.config_path}")
                    return config
            except Exception as e:
                logger.warning(f"Failed to load config from {self.config_path}: {e}")
                logger.info("Using default configuration")

        # Return default config
        return AppConfig()

    def save_config(self) -> bool:
        """
        Save current configuration to file

        Returns:
            True if successful, False otherwise
        """
        try:
            with open(self.config_path, "w") as f:
                json.dump(self.config.to_dict(), f, indent=2)
            logger.info(f"Saved configuration to {self.config_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to save config to {self.config_path}: {e}")
            return False

    def update_config(self, **kwargs) -> None:
        """
        Update configuration values

        Args:
            **kwargs: Configuration values to update
        """
        for key, value in kwargs.items():
            if hasattr(self.config, key):
                setattr(self.config, key, value)
                logger.debug(f"Updated config: {key} = {value}")
            else:
                logger.warning(f"Unknown config key: {key}")

    def reset_to_defaults(self) -> None:
        """Reset configuration to defaults"""
        self.config = AppConfig()
        logger.info("Reset configuration to defaults")

    def get(self, key: str, default: Any = None) -> Any:
        """
        Get configuration value

        Args:
            key: Configuration key
            default: Default value if key not found

        Returns:
            Configuration value or default
        """
        return getattr(self.config, key, default)

    def export_config(self, export_path: str) -> bool:
        """
        Export configuration to a different file

        Args:
            export_path: Path to export configuration to

        Returns:
            True if successful, False otherwise
        """
        try:
            with open(export_path, "w") as f:
                json.dump(self.config.to_dict(), f, indent=2)
            logger.info(f"Exported configuration to {export_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to export config to {export_path}: {e}")
            return False

    def import_config(self, import_path: str) -> bool:
        """
        Import configuration from a file

        Args:
            import_path: Path to import configuration from

        Returns:
            True if successful, False otherwise
        """
        try:
            with open(import_path, "r") as f:
                data = json.load(f)
                self.config = AppConfig.from_dict(data)
            logger.info(f"Imported configuration from {import_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to import config from {import_path}: {e}")
            return False


# Global config instance
_config_manager = None


def get_config_manager() -> ConfigManager:
    """Get the global config manager instance"""
    global _config_manager
    if _config_manager is None:
        _config_manager = ConfigManager()
    return _config_manager


def get_config() -> AppConfig:
    """Get the current configuration"""
    return get_config_manager().config
