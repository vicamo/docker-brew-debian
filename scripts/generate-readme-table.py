#!/usr/bin/env python3
"""Generate a markdown architecture support table for README.md.

Usage: generate-readme-table.py [options] [README_PATH]

When README_PATH is given, replaces content between hidden markers in-place.
Without it, prints the table to stdout.

Options:
  --repository REPO              Container image repository
  --disable-architecture A[,B]   Comma-separated architectures to exclude
  --disable-codename C[,D]       Comma-separated codenames to exclude

FULL_JSON is read from the environment variable, or fetched from the
vicamo/actions-library debian-releases action.yml as fallback.

Example:
  python3 scripts/generate-readme-table.py \
    --repository ghcr.io/vicamo/debian \
    --disable-codename experimental,slink,hamm \
    --disable-architecture hurd-amd64,hurd-i386,ia64,kfreebsd-amd64,kfreebsd-i386,s390,x32 \
    README.md
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from collections import OrderedDict

START_MARKER = "<!-- arch-table:start -->"
END_MARKER = "<!-- arch-table:end -->"

ACTION_URL = (
    "https://raw.githubusercontent.com/vicamo/actions-library/v1"
    "/debian-releases/action.yml"
)

# OCI platform string → Debian arch name
PLATFORM_TO_ARCH = {
    "linux/amd64": "amd64",
    "linux/amd64/v3": "amd64v3",
    "linux/arm": "arm",
    "linux/arm64": "arm64",
    "linux/arm/v5": "armel",
    "linux/arm/v7": "armhf",
    "linux/386": "i386",
    "linux/loong64": "loong64",
    "linux/mips64le": "mips64el",
    "linux/ppc64le": "ppc64el",
    "linux/riscv64": "riscv64",
    "linux/s390x": "s390x",
    "linux/mips": "mips",
    "linux/mipsle": "mipsel",
    "linux/ppc": "powerpc",
    "linux/ppc64": "ppc64",
    "linux/s390": "s390",
    "linux/sparc": "sparc",
    "linux/sparc64": "sparc64",
    "linux/amd64p32": "x32",
    "linux/alpha": "alpha",
    "linux/hppa": "hppa",
    "linux/m68k": "m68k",
    "linux/sh4": "sh4",
}


def fetch_full_json():
    """Get releases JSON from env or fetch from action.yml."""
    env_val = os.environ.get("FULL_JSON", "").strip()
    if env_val:
        return json.loads(env_val)

    # Fallback: fetch action.yml and extract RELEASE_INFO_JSON
    with urllib.request.urlopen(ACTION_URL, timeout=30) as resp:
        content = resp.read().decode()
    # It's a YAML >- folded scalar indented under env:
    m = re.search(
        r"RELEASE_INFO_JSON:\s*>-\n(.*?)(?=^\s*\w+:|\Z)",
        content,
        re.MULTILINE | re.DOTALL,
    )
    if not m:
        # Try single-line
        m = re.search(r"RELEASE_INFO_JSON:\s*(.+)", content)
        if not m:
            print(
                "error: cannot extract RELEASE_INFO_JSON from action.yml",
                file=sys.stderr,
            )
            sys.exit(1)
        return json.loads(m.group(1).strip())
    # Join folded lines (strip leading whitespace, join with space)
    raw = " ".join(line.strip() for line in m.group(1).splitlines() if line.strip())
    return json.loads(raw)


def get_manifest_arches(repository, codename):
    """Query GHCR for the manifest list and return set of Debian arch names."""
    image = f"{repository}:{codename}"
    cmd = ["docker", "buildx", "imagetools", "inspect", "--raw", image]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30, check=False
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return set()
    if result.returncode != 0:
        return set()
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return set()

    arches = set()
    for m in data.get("manifests", []):
        p = m.get("platform", {})
        if p.get("os") != "linux" or not p.get("architecture"):
            continue
        plat = f"linux/{p['architecture']}"
        if p.get("variant"):
            plat += f"/{p['variant']}"
        a = PLATFORM_TO_ARCH.get(plat)
        if a:
            arches.add(a)
    return arches


def generate_table(full_json, repository, disabled_codenames, disabled_arches):
    """Build a markdown table of suite × architecture build status."""
    suites = [s for s in full_json if s["codename"] not in disabled_codenames]

    # Collect all arches across all suites, minus disabled
    all_arches = OrderedDict()
    for s in suites:
        for arch in s.get("architectures", []):
            if arch not in disabled_arches:
                all_arches[arch] = True
    arches = sorted(all_arches.keys())

    # Query registry for each suite
    rows = []
    for s in suites:
        codename = s["codename"]
        suite_arches = set(s.get("architectures", [])) - disabled_arches
        built_arches = get_manifest_arches(repository, codename)

        cells = []
        for arch in arches:
            if arch not in suite_arches:
                cells.append("—")
            elif arch in built_arches:
                cells.append("✅")
            else:
                cells.append("❌")
        rows.append((codename, cells))

    lines = []
    lines.append(f"| suite | {' | '.join(arches)} |")
    lines.append(f"|---|{'|'.join(['---'] * len(arches))}|")
    for codename, cells in rows:
        lines.append(f"| {codename} | {' | '.join(cells)} |")
    lines.append("")
    lines.append("Legend: ✅ built | ❌ missing | — unsupported")
    return "\n".join(lines)


def main():
    """Parse arguments and generate/update the architecture table."""
    parser = argparse.ArgumentParser(
        description="Generate architecture support table for README.md"
    )
    parser.add_argument("readme", nargs="?", help="README file to update in-place")
    parser.add_argument(
        "--repository",
        default="ghcr.io/vicamo/debian",
        help="Container image repository (default: ghcr.io/vicamo/debian)",
    )
    parser.add_argument(
        "--disable-architecture",
        default="",
        metavar="ARCH[,ARCH2]",
        help="Comma-separated architectures to exclude",
    )
    parser.add_argument(
        "--disable-codename",
        default="",
        metavar="NAME[,NAME2]",
        help="Comma-separated codenames to exclude",
    )
    args = parser.parse_args()

    disabled_arches = set(args.disable_architecture.split(",")) - {""}
    disabled_codenames = set(args.disable_codename.split(",")) - {""}

    full_json = fetch_full_json()
    table = generate_table(
        full_json, args.repository, disabled_codenames, disabled_arches
    )

    if args.readme:
        with open(args.readme, "r", encoding="utf-8") as f:
            content = f.read()

        start = content.find(START_MARKER)
        end = content.find(END_MARKER)
        if start == -1 or end == -1:
            print(f"error: markers not found in {args.readme}", file=sys.stderr)
            sys.exit(1)

        new_content = (
            content[: start + len(START_MARKER)] + "\n" + table + "\n" + content[end:]
        )
        with open(args.readme, "w", encoding="utf-8") as f:
            f.write(new_content)
    else:
        print(table)


if __name__ == "__main__":
    main()
