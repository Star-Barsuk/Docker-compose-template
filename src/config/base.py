"""
Base configuration module.
"""
import os
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from .security import SecretReader


class Config:
    """Application configuration base class."""

    def __init__(self, env: Optional[str] = None):
        self.env = env or self._detect_env()

        self._secret_reader = SecretReader()
        self._load_env_file()

    def _load_env_file(self):
        """Load appropriate .env file."""
        project_root = Path(__file__).parent.parent.parent
        env_files = [
            project_root / f"envs/.env.{self.env}",
        ]

        for env_file in env_files:
            if env_file.exists():
                load_dotenv(env_file, override=True)
                print(f"📁 Loaded environment from: {env_file.name}")
                break

    def _detect_env(self) -> str:
        """Detect current environment."""
        active_env_file = Path(__file__).parent.parent.parent / ".active-env"
        if active_env_file.exists():
            with open(active_env_file) as f:
                return f.read().strip()

        return os.getenv("APP_ENV", "local")

    @property
    def is_docker(self) -> bool:
        """Check if running inside Docker."""
        return Path("/.dockerenv").exists() or os.getenv("DOCKER_CONTAINER") == "true"
