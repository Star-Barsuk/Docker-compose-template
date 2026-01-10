"""
Database query manager.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any

import asyncpg

from .connection import DatabaseConnection


class DatabaseManager(DatabaseConnection):
    """Manages database queries and operations."""

    @asynccontextmanager
    async def acquire(self):
        """Acquire a connection from pool."""
        if not self.pool:
            raise RuntimeError("Database not connected")

        conn = await self.pool.acquire()
        try:
            yield conn
        finally:
            await self.pool.release(conn)

    async def execute(self, query: str, *args, timeout: float = 30.0) -> str:
        """Execute a SQL command."""
        try:
            async with self.acquire() as conn:
                result = await conn.execute(query, *args, timeout=timeout)
                self.connection_stats["queries_executed"] += 1
                return result
        except Exception:
            self.connection_stats["errors"] += 1
            raise

    async def fetch(
        self, query: str, *args, timeout: float = 30.0
    ) -> list[asyncpg.Record]:
        """Fetch rows from a query."""
        try:
            async with self.acquire() as conn:
                result = await conn.fetch(query, *args, timeout=timeout)
                self.connection_stats["queries_executed"] += 1
                return result
        except Exception:
            self.connection_stats["errors"] += 1
            raise

    async def fetchrow(
        self, query: str, *args, timeout: float = 30.0
    ) -> asyncpg.Record | None:
        """Fetch a single row."""
        try:
            async with self.acquire() as conn:
                result = await conn.fetchrow(query, *args, timeout=timeout)
                self.connection_stats["queries_executed"] += 1
                return result
        except Exception:
            self.connection_stats["errors"] += 1
            raise

    async def fetchval(self, query: str, *args, timeout: float = 30.0) -> Any:
        """Fetch a single value."""
        try:
            async with self.acquire() as conn:
                result = await conn.fetchval(query, *args, timeout=timeout)
                self.connection_stats["queries_executed"] += 1
                return result
        except Exception:
            self.connection_stats["errors"] += 1
            raise
