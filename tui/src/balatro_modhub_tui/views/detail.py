"""The details of a single mod."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.screen import ModalScreen
from textual.widgets import Footer, Static

from ..models import Mod


class DetailScreen(ModalScreen):
    """The details of a mod, with the state of the manifest and the state of the real link."""

    BINDINGS = [
        Binding("escape", "dismiss", "Close"),
        Binding("space", "toggle", "Enable / disable"),
    ]

    CSS = """
    DetailScreen {
        align: center middle;
    }

    #details {
        width: 80%;
        max-width: 110;
        height: auto;
        max-height: 80%;
        border: thick $primary;
        padding: 1 2;
        overflow-y: auto;
    }
    """

    def __init__(self, mod: Mod, shared: list[str]) -> None:
        super().__init__()
        self.mod = mod
        self.shared = shared

    def compose(self) -> ComposeResult:
        yield Static(self.render_details(), id="details")
        yield Footer()

    def render_details(self) -> str:
        """The details of the mod, as text."""
        mod = self.mod

        lines = [
            f"[b]{mod.name}[/b]",
            "",
            f"state:       {mod.state}",
            f"description: {mod.description}",
            f"repo:        {mod.repo}",
            f"branch:      {mod.branch}",
            f"commit:      {mod.commit}",
            f"checkout:    {mod.checkout}",
            f"path:        {mod.path}",
            f"source:      {mod.source}",
            f"target:      {mod.target}",
        ]

        if self.shared:
            lines += ["", f"shared with:  {', '.join(self.shared)}"]

        return "\n".join(lines)

    async def action_toggle(self) -> None:
        await self.app.toggle_mod(self.mod.name)
        self.dismiss()
