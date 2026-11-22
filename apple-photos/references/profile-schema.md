# User profile

The profile stores reusable archive preferences. It never grants permission for an unrelated destructive action. The current explicit request overrides the saved value for that request.

Default location:

```text
~/.config/apple-photos/profile.json
```

Override it with `--profile /absolute/path/profile.json` or the `APPLE_PHOTOS_PROFILE` environment variable.

## Schema

```json
{
  "version": 1,
  "archive_root": null,
  "local_source_after_verified_archive": "keep",
  "raw_policy": "archive",
  "live_photo_export": "full_pair",
  "cloud_backup": {
    "enabled": false,
    "provider": null,
    "destination": null
  }
}
```

Fields:

- `archive_root`: absolute long-term archive directory, or `null` until configured.
- `local_source_after_verified_archive`:
  - `keep`: preserve local-computer and external-drive sources.
  - `delete_after_verify`: delete only the exact processed sources after verified archive completion.
- `raw_policy`:
  - `archive`: include and preserve RAW files.
  - `exclude_keep`: omit RAW from the archive and preserve source RAW files.
  - `exclude_delete_after_verify`: omit RAW and delete a source RAW only after its companion output is verified in the archive.
- `live_photo_export`:
  - `full_pair`: export original still and paired motion resources.
  - `still_only`: export only the original still resource.
- `cloud_backup`: disabled by default. When enabled, both `provider` and `destination` must be non-empty. The skill still treats cloud upload as a separate explicit task.

## Commands

```bash
python3 scripts/profile.py init
python3 scripts/profile.py show
python3 scripts/profile.py validate
python3 scripts/profile.py configure --archive-root /absolute/archive
python3 scripts/profile.py configure --live-photo still_only
python3 scripts/profile.py configure --raw exclude_keep --local-source keep
python3 scripts/profile.py configure --cloud-enabled --cloud-provider ExampleDrive --cloud-destination /Photos
```

Use `--clear-archive-root` or `--cloud-disabled` to restore the corresponding safe unset state.
