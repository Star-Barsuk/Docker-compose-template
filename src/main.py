"""
Main application entry point.
"""
import asyncio
import sys

from src.application import Application


async def main_async():
    """Async entry point."""
    app = Application()
    await app.run()


def main():
    """Main entry point."""
    try:
        asyncio.run(main_async())
    except KeyboardInterrupt:
        print("\n👋 Application terminated by user")
        sys.exit(0)
    except Exception as e:
        print(f"💥 Application failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
