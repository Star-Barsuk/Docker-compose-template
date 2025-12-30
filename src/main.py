from __future__ import annotations

from datetime import datetime
import os
import platform
import sys
import time


def main() -> None:
    print("=" * 50)
    print("🚀 Database Module — Standalone Runner")
    print("=" * 50)
    print(f"🕒 Started at: {datetime.now().isoformat()}")
    print(f"🐍 Python: {sys.version.split()[0]} ({platform.python_implementation()})")
    print(f"💻 OS: {platform.system()} {platform.release()} ({platform.machine()})")
    print(f"📂 Working dir: {os.getcwd()}")
    print(f"📁 Script location: {os.path.abspath(__file__)}")
    print("-" * 50)

    try:
        print("🟢 Service is running... (Press Ctrl+C to stop)")
        counter = 0
        while True:
            counter += 1
            print(f"   [heartbeat] tick #{counter} — {time.strftime('%H:%M:%S')}")
            time.sleep(5)

    except KeyboardInterrupt:
        print("\n🛑 Received SIGINT (Ctrl+C). Shutting down gracefully...")
    except Exception as e:
        print(f"💥 Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        print("✅ Goodbye! Have a great day 🌟")
        sys.exit(0)


if __name__ == "__main__":
    main()
