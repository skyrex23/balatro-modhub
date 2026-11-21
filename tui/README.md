# Balatro Mod Hub TUI

Terminal interface to browse and manage the collection of mods of the [Balatro Mod Hub](../README.md).

The TUI does not reimplement the logic of the collection: it reads the JSON output of the scripts of the repository
(`mods.sh`, `doctor.sh`) and calls them for the changes. The scripts stay the single source of truth.

## Install

With [uv](https://docs.astral.sh/uv/):

```bash
uv tool install ./tui
```

From the repository, without installing it:

```bash
uv run --project tui balatro-modhub
```

## Run

The TUI looks for the collection in the current directory and its parents, or in `COLLECTION_ROOT`:

```bash
cd ~/balatro-modhub
balatro-modhub
```

## Keys

| Key     | Action                    |
| ------- | ------------------------- |
| `/`     | Search                    |
| `space` | Enable or disable the mod |
| `enter` | Details of the mod        |
| `s`     | Sync the collection       |
| `d`     | Checks of the environment |
| `r`     | Reload                    |
| `q`     | Quit                      |
