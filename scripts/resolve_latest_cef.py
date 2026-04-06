#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path


INDEX_URL = "https://cef-builds.spotifycdn.com/index.json"
PLATFORMS = ("macosarm64", "macosx64")


def chromium_branch(chromium_version: str) -> int:
    return int(chromium_version.split(".")[2])


def is_beta_build(build: dict) -> bool:
    return "_beta" in build["files"][0]["name"]


def has_minimal_archive(build: dict, platform: str) -> bool:
    suffix = f"_{platform}_minimal.tar.bz2"
    return any(file_info["name"].endswith(suffix) for file_info in build["files"])


def choose_stable_build(versions: list[dict], platform: str) -> dict:
    remaining = 5
    selected: dict | None = None
    selected_branch = -1

    for build in versions:
        if is_beta_build(build) or not has_minimal_archive(build, platform):
            continue

        branch = chromium_branch(build["chromium_version"])
        if branch > selected_branch:
            selected = build
            selected_branch = branch

        remaining -= 1
        if remaining == 0:
            break

    if selected is None:
        raise RuntimeError(f"Could not resolve a stable minimal CEF build for {platform}.")

    return selected


def fetch_index() -> dict:
    with urllib.request.urlopen(INDEX_URL) as response:
        return json.load(response)


def resolve_latest_version() -> str:
    index = fetch_index()
    selected_versions = []

    for platform in PLATFORMS:
        versions = index.get(platform, {}).get("versions", [])
        if not versions:
            raise RuntimeError(f"CEF index did not contain any versions for {platform}.")
        selected_versions.append(choose_stable_build(versions, platform)["cef_version"])

    unique_versions = sorted(set(selected_versions))
    if len(unique_versions) != 1:
        raise RuntimeError(
            "Latest stable macOS arm64/x64 CEF builds disagree: "
            + ", ".join(unique_versions)
        )

    return unique_versions[0]


def read_current_version(path: Path) -> str:
    for line in path.read_text().splitlines():
        if line.startswith("readonly CEF_VERSION="):
            return line.split('"')[1]
    raise RuntimeError(f"Could not read CEF_VERSION from {path}.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current-file", type=Path, default=Path("scripts/cef_version.sh"))
    parser.add_argument("--print-current", action="store_true")
    args = parser.parse_args()

    if args.print_current:
        print(read_current_version(args.current_file))
        return 0

    print(resolve_latest_version())
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
