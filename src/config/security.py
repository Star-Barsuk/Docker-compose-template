"""
Secret reading utilities.
"""
import os
from pathlib import Path
from typing import Optional


class SecretReader:
    """Handles reading secrets from various sources."""

    def __init__(self, project_root: Optional[Path] = None):
        self.project_root = project_root or Path(__file__).parent.parent.parent

    def read_secret(self, secret_name: str, default: Optional[str] = None) -> str:
        """Read secret from Docker secrets, local files, or environment."""
        # Try Docker secrets first
        docker_secret_path = Path(f"/run/secrets/{secret_name}")
        if docker_secret_path.exists():
            return self._read_file(docker_secret_path)

        # Try local development secrets
        local_secret_path = self.project_root / f"docker/secrets/{secret_name}.txt"
        if local_secret_path.exists():
            return self._read_file(local_secret_path)

        # Fallback to environment variable
        env_var_name = secret_name.upper()
        return os.getenv(env_var_name, default or "")

    def _read_file(self, file_path: Path) -> str:
        """Read and sanitize file content."""
        try:
            with open(file_path) as f:
                return f.read().strip()
        except (IOError, OSError):
            return ""
