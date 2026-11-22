#!/usr/bin/env python3
"""Compare a fresh Apple Photos export with a local archive by SHA-256 multiset."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
import sys


IGNORED_NAMES = {".DS_Store"}


def normalize_suffix(value: str) -> str:
    suffix = value.strip().lower()
    if not suffix:
        raise ValueError("ignored suffix must not be empty")
    return suffix if suffix.startswith(".") else f".{suffix}"


def files_under(root: Path, ignored_suffixes: set[str]) -> list[Path]:
    if not root.is_dir():
        raise ValueError(f"not a directory: {root}")
    result: list[Path] = []
    for path in root.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        if path.name.startswith("._") or path.name in IGNORED_NAMES or path.suffix.lower() in ignored_suffixes:
            continue
        result.append(path)
    return sorted(result)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(
    root: Path, ignored_suffixes: set[str]
) -> tuple[list[Path], collections.Counter[str], dict[str, list[str]], int]:
    paths = files_under(root, ignored_suffixes)
    hashes: collections.Counter[str] = collections.Counter()
    names: dict[str, list[str]] = collections.defaultdict(list)
    total_bytes = 0
    for path in paths:
        value = sha256(path)
        hashes[value] += 1
        names[value].append(str(path.relative_to(root)))
        total_bytes += path.stat().st_size
    return paths, hashes, names, total_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument(
        "--ignore-suffix",
        action="append",
        default=[],
        help="suffix to exclude from both inventories; repeat as needed (default: none)",
    )
    args = parser.parse_args()

    try:
        ignored_suffixes = {normalize_suffix(value) for value in args.ignore_suffix}
        source_paths, source_hashes, source_names, source_bytes = inventory(
            args.source.resolve(), ignored_suffixes
        )
        archive_paths, archive_hashes, archive_names, archive_bytes = inventory(
            args.archive.resolve(), ignored_suffixes
        )
    except (OSError, ValueError) as error:
        print(json.dumps({"type": "error", "message": str(error)}, ensure_ascii=False))
        return 1

    missing_counter = source_hashes - archive_hashes
    missing_files: list[str] = []
    for value, count in missing_counter.items():
        missing_files.extend(source_names[value][:count])

    extra_counter = archive_hashes - source_hashes
    extra_files: list[str] = []
    for value, count in extra_counter.items():
        extra_files.extend(archive_names[value][:count])

    matched = len(source_paths) - sum(missing_counter.values())
    result = {
        "type": "archive_comparison",
        "complete": not missing_files,
        "source_files": len(source_paths),
        "source_bytes": source_bytes,
        "archive_files": len(archive_paths),
        "archive_bytes": archive_bytes,
        "matched_source_files": matched,
        "missing_source_files": len(missing_files),
        "missing_preview": missing_files[:20],
        "extra_archive_files": len(extra_files),
        "extra_preview": extra_files[:20],
        "exact_match": not missing_files and not extra_files,
        "ignored_suffixes": sorted(ignored_suffixes),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not missing_files else 2


if __name__ == "__main__":
    sys.exit(main())
