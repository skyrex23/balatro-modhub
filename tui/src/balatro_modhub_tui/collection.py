"""Access to the collection: where it is and how to run its scripts."""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

from .models import Check, Mod

MANIFEST = Path("config") / "mods.json"
SCRIPTS_DIR = "scripts"
REQUIRED_COMMANDS = ("bash", "jq", "git")


class CollectionError(Exception):
    """The collection cannot be found, or one of its scripts failed."""


class Collection:
    """The local collection of mods, driven through the scripts of the repository."""

    def __init__(self, root: Path) -> None:
        self.root = root

    # --- Location ------------------------------------------------------------------------------------------------

    @classmethod
    def locate(cls) -> Collection:
        """Find the collection: the environment, the current directory or one of its parents."""
        for candidate in cls._candidates():
            if (candidate / MANIFEST).is_file() and (candidate / SCRIPTS_DIR / "mods.sh").is_file():
                return cls(candidate.resolve())

        raise CollectionError(
            "Could not find the collection. Run the TUI from the repository of the collection "
            "or set COLLECTION_ROOT to its path."
        )

    @staticmethod
    def _candidates() -> list[Path]:
        candidates: list[Path] = []

        from_env = os.environ.get("COLLECTION_ROOT")
        if from_env:
            candidates.append(Path(from_env))

        current = Path.cwd()
        candidates.append(current)
        candidates.extend(current.parents)

        return candidates

    # --- Commands ------------------------------------------------------------------------------------------------

    @staticmethod
    def missing_commands() -> list[str]:
        """The commands the collection needs and that are not installed."""
        return [command for command in REQUIRED_COMMANDS if shutil.which(command) is None]

    def run(self, script: str, *args: str, strict: bool = True) -> dict[str, object]:
        """Run one of the scripts of the collection and return its JSON output."""
        command = ["bash", str(self.root / SCRIPTS_DIR / script), *args, "--json"]
        environment = dict(os.environ, COLLECTION_ROOT=str(self.root))

        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                cwd=self.root,
                env=environment,
                check=False,
            )
        except OSError as error:
            raise CollectionError(f"Could not run {script}: {error}") from error

        output = result.stdout.strip()
        if not output:
            raise CollectionError(result.stderr.strip() or f"{script} did not return any output")

        try:
            payload = json.loads(output)
        except json.JSONDecodeError as error:
            raise CollectionError(f"{script} did not return valid JSON: {error}") from error

        if not isinstance(payload, dict):
            raise CollectionError(f"{script} did not return a JSON object")

        if strict and not payload.get("ok", False):
            raise CollectionError(str(payload.get("error", f"{script} failed")))

        return payload

    def mods(self) -> list[Mod]:
        """Every mod of the collection, with its state."""
        mods = self.run("mods.sh", "list").get("mods", [])

        return [Mod.from_json(mod) for mod in mods]

    def status(self) -> dict[str, object]:
        """A summary of the state of the collection."""
        return self.run("mods.sh", "status")

    def info(self, name: str) -> dict[str, object]:
        """The details of a single mod."""
        return self.run("mods.sh", "info", name)

    def checks(self) -> list[Check]:
        """The checks of the environment."""
        payload = self.run("doctor.sh", strict=False)

        return [Check.from_json(check) for check in payload.get("checks", [])]

    def enable(self, name: str) -> None:
        self.run("mods.sh", "enable", name)

    def disable(self, name: str) -> None:
        self.run("mods.sh", "disable", name)

    def toggle(self, name: str) -> None:
        self.run("mods.sh", "toggle", name)

    def sync(self) -> None:
        self.run("mods.sh", "sync")

    def manifest_dirty(self) -> bool:
        """Whether the manifest has changes that are not committed."""
        result = subprocess.run(
            ["git", "status", "--porcelain", "--", "config/mods.json"],
            capture_output=True,
            text=True,
            cwd=self.root,
            check=False,
        )

        return bool(result.stdout.strip())

    def run_fix(self, command: str) -> tuple[int, str]:
        """Run one of the fix commands of the checks and return its exit code and its output."""
        result = subprocess.run(
            shlex.split(command),
            capture_output=True,
            text=True,
            cwd=self.root,
            check=False,
        )

        return result.returncode, (result.stdout + result.stderr).strip()
