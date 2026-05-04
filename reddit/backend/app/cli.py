"""Tiny CLI: `python -m app.cli migrate`.

ADR 0004 の通り Alembic を入れない方針なので、`Base.metadata.create_all` を
そのまま migrate コマンドとして提供する。本番運用なら派生 ADR で Alembic 化する。
"""

import asyncio
import sys

from app.main import init_db


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] != "migrate":
        print("usage: python -m app.cli migrate", file=sys.stderr)
        sys.exit(2)
    asyncio.run(init_db())
    print("migrated.")


if __name__ == "__main__":
    main()
