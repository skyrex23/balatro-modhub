"""The list of the mods of the collection, with a search box."""

from __future__ import annotations

from rich.text import Text
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical
from textual.widgets import DataTable, Input

from ..models import Mod

STATE_STYLES = {
    "enabled": "green",
    "disabled": "dim",
    "diverged": "yellow",
    "orphan": "yellow",
}


class SearchInput(Input):
    """The search box of the list."""

    BINDINGS = [Binding("escape", "leave", "Back to the list")]

    def action_leave(self) -> None:
        self.value = ""
        self.screen.query_one("#mods", DataTable).focus()


class ModsView(Vertical):
    """The mods of the collection, filtered by the search box."""

    BINDINGS = [Binding("enter", "details", "Details", priority=True)]

    def compose(self) -> ComposeResult:
        yield SearchInput(placeholder="Search mods", id="filter")
        yield DataTable(id="mods", cursor_type="row")

    def on_mount(self) -> None:
        self.table = self.query_one("#mods", DataTable)
        self.filter = self.query_one("#filter", SearchInput)
        self.table.add_columns("Name", "State", "Branch", "Commit", "Description")
        self.visible_mods: list[Mod] = []
        self.table.focus()

    def on_input_changed(self, event: Input.Changed) -> None:
        self.refresh_rows()

    def refresh_rows(self) -> None:
        """Fill the table with the mods that match the search box."""
        needle = self.filter.value
        selected = self.selected
        previous = selected.name if selected else ""

        self.visible_mods = [mod for mod in self.app.mods if mod.matches(needle)]

        self.table.clear()
        for mod in self.visible_mods:
            self.table.add_row(
                Text(mod.name),
                Text(mod.state, style=STATE_STYLES.get(mod.state, "")),
                mod.branch or "-",
                mod.commit or "-",
                mod.description,
            )

        if not self.visible_mods:
            self.table.add_row(Text("No mods match the search"), "", "", "", "")
            return

        for index, mod in enumerate(self.visible_mods):
            if mod.name == previous:
                self.table.move_cursor(row=index)
                break

    @property
    def selected(self) -> Mod | None:
        """The mod under the cursor, if there is one."""
        index = self.table.cursor_row

        if index < 0 or index >= len(self.visible_mods):
            return None

        return self.visible_mods[index]

    def action_details(self) -> None:
        self.app.action_details()
