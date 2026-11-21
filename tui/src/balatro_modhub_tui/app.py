"""The Textual application."""

from __future__ import annotations

import asyncio

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import DataTable, Footer, Header, Static

from .collection import Collection, CollectionError
from .models import Mod
from .views.detail import DetailScreen
from .views.doctor import DoctorScreen
from .views.mods import ModsView, SearchInput


class ModHubApp(App):
    """The collection of mods, browsable and manageable from the terminal."""

    TITLE = "Balatro Mod Hub"
    AUTO_FOCUS = "#mods"

    CSS = """
    ModsView {
        height: 1fr;
    }

    #filter {
        margin: 0 1;
    }

    #mods {
        height: 1fr;
    }

    #status {
        height: 1;
        padding: 0 1;
        color: $text-muted;
    }

    #status.-error {
        color: $error;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "reload", "Reload"),
        Binding("space", "toggle", "Enable / disable"),
        Binding("s", "sync", "Sync"),
        Binding("d", "doctor", "Doctor"),
        Binding("/", "focus_filter", "Search"),
    ]

    def __init__(self, collection: Collection) -> None:
        super().__init__()
        self.collection = collection
        self.mods: list[Mod] = []
        self.status: dict[str, object] = {}

    def compose(self) -> ComposeResult:
        yield Header()
        yield ModsView()
        yield Static("", id="status")
        yield Footer()

    async def on_mount(self) -> None:
        missing = Collection.missing_commands()
        if missing:
            self.set_status(f"Missing commands: {', '.join(missing)}", error=True)
            return

        await self.load_state()

    # --- State --------------------------------------------------------------------------------------------------

    async def load_state(self) -> bool:
        """Read the state of the collection and show it."""
        try:
            status = await asyncio.to_thread(self.collection.status)
        except CollectionError as error:
            self.set_status(str(error), error=True)
            return False

        self.status = status
        self.mods = [Mod.from_json(mod) for mod in status.get("mods", [])]
        self.query_one(ModsView).refresh_rows()

        diverged = int(status.get("diverged", 0))
        if diverged:
            self.set_status(f"{len(self.mods)} mod(s), {diverged} out of sync (press s to sync)", error=True)
        else:
            self.set_status(f"{len(self.mods)} mod(s) in the collection")

        return True

    def set_status(self, message: str, error: bool = False) -> None:
        """Show a message at the bottom of the screen."""
        status = self.query_one("#status", Static)
        status.update(message)
        status.set_class(error, "-error")

    @property
    def selected_mod(self) -> Mod | None:
        """The mod under the cursor of the list."""
        return self.query_one(ModsView).selected

    # --- Actions ------------------------------------------------------------------------------------------------

    async def toggle_mod(self, name: str) -> None:
        """Enable or disable a mod and refresh the list."""
        try:
            await asyncio.to_thread(self.collection.toggle, name)
        except CollectionError as error:
            self.set_status(str(error), error=True)
            return

        await self.load_state()

        if self.collection.manifest_dirty():
            self.set_status(f"{name} toggled, the manifest changed (commit it or discard the change)")
        else:
            self.set_status(f"{name} toggled")

    @work
    async def action_reload(self) -> None:
        await self.load_state()

    @work
    async def action_toggle(self) -> None:
        mod = self.selected_mod
        if mod is None:
            return

        await self.toggle_mod(mod.name)

    @work
    async def action_sync(self) -> None:
        try:
            await asyncio.to_thread(self.collection.sync)
        except CollectionError as error:
            self.set_status(str(error), error=True)
            return

        await self.load_state()
        self.set_status("The collection is synced with the manifest")

    @work
    async def action_details(self) -> None:
        mod = self.selected_mod
        if mod is None:
            return

        try:
            info = await asyncio.to_thread(self.collection.info, mod.name)
        except CollectionError as error:
            self.set_status(str(error), error=True)
            return

        shared = [str(name) for name in info.get("shared_checkout_with", [])]
        self.push_screen(DetailScreen(mod, shared))

    def action_focus_filter(self) -> None:
        self.query_one("#filter", SearchInput).focus()

    def action_doctor(self) -> None:
        if isinstance(self.screen, DoctorScreen):
            return

        self.push_screen(DoctorScreen())

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        if event.data_table.id != "mods":
            return

        event.stop()
        self.action_details()
