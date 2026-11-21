"""Fixtures of the tests: a collection of mods in a temporary directory."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from balatro_modhub_tui.collection import Collection

MANIFEST = {
    "mods": [
        {
            "name": "alpha",
            "repo": "https://example.com/mods",
            "checkout": "shared",
            "path": "alpha",
            "branch": "main",
            "enabled": True,
            "description": "The first mod",
        },
        {
            "name": "beta",
            "repo": "https://example.com/mods",
            "checkout": "shared",
            "path": "beta",
            "branch": "main",
            "enabled": False,
            "description": "The second mod",
        },
    ]
}


@pytest.fixture
def collection_root(tmp_path: Path) -> Path:
    """A collection with two mods that share the same checkout."""
    root = tmp_path / "collection"

    (root / "config").mkdir(parents=True)
    (root / "mods" / "shared" / "alpha").mkdir(parents=True)
    (root / "mods" / "shared" / "beta").mkdir(parents=True)
    (tmp_path / "game").mkdir()
    (tmp_path / "save" / "Mods").mkdir(parents=True)

    (root / "config" / "balatro.env").write_text(
        "\n".join(
            [
                'BALATRO_APP_ID="2379780"',
                "STEAM_LAUNCH_OPTIONS=''",
                f'BALATRO_GAME_DIR="{tmp_path / "game"}"',
                f'BALATRO_SAVE_DIR="{tmp_path / "save"}"',
                'MOD_LINK_MODE="symlink"',
            ]
        )
    )
    (root / "config" / "mods.json").write_text(json.dumps(MANIFEST, indent=2))

    # The scripts of the repository, they read the configuration from COLLECTION_ROOT
    (root / "scripts").symlink_to(Path(__file__).resolve().parents[2] / "scripts")

    return root


@pytest.fixture
def collection(collection_root: Path) -> Collection:
    """The collection of the temporary directory."""
    return Collection(collection_root)
