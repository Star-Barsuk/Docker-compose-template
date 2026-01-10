"""
Database schema management.
"""
from .manager import DatabaseManager


class SchemaManager:
    """Manages database schema initialization."""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    async def init_schema(self) -> None:
        """Initialize database schema."""
        print("📐 Initializing database schema...")

        try:
            await self._create_heartbeat_table()
            await self._create_indexes()
            await self._create_cleanup_function()

            print("✅ Database schema initialized")

        except Exception as e:
            print(f"❌ Schema initialization failed: {e}")
            raise

    async def _create_heartbeat_table(self) -> None:
        """Create heartbeat table."""
        await self.db.execute("""
            CREATE TABLE IF NOT EXISTS heartbeat (
                id BIGSERIAL PRIMARY KEY,
                timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                message TEXT NOT NULL,
                counter INTEGER NOT NULL,
                environment VARCHAR(50) NOT NULL DEFAULT 'unknown',
                metadata JSONB DEFAULT '{}'::jsonb
            )
        """)

    async def _create_indexes(self) -> None:
        """Create indexes for heartbeat table."""
        await self.db.execute("""
            CREATE INDEX IF NOT EXISTS idx_heartbeat_timestamp
            ON heartbeat(timestamp DESC)
        """)

        await self.db.execute("""
            CREATE INDEX IF NOT EXISTS idx_heartbeat_environment
            ON heartbeat(environment)
        """)

    async def _create_cleanup_function(self) -> None:
        """Create cleanup function."""
        await self.db.execute("""
            CREATE OR REPLACE FUNCTION cleanup_old_heartbeats(
                keep_days INTEGER DEFAULT 7
            ) RETURNS INTEGER AS $$
            DECLARE
                deleted_count INTEGER;
            BEGIN
                DELETE FROM heartbeat
                WHERE timestamp < NOW() - (keep_days || ' days')::INTERVAL
                RETURNING COUNT(*) INTO deleted_count;

                RETURN deleted_count;
            END;
            $$ LANGUAGE plpgsql;
        """)

    async def cleanup_old_records(self, keep_days: int = 3) -> int:
        """Clean up old heartbeat records."""
        try:
            deleted = await self.db.fetchval(
                "SELECT cleanup_old_heartbeats($1)",
                keep_days
            )
            return deleted or 0
        except Exception:
            return 0
