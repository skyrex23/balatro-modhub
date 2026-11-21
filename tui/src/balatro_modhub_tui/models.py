"""The data of the collection, as it comes from the JSON output of the scripts."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Mod:
    """A mod of the collection, with the state of the manifest and the state of the real link."""

    name: str
    repo: str
    checkout: str
    path: str
    branch: str
    description: str
    enabled: bool
    linked: bool
    state: str
    commit: str
    source: str
    target: str

    @classmethod
    def from_json(cls, data: dict[str, object]) -> Mod:
        return cls(
            name=str(data.get("name", "")),
            repo=str(data.get("repo", "")),
            checkout=str(data.get("checkout", "")),
            path=str(data.get("path", "")),
            branch=str(data.get("branch", "")),
            description=str(data.get("description", "")),
            enabled=bool(data.get("enabled", False)),
            linked=bool(data.get("linked", False)),
            state=str(data.get("state", "")),
            commit=str(data.get("commit", "")),
            source=str(data.get("source", "")),
            target=str(data.get("target", "")),
        )

    def matches(self, needle: str) -> bool:
        """Whether the mod matches the text of the search box."""
        if not needle:
            return True

        needle = needle.lower()
        fields = (self.name, self.description, self.repo, self.branch, self.checkout)

        return any(needle in field.lower() for field in fields)


@dataclass(frozen=True)
class Check:
    """A check of the environment, with the action that can fix it."""

    id: str
    group: str
    label: str
    status: str
    detail: str
    fix_description: str
    fix_command: str

    @classmethod
    def from_json(cls, data: dict[str, object]) -> Check:
        fix = data.get("fix") or {}

        return cls(
            id=str(data.get("id", "")),
            group=str(data.get("group", "")),
            label=str(data.get("label", "")),
            status=str(data.get("status", "")),
            detail=str(data.get("detail", "")),
            fix_description=str(fix.get("description", "")) if isinstance(fix, dict) else "",
            fix_command=str(fix.get("command", "")) if isinstance(fix, dict) else "",
        )

    @property
    def fixable(self) -> bool:
        """Whether a command can fix the check."""
        return bool(self.fix_command)
