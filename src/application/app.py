"""
Main application class.
"""
import os
import platform
import signal
import sys
from datetime import datetime

import src.config as config
from src.database import DatabaseManager, SchemaManager
from .heartbeat import HeartbeatService


class Application:
    """Main application class."""

    def __init__(self):
        self.db = DatabaseManager()
        self.schema = SchemaManager(self.db)
        self.heartbeat = HeartbeatService(self.db)
        self.should_exit = False
        self.start_time = datetime.now()

    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown."""
        def signal_handler(signum, frame):
            print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
            self.should_exit = True

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

    def _print_startup_info(self):
        """Print application startup information."""
        print("=" * 50)
        print("🚀 Database Application")
        print("=" * 50)
        print(f"🕒 Started at: {self.start_time.isoformat()}")
        print(f"🐍 Python: {sys.version.split()[0]} ({platform.python_implementation()})")
        print(f"💻 OS: {platform.system()} {platform.release()}")
        print(f"📂 Working dir: {os.getcwd()}")
        print(f"🌍 Environment: {config.config.env}")
        print(f"🐳 Docker: {'✅ Yes' if config.config.is_docker else '❌ No'}")
        print(f"🔧 Debug: {'✅ Yes' if config.config.debug else '❌ No'}")
        print("-" * 50)

    async def startup(self):
        """Application startup routine."""
        self._print_startup_info()

        # Connect to database
        await self.db.connect()

        # Initialize schema
        await self.schema.init_schema()

        # Run initial cleanup
        deleted = await self.schema.cleanup_old_records(3)
        if deleted > 0:
            print(f"🧹 Cleaned up {deleted} old records")

    async def shutdown(self):
        """Application shutdown routine."""
        print("\n" + "-" * 50)
        print("🛑 Shutting down application...")

        # Disconnect from database
        await self.db.disconnect()

        # Print statistics
        uptime = datetime.now() - self.start_time
        print(f"📊 Statistics:")
        print(f"   Uptime: {uptime}")
        print(f"   Queries executed: {self.db.connection_stats['queries_executed']}")
        print(f"   Database errors: {self.db.connection_stats['errors']}")

        print("✅ Application shut down successfully")

    async def run(self):
        """Main application runner."""
        self.setup_signal_handlers()

        try:
            await self.startup()
            await self.heartbeat.run(self.should_exit)
        except KeyboardInterrupt:
            print("\n🛑 Keyboard interrupt received")
        except Exception as e:
            print(f"💥 Fatal error: {e}", file=sys.stderr)
            raise
        finally:
            await self.shutdown()
