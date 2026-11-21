"""Tests of the TUI, against a collection in a temporary directory."""

from __future__ import annotations

import asyncio
import shutil
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest

from balatro_modhub_tui.app import ModHubApp
from balatro_modhub_tui.collection import Collection, CollectionError
from balatro_modhub_tui.views.mods import ModsView

Condition = Callable[[], bool]


async def wait_for(pilot: Any, condition: Condition, timeout: float = 15) -> bool:
    """Wait until a condition is true, giving the workers time to finish."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout

    while loop.time() < deadline:
        if condition():
            return True
        await pilot.pause()
        await asyncio.sleep(0.05)

    return False


def make_app(collection: Collection) -> ModHubApp:
    return ModHubApp(collection)


def test_list_shows_the_mods(collection: Collection) -> None:
    async def scenario() -> None:
        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)
            assert app.query_one("#mods").row_count == 2
            assert app.query_one("#status").content == "2 mod(s), 1 out of sync (press s to sync)"

    asyncio.run(scenario())


def test_search_filters_the_mods(collection: Collection) -> None:
    async def scenario() -> None:
        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)

            await pilot.press("/")
            for key in "alpha":
                await pilot.press(key)
            await pilot.pause()

            assert app.query_one("#mods").row_count == 1
            assert app.query_one(ModsView).selected.name == "alpha"

            await pilot.press("escape")
            assert app.query_one("#mods").row_count == 2

    asyncio.run(scenario())


def test_toggle_enables_and_disables_a_mod(collection: Collection, collection_root: Path) -> None:
    async def scenario() -> None:
        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)

            # alpha is enabled in the manifest but it is not linked yet
            assert app.mods[0].state == "diverged"

            await pilot.press("space")
            assert await wait_for(pilot, lambda: app.mods[0].state == "disabled")
            assert not (collection_root.parent / "save" / "Mods" / "alpha").exists()

            await pilot.press("space")
            assert await wait_for(pilot, lambda: app.mods[0].state == "enabled")
            assert (collection_root.parent / "save" / "Mods" / "alpha").is_symlink()

    asyncio.run(scenario())


def test_sync_repairs_the_diverged_mods(collection: Collection, collection_root: Path) -> None:
    async def scenario() -> None:
        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)
            assert app.mods[0].state == "diverged"

            await pilot.press("s")
            assert await wait_for(pilot, lambda: app.mods[0].state == "enabled")
            assert (collection_root.parent / "save" / "Mods" / "alpha").is_symlink()

    asyncio.run(scenario())


def test_details_show_the_mod(collection: Collection) -> None:
    async def scenario() -> None:
        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)

            await pilot.press("enter")
            assert await wait_for(pilot, lambda: app.screen.__class__.__name__ == "DetailScreen")

            details = app.screen.query_one("#details").content
            assert "alpha" in details
            assert "The first mod" in details
            assert "beta" in details

            await pilot.press("escape")
            assert await wait_for(pilot, lambda: app.screen.__class__.__name__ == "Screen")

    asyncio.run(scenario())


def test_doctor_lists_the_checks(collection: Collection) -> None:
    async def scenario() -> None:
        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)

            await pilot.press("d")
            assert await wait_for(pilot, lambda: app.screen.__class__.__name__ == "DoctorScreen")
            assert await wait_for(pilot, lambda: app.screen.query_one("#checks").row_count > 0)

            checks = app.screen.checks
            assert any(check.id == "collection.manifest" for check in checks)
            assert any(check.fixable for check in checks)

            await pilot.press("escape")
            assert await wait_for(pilot, lambda: app.screen.__class__.__name__ == "Screen")

    asyncio.run(scenario())


def test_the_collection_is_not_found_outside_of_it(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("COLLECTION_ROOT", raising=False)

    with pytest.raises(CollectionError):
        Collection.locate()


def test_the_doctor_runs_the_fix_of_a_check(collection: Collection, collection_root: Path) -> None:
    async def scenario() -> None:
        mods_dir = collection_root.parent / "save" / "Mods"
        shutil.rmtree(mods_dir)

        app = make_app(collection)
        async with app.run_test() as pilot:
            assert await wait_for(pilot, lambda: len(app.mods) == 2)

            await pilot.press("d")
            assert await wait_for(pilot, lambda: app.screen.__class__.__name__ == "DoctorScreen")
            assert await wait_for(pilot, lambda: app.screen.query_one("#checks").row_count > 0)

            checks = app.screen.checks
            index = next(index for index, check in enumerate(checks) if check.id == "path.mods_dir")
            assert checks[index].fixable

            app.screen.query_one("#checks").move_cursor(row=index)
            await pilot.press("enter")

            assert await wait_for(pilot, lambda: bool(app.screen.query_one("#log").content))
            assert await wait_for(pilot, lambda: mods_dir.is_dir())

    asyncio.run(scenario())
