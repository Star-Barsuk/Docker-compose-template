"""
Configuration module that handles environment variables and secrets.
"""
from .base import Config

config = Config()

__all__ = ['Config', 'config']
