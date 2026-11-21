"""The checks of the environment, with the action that can fix each one."""

from __future__ import annotations

import asyncio

from rich.text import Text
from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import DataTable, Footer, Static

from ..collection import CollectionError
from ..models import Check

STATUS_STYLES = {
    "ok": ("green", "✓"),
    "warn": ("yellow", "!"),
    "fail": ("red", "✗"),
}


class DoctorScreen(Screen):
    """The checks of the environment, as a guided checklist."""

    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("r", "refresh", "Check again"),
        Binding("enter", "fix", "Fix", priority=True),
    ]

    CSS = """
    DoctorScreen {
        layout: vertical;
    }

    #checks {
        height: 1fr;
    }

    #log {
        height: 10;
        border: solid $warning;
        overflow-y: auto;
        padding: 0 1;
    }
    """

    def __init__(self) -> None:
        super().__init__()
        self.checks: list[Check] = []

    def compose(self) -> ComposeResult:
        yield DataTable(id="checks", cursor_type="row")
        yield Static("", id="log")
        yield Footer()

    async def on_mount(self) -> None:
        table = self.query_one("#checks", DataTable)
        table.add_columns("Group", "Check", "Status", "Detail", "Fix")

        await self.load_checks()

    # --- Checks -------------------------------------------------------------------------------------------------

    async def load_checks(self) -> None:
        """Run the checks of the environment and show them."""
        try:
            checks = await asyncio.to_thread(self.app.collection.checks)
        except CollectionError as error:
            self.query_one("#log", Static).update(str(error))
            return

        self.checks = checks
        self.refresh_rows()

    def refresh_rows(self) -> None:
        """Fill the table with the checks."""
        table = self.query_one("#checks", DataTable)
        table.clear()

        for check in self.checks:
            style, icon = STATUS_STYLES.get(check.status, ("", "·"))
            table.add_row(
                check.group,
                check.label,
                Text(f"{icon} {check.status}", style=style),
                check.detail,
                check.fix_description or "-",
            )

    @property
    def selected(self) -> Check | None:
        """The check under the cursor, if there is one."""
        index = self.query_one("#checks", DataTable).cursor_row

        if index < 0 or index >= len(self.checks):
            return None

        return self.checks[index]

    # --- Actions ------------------------------------------------------------------------------------------------

    def action_back(self) -> None:
        self.app.pop_screen()

    @work
    async def action_refresh(self) -> None:
        await self.load_checks()

    @work
    async def action_fix(self) -> None:
        check = self.selected
        if check is None or not check.fixable:
            return

        code, output = await asyncio.to_thread(self.app.collection.run_fix, check.fix_command)

        if code == 0:
            message = f"$ {check.fix_command}\n{output}"
        else:
            message = f"$ {check.fix_command}\n{output}\nThe command failed with the exit code {code}"

        self.query_one("#log", Static).update(message)

        await self.load_checks()
