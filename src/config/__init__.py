"""
Configuration module that handles environment variables and secrets.
"""

from __future__ import annotations

from .base import Config

config = Config()

__all__ = ["Config", "config"]
