#!/usr/bin/env python3
"""Create and validate a portable Apple Photos skill profile."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile


DEFAULT_PROFILE = {
    "version": 1,
    "archive_root": None,
    "local_source_after_verified_archive": "keep",
    "raw_policy": "archive",
    "live_photo_export": "full_pair",
    "cloud_backup": {
        "enabled": False,
        "provider": None,
        "destination": None,
    },
}

LOCAL_SOURCE_VALUES = {"keep", "delete_after_verify"}
RAW_VALUES = {"archive", "exclude_keep", "exclude_delete_after_verify"}
LIVE_VALUES = {"full_pair", "still_only"}


def default_profile_path() -> Path:
    configured = os.environ.get("APPLE_PHOTOS_PROFILE")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".config" / "apple-photos" / "profile.json"


def absolute_profile_path(value: str | None) -> Path:
    path = Path(value).expanduser() if value else default_profile_path()
    if not path.is_absolute():
        raise ValueError("profile path must be absolute")
    return path


def validate_profile(data: object) -> dict:
    if not isinstance(data, dict):
        raise ValueError("profile root must be an object")
    expected_keys = {
        "version",
        "archive_root",
        "local_source_after_verified_archive",
        "raw_policy",
        "live_photo_export",
        "cloud_backup",
    }
    unknown = set(data) - expected_keys
    missing = expected_keys - set(data)
    if unknown:
        raise ValueError(f"unknown profile fields: {', '.join(sorted(unknown))}")
    if missing:
        raise ValueError(f"missing profile fields: {', '.join(sorted(missing))}")
    if data["version"] != 1:
        raise ValueError("only profile version 1 is supported")

    archive_root = data["archive_root"]
    if archive_root is not None:
        if not isinstance(archive_root, str) or not archive_root.strip():
            raise ValueError("archive_root must be null or a non-empty absolute path")
        if not Path(archive_root).expanduser().is_absolute():
            raise ValueError("archive_root must be absolute")

    if data["local_source_after_verified_archive"] not in LOCAL_SOURCE_VALUES:
        raise ValueError("invalid local_source_after_verified_archive")
    if data["raw_policy"] not in RAW_VALUES:
        raise ValueError("invalid raw_policy")
    if data["live_photo_export"] not in LIVE_VALUES:
        raise ValueError("invalid live_photo_export")

    cloud = data["cloud_backup"]
    if not isinstance(cloud, dict) or set(cloud) != {"enabled", "provider", "destination"}:
        raise ValueError("cloud_backup must contain enabled, provider, and destination")
    if not isinstance(cloud["enabled"], bool):
        raise ValueError("cloud_backup.enabled must be boolean")
    for field in ("provider", "destination"):
        value = cloud[field]
        if value is not None and (not isinstance(value, str) or not value.strip()):
            raise ValueError(f"cloud_backup.{field} must be null or a non-empty string")
    if cloud["enabled"] and (not cloud["provider"] or not cloud["destination"]):
        raise ValueError("enabled cloud backup requires provider and destination")
    return data


def load_profile(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"profile does not exist: {path}; run init first") from error
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read profile: {error}") from error
    return validate_profile(data)


def write_atomic(path: Path, data: dict) -> None:
    validate_profile(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def emit(event: str, **fields: object) -> None:
    print(json.dumps({"type": event, **fields}, ensure_ascii=False, sort_keys=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", help="absolute profile path")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init")
    commands.add_parser("show")
    commands.add_parser("validate")

    configure = commands.add_parser("configure")
    archive_group = configure.add_mutually_exclusive_group()
    archive_group.add_argument("--archive-root")
    archive_group.add_argument("--clear-archive-root", action="store_true")
    configure.add_argument("--local-source", choices=sorted(LOCAL_SOURCE_VALUES))
    configure.add_argument("--raw", choices=sorted(RAW_VALUES))
    configure.add_argument("--live-photo", choices=sorted(LIVE_VALUES))
    cloud_group = configure.add_mutually_exclusive_group()
    cloud_group.add_argument("--cloud-enabled", action="store_true")
    cloud_group.add_argument("--cloud-disabled", action="store_true")
    configure.add_argument("--cloud-provider")
    configure.add_argument("--cloud-destination")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        path = absolute_profile_path(args.profile)
        if args.command == "init":
            if path.exists():
                data = load_profile(path)
                emit("profile_ready", path=str(path), profile=data, created=False)
            else:
                data = json.loads(json.dumps(DEFAULT_PROFILE))
                write_atomic(path, data)
                emit("profile_ready", path=str(path), profile=data, created=True)
            return 0

        data = load_profile(path)
        if args.command in {"show", "validate"}:
            emit("profile_valid", path=str(path), profile=data)
            return 0

        changed = False
        if args.archive_root is not None:
            root = str(Path(args.archive_root).expanduser())
            if not Path(root).is_absolute():
                raise ValueError("archive root must be absolute")
            data["archive_root"] = root
            changed = True
        elif args.clear_archive_root:
            data["archive_root"] = None
            changed = True
        if args.local_source is not None:
            data["local_source_after_verified_archive"] = args.local_source
            changed = True
        if args.raw is not None:
            data["raw_policy"] = args.raw
            changed = True
        if args.live_photo is not None:
            data["live_photo_export"] = args.live_photo
            changed = True

        cloud = data["cloud_backup"]
        if args.cloud_enabled:
            cloud["enabled"] = True
            changed = True
        elif args.cloud_disabled:
            cloud.update({"enabled": False, "provider": None, "destination": None})
            changed = True
        if args.cloud_provider is not None:
            cloud["provider"] = args.cloud_provider
            changed = True
        if args.cloud_destination is not None:
            cloud["destination"] = args.cloud_destination
            changed = True
        if not changed:
            raise ValueError("configure requires at least one setting")

        write_atomic(path, data)
        emit("profile_updated", path=str(path), profile=data)
        return 0
    except (OSError, ValueError) as error:
        emit("error", message=str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
