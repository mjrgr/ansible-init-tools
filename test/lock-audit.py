#!/usr/bin/env python3
"""Offline: every tool in mise/config.toml is locked for linux-x64 and
linux-arm64 with a sha256 or sha512 digest. A pin without one is a download nobody
verifies, and a platform missing from the lock is one `mise install --locked`
refuses on. Exit 1 on the first gap."""
import pathlib
import re
import sys
import tomllib

root = pathlib.Path(__file__).resolve().parent.parent / "mise"
config = tomllib.loads((root / "config.toml").read_text())
lock_path = root / "mise.lock"
if not lock_path.exists():
    sys.exit(f"{lock_path} missing — run `mise lock`")
lock = tomllib.loads(lock_path.read_text())
platforms = config.get("settings", {}).get("lockfile_platforms", ["linux-x64", "linux-arm64"])

errors = []
for tool, spec in config["tools"].items():
    entries = lock.get("tools", {}).get(tool)
    if not entries:
        errors.append(f"{tool}: not in mise.lock")
        continue
    # A bump rewrites config.toml first and the lock after; a failed one leaves the two apart.
    pinned = spec if isinstance(spec, str) else spec.get("version")
    locked = sorted({e.get("version") for e in entries})
    if pinned != "latest" and pinned not in locked:
        errors.append(f"{tool}: config pins {pinned}, lock has {locked}")
    for entry in entries:
        # Not downloads mise hashes: rustup verifies its toolchain, cargo the crate.
        if entry.get("backend", "").split(":")[0] in ("core", "cargo"):
            continue
        # pypi/npm: platform-free packages, pinned by the uv / aube lock mise keeps next to the config.
        kind = entry.get("backend", "").split(":")[0]
        if kind in ("pypi", "npm"):
            key, name = ("uv", "uv.lock") if kind == "pypi" else ("aube", "aube-lock.yaml")
            sub = entry.get(key) or {}
            if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(sub.get("digest", ""))) or not (root / sub.get("path", "x") / name).is_file():
                errors.append(f"{tool}@{entry.get('version')}: no {key} lock with a digest")
            continue
        for platform in platforms:
            # mise writes the platform as one quoted key: [tools.x."platforms.linux-x64"]
            info = entry.get(f"platforms.{platform}") or entry.get("platforms", {}).get(platform)
            if not info:
                errors.append(f"{tool}@{entry.get('version')}: no {platform} entry")
            # `mise upgrade --bump` records sha512 for the native platform where the registry publishes one.
            elif not re.fullmatch(r"sha(256|512):[0-9a-f]{64,128}", str(info.get("checksum", ""))):
                errors.append(f"{tool}@{entry.get('version')}: no digest for {platform}")

for e in errors:
    print(e)
print(f"{len(config['tools'])} tools, {len(errors)} gap(s)")
sys.exit(1 if errors else 0)
