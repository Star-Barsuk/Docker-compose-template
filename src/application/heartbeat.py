"""
Heartbeat service.
"""
import asyncio
import platform
import sys
from datetime import datetime


class HeartbeatService:
    """Manages application heartbeat."""

    def __init__(self, db, config):
        self.db = db
        self.config = config
        self.counter = 0

    async def run(self, should_exit_flag):
        """Run heartbeat loop."""
        while not should_exit_flag():
            self.counter += 1
            await self._heartbeat_cycle()

    async def _heartbeat_cycle(self):
        """Execute a single heartbeat cycle."""
        try:
            await self._insert_heartbeat()
            await self._log_heartbeat_stats()

            # Print connection pool info occasionally
            if self.counter % 10 == 0:
                await self._log_connection_info()

        except Exception as e:
            print(f"❌ Heartbeat failed: {e}")
            self.db.connection_stats["errors"] += 1

            # Try to reconnect on error
            if not self.db.is_connected:
                try:
                    await self.db.connect()
                except:
                    pass

        # Wait for next heartbeat
        await self._wait_next_heartbeat()

    async def _insert_heartbeat(self):
        """Insert heartbeat record."""
        await self.db.execute("""
            INSERT INTO heartbeat (message, counter, environment, metadata)
            VALUES ($1, $2, $3, $4::jsonb)
        """,
            f"heartbeat #{self.counter}",
            self.counter,
            self.config.env,
            '{"host": "' + platform.node() + '", "python_version": "' + sys.version.split()[0] + '"}'
        )

    async def _log_heartbeat_stats(self):
        """Log heartbeat statistics."""
        stats = await self.db.fetchrow("""
            SELECT
                COUNT(*) as total_records,
                MIN(timestamp) as first_record,
                MAX(timestamp) as last_record
            FROM heartbeat
            WHERE environment = $1
        """, self.config.env)

        recent = await self.db.fetch("""
            SELECT
                timestamp,
                message,
                counter
            FROM heartbeat
            WHERE environment = $1
            ORDER BY timestamp DESC
            LIMIT 3
        """, self.config.env)

        current_time = datetime.now()
        print(f"\n💓 Heartbeat #{self.counter} — {current_time.strftime('%H:%M:%S')}")
        print(f"   📊 Database stats:")
        print(f"     • Total records: {stats['total_records']}")
        print(f"     • First: {stats['first_record'].strftime('%H:%M:%S') if stats['first_record'] else 'N/A'}")
        print(f"     • Last: {stats['last_record'].strftime('%H:%M:%S') if stats['last_record'] else 'N/A'}")

        if recent:
            print(f"   📝 Recent activity:")
            for record in recent[:2]:
                print(f"     • {record['timestamp'].strftime('%H:%M:%S')}: {record['message']}")

    async def _log_connection_info(self):
        """Log connection pool information."""
        pool_info = await self.db.fetchrow("""
            SELECT
                COUNT(*) as active_connections,
                (SELECT setting FROM pg_settings WHERE name = 'max_connections') as max_connections
            FROM pg_stat_activity
            WHERE datname = current_database()
        """)
        print(f"   🔌 Connections: {pool_info['active_connections']}/{pool_info['max_connections']}")

    async def _wait_next_heartbeat(self):
        """Wait for next heartbeat interval."""
        interval = self.config.heartbeat_interval
        for _ in range(interval):
            await asyncio.sleep(1)
