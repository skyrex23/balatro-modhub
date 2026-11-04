# Balatro mods collection

Personal collection of [Balatro](https://www.playbalatro.com/) mods with the tooling to enable, disable and update them.

Every mod lives in its own upstream repository and is added here as a **git submodule**, so the state of the collection
(which mods exist, which ones are enabled and at which version) is versioned in a single place.

## Requirements

- [Task](https://taskfile.dev) (`task`)
- `git`, `jq`, `curl`, `unzip`
- Balatro installed through Steam (on Linux, via Proton) and [Steamodded](https://github.com/Steamodded/smods) +
  [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector)

## Getting started

```bash
git clone --recurse-submodules <this-repo> ~/balatro-mods-collection
cd ~/balatro-mods-collection
task setup
```

`task setup` installs the loader (Lovely + Steamodded) and applies the state of the manifest to the Balatro `Mods`
folder.

Afterwards you have to set the launch options in Steam, **only once**:

```
WINEDLLOVERRIDES="winmm=n,b" %command%
```

> In Steam: `Balatro` → `Properties` → `General` → `Launch Options`.

Finally, `task run` launches the game.

## Layout

```
.
├── Taskfile.yaml         Main tasks
├── taskfiles/
│   ├── loader.yaml       Loader tasks (Lovely + Steamodded)
│   └── mods.yaml         Mod tasks
├── scripts/
│   ├── lib/common.sh     Shared helpers (config, path detection, manifest)
│   ├── doctor.sh         Environment check
│   ├── loader.sh         Loader installation and updates
│   ├── logs.sh           Lovely and Steamodded logs
│   └── mods.sh           Mod management
├── config/
│   ├── balatro.env       Default configuration
│   ├── balatro.local.env Local overrides (not versioned)
│   └── mods.json         Collection manifest
└── mods/                 One submodule per mod repository
```

## Tasks

| Task                                 | What it does                                            |
| ------------------------------------ | ------------------------------------------------------- |
| `task setup`                         | Installs the loader and syncs the mods                  |
| `task doctor`                        | Checks dependencies, paths and loader state             |
| `task status`                        | Lists the mods and the loader state                     |
| `task run`                           | Launches Balatro through Steam                          |
| `task logs`                          | Shows the most recent log of the loader                 |
| `task mods:list`                     | Lists the mods with their state                         |
| `task mods:info -- <name>`           | Details of a single mod                                 |
| `task mods:enable -- <name>`         | Enables a mod                                           |
| `task mods:disable -- <name>`        | Disables a mod                                          |
| `task mods:toggle -- <name>`         | Toggles the state of a mod                              |
| `task mods:sync`                     | Applies the manifest state to the Balatro `Mods` folder |
| `task mods:update -- [name...]`      | Updates the mods from their upstream repositories       |
| `task mods:add -- <name> <repo> ...` | Adds a mod as a submodule                               |
| `task mods:remove -- <name>`         | Removes a mod from the collection                       |
| `task loader:install`                | Installs Lovely and Steamodded                          |
| `task loader:update`                 | Updates Lovely and Steamodded                           |
| `task loader:uninstall`              | Removes Lovely and Steamodded                           |

> Task treats the arguments that follow the task name as additional tasks, so the arguments of the mod tasks go after
> `--`. They can also be passed as variables: `task mods:enable mod_name=first-round-joker`.

## How enabling and disabling works

The mod always stays in `mods/<checkout>/<path>` inside this repository. Enabling it means linking it (symlink) into the
Balatro `Mods` folder:

```
~/.steam/steam/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro/
└── Mods
    ├── smods            ← Steamodded (the loader)
    └── first-round-joker → .../balatro-mods-collection/mods/first-round-joker/first-round-joker
```

The advantage of the symlink: updating a mod is a `git pull` and the change is visible instantly, without copying
anything again.

If the game did not follow symlinks (it does with Proton), the behaviour can be switched to copies in
`config/balatro.local.env`:

```bash
MOD_LINK_MODE="copy"
```

Mods installed by hand inside the `Mods` folder are never touched: `task mods:sync` lists them as _foreign entries_ and
leaves them alone.

Steamodded also has its own switch inside the game (`MODS` menu), which disables a mod with a `.lovelyignore` file. Both
mechanisms coexist: the symlink decides whether the mod is available and the in-game switch decides whether it is
loaded.

## Adding a mod

```bash
task mods:add -- balatro-plus https://github.com/SomeCoder99/balatro-plus . main "Description of the mod"
```

Arguments: `<name> <repo> [path] [branch] [description]`.

- `name`: name of the mod, it is the folder name inside `Mods`.
- `repo`: URL of the upstream repository.
- `path`: folder of the mod inside the repository, useful when a repository groups several mods (`.` by default).
- `branch`: branch to follow (the repository default when omitted).

The mod is added as a submodule in `mods/<name>` and registered in `config/mods.json`. Afterwards you have to commit
`.gitmodules`, `config/mods.json` and the submodule pointer.

If the repository is already part of the collection, the new mod reuses the same checkout and only changes the `path`.

## Updating the mods

```bash
task mods:update              # all of them
task mods:update -- balatro-plus   # only one
```

The mods are updated with `git submodule update --remote`, following the branch configured in `.gitmodules`. The
submodule pointer is left modified in the index: review it and commit when the state is the one you want.

## Configuration

`config/balatro.env` holds the default values and `config/balatro.local.env` (not versioned) the local overrides:

| Variable                   | Default       | What it is                                   |
| -------------------------- | ------------- | -------------------------------------------- |
| `BALATRO_APP_ID`           | `2379780`     | Steam app id of Balatro                      |
| `BALATRO_GAME_DIR`         | auto-detected | Game folder (the one with `Balatro.exe`)     |
| `BALATRO_SAVE_DIR`         | auto-detected | Save folder (the one with the `Mods` folder) |
| `MOD_LINK_MODE`            | `symlink`     | `symlink` or `copy`                          |
| `SUBMODULE_INIT_RECURSIVE` | `false`       | Initialize the submodules of the mods        |

## Troubleshooting

**The game does not show the `MODS` button.** Steamodded is not installed or `winmm.dll` is missing. Check `task doctor`
and `task loader:status`.

**Steamodded does not see the mods.** The symlink has to point to the folder that contains the mod, not to its parent.
Check `task mods:info -- <name>` and that the `Mods` folder of the game contains the files of the mod.

**The mods do not show up after cloning the repository.** The submodules are not initialized:
`git submodule update --init`.

**A mod does not load.** Look at `task logs`: Steamodded writes the loading errors in the Lovely log.

## License

The code of this repository is under the [MIT license](./LICENSE). Every mod keeps the license of its upstream
repository.
