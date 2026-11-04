# Contributing guidelines

This repository is a **personal collection** of Balatro mods. Every mod is added as a git submodule of the upstream
repository and declared in `config/mods.json`.

## Adding a mod

1. **Make sure the mod exists** in a public repository (GitHub, GitLab, Codeberg...).

2. **Add it with the task**, instead of editing the files by hand:

    ```bash
    task mods:add -- <name> <repo> [path] [branch] [description]
    ```

    Example:

    ```bash
    task mods:add -- balatro-plus https://github.com/SomeCoder99/balatro-plus . main "Adds the Balatro Plus mode"
    ```

3. **Review the state** before committing:

    ```bash
    task mods:list
    task mods:info -- <name>
    git status
    ```

4. **Commit** the three affected places: `.gitmodules`, `config/mods.json` and the submodule pointer.

## Collection rules

- Every mod is referenced from its original repository, not from a copy.
- The `path` of the manifest points to the folder of the mod inside the upstream repository.
- The description of the manifest is short and in English.
- Mods are enabled by default (`enabled: true`); disable in the manifest the ones you do not want to use.
- Changes inside the submodules are not versioned: the mods are updated from upstream with `task mods:update`.
