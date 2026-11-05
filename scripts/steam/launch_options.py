#!/usr/bin/env python3
# ======================================================================================================================
# Read and write the launch options of a Steam app in localconfig.vdf
#
# The file is edited in place: only the LaunchOptions entry of the app block is touched, the rest of the file stays
# byte for byte identical. Steam rewrites localconfig.vdf when it exits, so Steam must not be running.
# ======================================================================================================================

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import time
from pathlib import Path

STEAM_ROOTS = [
    Path.home() / ".steam/steam",
    Path.home() / ".local/share/Steam",
    Path.home() / ".var/app/com.valvesoftware.Steam/data/Steam",
    Path.home() / "snap/steam/common/.local/share/Steam",
]

STEAM_PROCESSES = ("steam", "steamwebhelper", "steamerrorreporter")

KEY_RE = re.compile(r'"((?:[^"\\]|\\.)*)"\s*')


# --- VDF helpers --------------------------------------------------------------------------------------------------


def decode(value: str) -> str:
    return value.replace('\\"', '"').replace("\\\\", "\\")


def encode(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def match_brace(text: str, open_index: int) -> int:
    depth = 0
    index = open_index
    in_string = False

    while index < len(text):
        char = text[index]
        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1

    raise ValueError("unbalanced braces")


def find_blocks(text: str, key: str, start: int = 0):
    """Yield the (key_start, block_start, block_end) of every block with the given key."""
    position = start

    while True:
        match = KEY_RE.search(text, position)
        if not match:
            return
        position = match.end()

        index = match.end()
        while index < len(text) and text[index].isspace():
            index += 1
        if index < len(text) and text[index] == "{" and match.group(1) == key:
            yield match.start(), index, match_brace(text, index)


def get_value(text: str, key: str):
    """Return the decoded value of a key inside a block, or None when it is not there."""
    for match in KEY_RE.finditer(text):
        if match.group(1) != key:
            continue
        index = match.end()
        while index < len(text) and text[index].isspace():
            index += 1
        if index < len(text) and text[index] == '"':
            value_match = KEY_RE.match(text, index)
            if value_match:
                return decode(value_match.group(1))
    return None


def set_value(text: str, key: str, value: str) -> str:
    """Replace the value of a key inside a block, or append the key before the closing brace."""
    pattern = re.compile(r'("%s"\s*)"((?:[^"\\]|\\.)*)"' % re.escape(key))

    for match in pattern.finditer(text):
        return text[: match.start()] + '%s"%s"' % (match.group(1), encode(value)) + text[match.end() :]

    closing = text.rfind("}")
    if closing == -1:
        raise ValueError("the block has no closing brace")

    indentation = ""
    for line in reversed(text[:closing].split("\n")):
        stripped = line.strip()
        if stripped:
            indentation = line[: len(line) - len(line.lstrip("\t "))]
            break

    line_start = text.rfind("\n", 0, closing) + 1
    entry = '%s"%s"\t\t"%s"\n' % (indentation, key, encode(value))
    return text[:line_start] + entry + text[line_start:]


# --- Steam helpers ------------------------------------------------------------------------------------------------


def config_files() -> list[Path]:
    found: list[Path] = []
    for root in STEAM_ROOTS:
        userdata = root / "userdata"
        if not userdata.is_dir():
            continue
        for entry in sorted(userdata.iterdir()):
            config = entry / "config" / "localconfig.vdf"
            if config.is_file():
                found.append(config)
    return found


def steam_running() -> list[str]:
    running = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            comm = (proc / "comm").read_text().strip()
        except OSError:
            continue
        if comm in STEAM_PROCESSES:
            running.append(comm)
    return running


def app_block(text: str, appid: str):
    """Return the (start, end) offsets of the app block inside the Steam apps section."""
    for _, apps_open, apps_end in find_blocks(text, "apps"):
        apps_body = text[apps_open + 1 : apps_end]
        for _, app_open, app_end in find_blocks(apps_body, appid):
            return apps_open + 1 + app_open, apps_open + 1 + app_end
    return None


def current_options(text: str, appid: str):
    block = app_block(text, appid)
    if not block:
        return None
    return get_value(text[block[0] : block[1]], "LaunchOptions")


def set_options(config: Path, appid: str, options: str, force: bool) -> int:
    """Write the launch options of an app in the given localconfig.vdf."""
    text = config.read_text(encoding="utf-8", errors="surrogateescape")
    value = current_options(text, appid)

    if value == options:
        print("Launch options already set in %s" % config)
        return 0

    if value is not None and not force:
        print("Launch options are already set to '%s' in %s" % (value, config), file=sys.stderr)
        print("Use --force to replace them.", file=sys.stderr)
        return 1

    block = app_block(text, appid)
    if block is None:
        print("Could not find the block of the app %s in %s" % (appid, config), file=sys.stderr)
        return 1

    updated = set_value(text[block[0] : block[1] + 1], "LaunchOptions", options)
    new_text = text[: block[0]] + updated + text[block[1] + 1 :]

    backup = config.with_suffix(".vdf.bak")
    shutil.copy2(config, backup)

    temporary = config.with_suffix(".vdf.tmp")
    temporary.write_text(new_text, encoding="utf-8", errors="surrogateescape")
    os.replace(temporary, config)

    print("Launch options set in %s" % config)
    print("  %s" % options)
    print("  backup: %s" % backup)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Read or write the launch options of a Steam app")
    parser.add_argument("--appid", required=True, help="Steam app id")
    parser.add_argument("--options", default="", help="launch options to set")
    parser.add_argument("--config", default="", help="path to localconfig.vdf")
    parser.add_argument("--check", action="store_true", help="only report the current value")
    parser.add_argument("--force", action="store_true", help="replace different launch options")
    args = parser.parse_args()

    if args.config:
        configs = [Path(args.config)]
    else:
        configs = config_files()
        if not configs:
            print("Could not find localconfig.vdf", file=sys.stderr)
            return 1

    target = None
    for config in configs:
        try:
            text = config.read_text(encoding="utf-8", errors="surrogateescape")
        except OSError:
            continue
        if current_options(text, args.appid) is not None:
            target = config
            break

    if target is None:
        target = configs[0]

    if args.check:
        text = target.read_text(encoding="utf-8", errors="surrogateescape")
        value = current_options(text, args.appid)
        print(value if value is not None else "")
        return 0 if value == args.options else 1

    running = steam_running()
    if running:
        print(
            "Steam is running (%s). Stop it before changing the launch options, it rewrites "
            "localconfig.vdf when it exits." % ", ".join(sorted(set(running))),
            file=sys.stderr,
        )
        return 1

    return set_options(target, args.appid, args.options, args.force)


if __name__ == "__main__":
    sys.exit(main())
