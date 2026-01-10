"""
Database connection handling.
"""

from __future__ import annotations

import asyncio

import asyncpg

from src.config.database import DatabaseConfig


class DatabaseConnection:
    """Handles database connection lifecycle."""

    def __init__(self, db_config: DatabaseConfig):
        self.db_config = db_config
        self.pool: asyncpg.Pool = None
        self.is_connected = False
        self.connection_stats: dict[str, int] = {
            "connections_created": 0,
            "queries_executed": 0,
            "errors": 0,
        }

    async def connect(self, dsn: str = None) -> None:
        """Establish database connection with retry logic."""
        if self.is_connected:
            return

        dsn = dsn or self.db_config.database_url

        print("🔌 Connecting to database...")
        print(f"   URL: {self.db_config.database_url_safe}")
        print(f"   Environment: {self.db_config.config.env}")
        print(f"   Docker: {'✅ Yes' if self.db_config.config.is_docker else '❌ No'}")

        max_retries = 5
        for attempt in range(max_retries):
            try:
                await self._create_pool(dsn)
                await self._test_connection()

                self.is_connected = True
                self.connection_stats["connections_created"] += 1
                return

            except asyncpg.InvalidPasswordError:
                print("❌ Invalid database password")
                raise
            except asyncpg.ConnectionDoesNotExistError:
                print("❌ Database does not exist")
                raise
            except (OSError, asyncpg.PostgresConnectionError) as e:
                if attempt < max_retries - 1:
                    wait_time = 2**attempt
                    print(
                        f"⚠️  Connection failed (attempt {attempt + 1}/{max_retries}): {e}"
                    )
                    print(f"   Retrying in {wait_time} seconds...")
                    await asyncio.sleep(wait_time)
                else:
                    print(f"💥 Failed to connect after {max_retries} attempts")
                    raise

    async def _create_pool(self, dsn: str) -> None:
        """Create connection pool."""
        self.pool = await asyncpg.create_pool(
            dsn=dsn,
            min_size=self.db_config.pool_min_size,
            max_size=self.db_config.pool_max_size,
            command_timeout=self.db_config.connect_timeout,
            statement_cache_size=0,
            server_settings={
                "application_name": f"app-{self.db_config.config.env}",
                "search_path": "public",
                "statement_timeout": "30000",
            },
        )

    async def _test_connection(self) -> None:
        """Test database connection and display information."""
        async with self.pool.acquire() as conn:
            db_info = await conn.fetchrow("""
                SELECT
                    current_database() as db_name,
                    current_user as db_user,
                    version() as version,
                    pg_size_pretty(pg_database_size(current_database())) as size
            """)

            print("✅ Database connected successfully!")
            print(f"   Database: {db_info['db_name']}")
            print(f"   User: {db_info['db_user']}")
            print(f"   Version: {db_info['version'].split(',')[0]}")
            print(f"   Size: {db_info['size']}")

            active_conns = await conn.fetchval(
                "SELECT COUNT(*) FROM pg_stat_activity WHERE datname = current_database()"
            )
            print(f"   Active connections: {active_conns}")

    async def disconnect(self) -> None:
        """Close database connection gracefully."""
        if self.pool:
            await self.pool.close()
            self.is_connected = False
            print("🔌 Database connection closed")
