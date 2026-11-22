#!/usr/bin/env python3
"""Maintain one durable, non-mutating Apple Photos review queue per year."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile


DECISIONS = {
    "delete_all",
    "delete_remaining",
    "delete_marked_keep_album",
    "delete_marked_remove_album",
    "delete_unmarked_keep_album",
    "delete_unmarked_remove_album",
    "remove_album_keep_assets",
    # Backward-compatible legacy values. Do not use for new decisions.
    "keep_favorites",
    "keep_all",
}


def queue_path(value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("queue path must be absolute")
    return path


def load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"queue does not exist: {path}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read queue: {error}") from error
    if data.get("version") != 1 or not isinstance(data.get("year"), int):
        raise ValueError("invalid queue schema")
    if not isinstance(data.get("albums"), dict):
        raise ValueError("invalid queue albums")
    return data


def write_atomic(path: Path, data: dict) -> None:
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


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    initialize = subparsers.add_parser("init")
    initialize.add_argument("--queue", required=True, type=queue_path)
    initialize.add_argument("--year", required=True, type=int)

    record = subparsers.add_parser("record")
    record.add_argument("--queue", required=True, type=queue_path)
    record.add_argument("--album", required=True)
    record.add_argument("--decision", required=True, choices=sorted(DECISIONS))
    record.add_argument("--allow-delete-favorites", action="store_true")

    remove = subparsers.add_parser("remove")
    remove.add_argument("--queue", required=True, type=queue_path)
    remove.add_argument("--album", required=True)

    show = subparsers.add_parser("show")
    show.add_argument("--queue", required=True, type=queue_path)

    args = parser.parse_args()

    try:
        if args.command == "init":
            if args.year < 1900 or args.year > 3000:
                raise ValueError("year is outside the supported range")
            if args.queue.exists():
                data = load(args.queue)
                if data["year"] != args.year:
                    raise ValueError("existing queue belongs to a different year")
                emit("review_queue_ready", path=str(args.queue), year=args.year, albums=len(data["albums"]))
                return 0
            write_atomic(args.queue, {"version": 1, "year": args.year, "albums": {}})
            emit("review_queue_created", path=str(args.queue), year=args.year, albums=0)
            return 0

        data = load(args.queue)
        if args.command == "record":
            if not args.album.strip():
                raise ValueError("album must not be empty")
            decision = {"decision": args.decision}
            if args.allow_delete_favorites:
                if args.decision not in {"delete_all", "delete_remaining"}:
                    raise ValueError("allow-delete-favorites is valid only for whole-current-album deletion")
                decision["allow_delete_favorites"] = True
            data["albums"][args.album] = decision
            write_atomic(args.queue, data)
            emit(
                "review_decision_recorded",
                path=str(args.queue),
                year=data["year"],
                album=args.album,
                decision=args.decision,
                queued_albums=len(data["albums"]),
            )
            return 0

        if args.command == "remove":
            removed = data["albums"].pop(args.album, None) is not None
            write_atomic(args.queue, data)
            emit(
                "review_decision_removed",
                path=str(args.queue),
                year=data["year"],
                album=args.album,
                removed=removed,
                queued_albums=len(data["albums"]),
            )
            return 0

        emit(
            "review_queue",
            path=str(args.queue),
            year=data["year"],
            albums=data["albums"],
            queued_albums=len(data["albums"]),
        )
        return 0
    except (OSError, ValueError) as error:
        emit("error", message=str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
