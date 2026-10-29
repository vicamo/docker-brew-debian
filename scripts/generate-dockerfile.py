#!/usr/bin/env python3
"""Render the rootfs Dockerfile with the requested hotfixes (requires Jinja2)."""

import argparse
import sys
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined


def main():
    """Write a Dockerfile to stdout for a comma-separated hotfix list."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hotfixes", default="", help="Comma-separated hotfix names")
    args = parser.parse_args()

    environment = Environment(
        loader=FileSystemLoader(Path(__file__).resolve().parent.parent),
        undefined=StrictUndefined,
        autoescape=False,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    template = environment.get_template("Dockerfile.template")
    sys.stdout.write(template.render(hotfixes=args.hotfixes.split(",")))


if __name__ == "__main__":
    main()
