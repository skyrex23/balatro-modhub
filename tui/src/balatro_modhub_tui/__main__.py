"""The entry point of the TUI."""

from __future__ import annotations

import sys

from .app import ModHubApp
from .collection import Collection, CollectionError


def main() -> int:
    try:
        collection = Collection.locate()
    except CollectionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    ModHubApp(collection).run()

    return 0


if __name__ == "__main__":
    sys.exit(main())
