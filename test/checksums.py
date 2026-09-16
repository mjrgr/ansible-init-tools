#!/usr/bin/env python3
"""Regenerate (or verify) the sha256 pins that guard every binary download.

Every role that fetches a binary declares three things in defaults/main.yml:

    <name>_url      a template holding {version}, {version_nov} and {arch}
    <role>_arch     the upstream spelling of each target architecture
    <name>_sha256   what the download must hash to, per architecture

This walks those declarations, fetches each asset, and writes the digests back.
It is the only supported way to fill <name>_sha256 in: a hand-copied digest is a
digest nobody rechecked.

    ./test/checksums.py            update the defaults in place
    ./test/checksums.py --check    fail instead of writing, for CI (downloads)
    ./test/checksums.py --audit    offline: every pinned version has a digest
    ./test/checksums.py kind yq    limit the work to some roles

A version pinned to "latest" cannot be checksummed ahead of time, so its digests
are blanked and the download runs unverified. That is the cost of not pinning.
"""

import argparse
import hashlib
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROLES = pathlib.Path(__file__).resolve().parent.parent / "playbooks" / "roles"
ARCHES = ("amd64", "arm64")
CHUNK = 1 << 20
RETRIES = 3


# A trailing "# noqa" comment is part of the line for ansible-lint, so every
# pattern here has to tolerate one.
COMMENT = r"(?:[ \t]+#.*)?"


def scalar(text, key):
    m = re.search(rf"^{re.escape(key)}:[ \t]*(.*?){COMMENT}[ \t]*$", text, re.M)
    if not m:
        return None
    value = m.group(1).strip()
    return value[1:-1] if value[:1] == value[-1:] == '"' else value


def mapping(text, key):
    m = re.search(rf"^{re.escape(key)}:[ \t]*{COMMENT}\n((?:[ \t]+\S+:.*\n?)+)", text, re.M)
    if not m:
        return None
    out = {}
    for line in m.group(1).splitlines():
        k, _, v = line.strip().partition(":")
        out[k.strip()] = v.strip().strip('"')
    return out


def render(url, version, arch_slug, text=""):
    url = (url.replace("{version_nov}", version.lstrip("v"))
              .replace("{version}", version)
              .replace("{arch}", arch_slug))
    # A URL that has no "latest" mode is spelled in plain Jinja instead; resolve
    # those against the same defaults file Ansible would read them from.
    for ref in set(re.findall(r"{{\s*(\w+)\s*}}", url)):
        value = scalar(text, ref)
        if value is None:
            raise SystemExit(f"cannot resolve {{{{ {ref} }}}} in {url}")
        url = re.sub(r"{{\s*%s\s*}}" % ref, value, url)
    return url


def digest(url):
    last = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(url, timeout=120) as resp:
                h = hashlib.sha256()
                for chunk in iter(lambda: resp.read(CHUNK), b""):
                    h.update(chunk)
                return h.hexdigest()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
    raise SystemExit(f"  ! {url}\n    {last}")


def replace_digest(text, key, arch, value):
    """Rewrite one digest in place, leaving the comments around it alone."""
    if arch is None:
        pattern = re.compile(rf'(^{re.escape(key)}:[ \t]*)"?[^"\n#]*"?({COMMENT})[ \t]*$', re.M)
    else:
        pattern = re.compile(
            rf'(^{re.escape(key)}:[ \t]*{COMMENT}\n(?:[ \t]+\w+:.*\n)*?[ \t]+{arch}:[ \t]*)'
            rf'"?[^"\n#]*"?({COMMENT})[ \t]*$',
            re.M)
    new, n = pattern.subn(rf'\g<1>"{value}"\g<2>', text, count=1)
    if n != 1:
        raise SystemExit(f"could not rewrite {key}{'' if arch is None else '.' + arch}")
    return new


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roles", nargs="*", help="limit to these roles (default: all)")
    ap.add_argument("--check", action="store_true",
                    help="report drift and exit non-zero instead of writing")
    ap.add_argument("--audit", action="store_true",
                    help="no network: fail if a pinned version has an empty digest")
    args = ap.parse_args()

    wanted = set(args.roles)
    drift = []

    for defaults in sorted(ROLES.glob("*/defaults/main.yml")):
        role = defaults.parent.parent.name
        if wanted and role not in wanted:
            continue
        text = original = defaults.read_text()
        role_arch = mapping(text, f"{role}_arch")

        for key in re.findall(r"^(\w+)_url:", text, re.M):
            digests = mapping(text, f"{key}_sha256")
            # A download with no architecture in it (the Nerd Font archive) pins a
            # single digest rather than one per target.
            per_arch = digests is not None
            if not per_arch and scalar(text, f"{key}_sha256") is None:
                continue
            version = scalar(text, f"{key}_version") or scalar(text, f"{role}_version")
            arch_map = mapping(text, f"{key}_arch") or role_arch
            url = scalar(text, f"{key}_url")
            if version is None or url is None:
                raise SystemExit(f"{role}: {key}_url has no version to render with")

            for arch in (ARCHES if per_arch else (None,)):
                have = ((mapping(text, f"{key}_sha256") or {}).get(arch, "")
                        if per_arch else (scalar(text, f"{key}_sha256") or ""))
                # The offline gate: an empty digest is only defensible when the
                # pin says "latest", and that is a deliberate, visible choice.
                if args.audit:
                    if version != "latest" and not have:
                        drift.append(f"{role}: {key}_sha256.{arch} is empty but "
                                     f"{key} is pinned to {version}")
                    continue
                if version == "latest":
                    want = ""
                else:
                    slug = (arch_map or {}).get(arch, arch) if arch else ""
                    full = render(url, version, slug, text)
                    print(f"  {role}: {key} {arch or ''}".rstrip(), flush=True)
                    want = digest(full)
                if have != want:
                    drift.append(f"{role}: {key}_sha256"
                                 + ("" if arch is None else f".{arch}"))
                    text = replace_digest(text, f"{key}_sha256", arch, want)

        if text != original and not args.check:
            defaults.write_text(text)

    if drift and (args.check or args.audit):
        header = ("Pinned versions with no digest to verify against:" if args.audit
                  else "Checksums do not match what upstream serves:")
        print(f"\n{header}", file=sys.stderr)
        for d in drift:
            print(f"  {d}", file=sys.stderr)
        print("\nRun ./test/checksums.py to refresh them.", file=sys.stderr)
        return 1
    if args.audit:
        print("every pinned version has a digest")
        return 0
    print(f"\n{len(drift)} digest(s) {'stale' if args.check else 'written'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
