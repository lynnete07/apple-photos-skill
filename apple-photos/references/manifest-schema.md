# Batch manifest

Use UTF-8 JSON with `version: 1` and a non-empty `operations` array. Paths must be absolute. Date-range `end` is exclusive. Date-only values use the Mac's current local time zone.

## Supported actions

| Action | Selection | Result |
|---|---|---|
| `archive_album` | Exact existing album | Export unmodified originals to a fresh empty directory |
| `archive_favorites_album` | Current favorites in an exact existing album | Export only currently favorited unmodified originals; leave Photos unchanged |
| `archive_unfavorites_album` | Current nonfavorites in an exact existing album | Export only currently unmarked originals; leave Photos unchanged |
| `archive_date_range` | `[start, end)` | Export unmodified originals, then create/fill the same-name album |
| `create_album_from_date_range` | `[start, end)` | Create/fill a review album without export |
| `create_remainder_album` | Annual range minus new `exclude_albums` and existing `reuse_albums` | Create the catch-all review album and verify complete annual coverage without duplicate batch albums |
| `merge_albums_keep_assets` | Exact union of `source_albums` | Create/fill one target album, retain every asset, then remove the source album containers |
| `move_favorites_to_album_delete_unfavorites_and_source` | Current favorites and nonfavorites in one exact source album | Add favorites to an existing destination album, delete nonfavorites globally, then remove the source album |
| `delete_album_assets_and_album` | Current exact album | Delete its current assets globally and remove the album |
| `delete_album_assets_keep_album` | Current exact album | Delete its current assets globally and preserve the empty album |
| `delete_unfavorite_assets_keep_album` | Current nonfavorites | Delete nonfavorites and preserve album/favorites |
| `delete_unfavorite_assets_and_album` | Current nonfavorites | Delete nonfavorites, retain favorites in Photos, and remove the temporary album |
| `delete_favorite_assets_keep_album` | Current favorites | Delete favorites and preserve the album/nonfavorites |
| `delete_favorite_assets_and_album` | Current favorites | Delete favorites, retain nonfavorites in Photos, and remove the temporary album |
| `delete_album_keep_assets` | Exact album | Remove album structure but keep every asset |
| `delete_album_if_contained` | Exact source and container albums | Remove source album only after exact containment succeeds |

All date selections include images, videos, and Live Photos. A Live Photo counts as one image asset.

## Fields

- `action`: required supported action.
- `album`: required exact album title.
- `expected_assets`: required for every `--apply`; use the immediate preflight/current membership, not a historical creation count.
- `expected_unfavorite`: required for both unmarked-delete actions and the favorite-move/source-close action.
- `expected_favorite`: required for both marked-delete actions and the favorite-move/source-close action.
- `start`, `end`: required for archive/create date-range and remainder actions.
- `output_dir`: required only for archive actions; the directory must not exist or must be empty.
- `live_photo_export`: optional on archive actions and forbidden elsewhere. Values are `full_pair` or `still_only`; omission defaults to the loss-averse `full_pair` mode.
- For `archive_favorites_album` and `archive_unfavorites_album`, `expected_assets` is the selected subset count. Apply fails if the marker split changes after preflight.
- `allow_album_outside`: optional, default `false`; permit an existing date-range album to retain unrelated members. Do not use it for annual-review partitions.
- `allow_delete_favorites`: optional, default `false`; permit whole-album asset deletion when favorites exist. Set only after explicit authorization.
- `exclude_albums`: list new mutually exclusive annual batch albums for `create_remainder_album`.
- `reuse_albums`: list existing albums accepted as coverage. Their annual intersections count; assets outside the year are allowed. At least one of `exclude_albums` or `reuse_albums` is required.
- `container_album`: required for `delete_album_if_contained` and `move_favorites_to_album_delete_unfavorites_and_source`.
- `source_albums`: required for `merge_albums_keep_assets`; provide at least two unique exact source titles. The target `album` must differ from every source.

Unknown fields and unknown actions fail closed.

A grouped apply also fails before mutation when one operation targets an asset that another operation must retain.

Favorites are neutral markers. An action name selects `all`, `favorite` (marked), or `unfavorite` (unmarked); it does not assign keep/delete meaning by itself. Read [marker-workflow.md](marker-workflow.md) for the operation matrix.

## Annual review creation

Put the remainder operation after accepted batch operations. The bridge computes the remainder from planned ranges and reused existing albums, creates only necessary new/fill operations, creates the remainder second, then verifies the final union. Reused albums may overlap one another, but a new batch must not overlap reused coverage.

```json
{
  "version": 1,
  "operations": [
    {
      "action": "create_album_from_date_range",
      "album": "2022-05-08_待识别主题",
      "start": "2022-05-08",
      "end": "2022-05-09",
      "expected_assets": 93
    },
    {
      "action": "create_album_from_date_range",
      "album": "2022-08-31_待识别连续段",
      "start": "2022-08-31",
      "end": "2022-09-09",
      "expected_assets": 71
    },
    {
      "action": "create_remainder_album",
      "album": "2022_未进入批次",
      "start": "2022-01-01",
      "end": "2023-01-01",
      "exclude_albums": [
        "2022-05-08_待识别主题",
        "2022-08-31_待识别连续段"
      ],
      "reuse_albums": [
        "2022-10-01_已有旅行相册"
      ],
      "expected_assets": 670
    }
  ]
}
```

Require `annual_coverage_preflight` and `annual_coverage_verified` to report zero new-batch overlap, zero new/reuse overlap, and zero missing assets. Overlap among reused existing albums is reported but allowed. If remainder count is zero, the bridge skips creating a new empty remainder album but still verifies full coverage.

## Annual decision execution

Inspect every queued album immediately before generating this manifest. The example covers all three review outcomes in one transaction.

```json
{
  "version": 1,
  "operations": [
    {
      "action": "delete_album_assets_and_album",
      "album": "2022-05-08_待识别主题",
      "expected_assets": 93
    },
    {
      "action": "delete_unfavorite_assets_and_album",
      "album": "2022-08-31_待识别连续段",
      "expected_assets": 71,
      "expected_unfavorite": 60
    },
    {
      "action": "delete_album_keep_assets",
      "album": "2022_未进入批次",
      "expected_assets": 15
    }
  ]
}
```

For a user who manually removed keepers from a temporary album, use `delete_album_assets_and_album` with the album's current count. Do not compare it with the count at creation time.

## Archive originals

```json
{
  "version": 1,
  "operations": [
    {
      "action": "archive_date_range",
      "album": "2023-10-03_呼和浩特",
      "start": "2023-10-03",
      "end": "2023-10-07",
      "expected_assets": 107,
      "output_dir": "/absolute/empty/output/2023-10-03_trip",
      "live_photo_export": "full_pair"
    }
  ]
}
```

Archive actions write original resource bytes. Videos use the original video resource. With `full_pair`, each Live Photo contributes its original still and paired motion resource; with `still_only`, it contributes only the original still. A Live Photo remains one Photos asset in counts even when it produces two files. Embedded EXIF/HEIC/QuickTime metadata stays intact. Each exported-resource event reports the Photos `creationDate` separately as `photos_creation_date`; no EXIF/XMP sidecar is created unless explicitly requested.

To export only the current favorites from an album without changing Photos:

```json
{
  "version": 1,
  "operations": [
    {
      "action": "archive_favorites_album",
      "album": "2019_未进入批次",
      "expected_assets": 95,
      "output_dir": "/absolute/empty/output",
      "live_photo_export": "full_pair"
    }
  ]
}
```

## Conditional redundant-album cleanup

```json
{
  "version": 1,
  "operations": [
    {
      "action": "delete_album_if_contained",
      "album": "2019-01-27_清迈",
      "container_album": "2019-01-27_泰国",
      "expected_assets": 22
    }
  ]
}
```

## Move favorites and close a reviewed batch

```json
{
  "version": 1,
  "operations": [
    {
      "action": "move_favorites_to_album_delete_unfavorites_and_source",
      "album": "2023-07-21_荆州-武汉",
      "container_album": "2023_未进入批次",
      "expected_assets": 83,
      "expected_favorite": 24,
      "expected_unfavorite": 59
    }
  ]
}
```

The destination album must already exist. The bridge adds only missing favorites, preserves all existing destination members, deletes source nonfavorites globally, and removes the source album in one PhotoKit transaction. It rejects the operation if any source nonfavorite is already present in the destination.

## Merge exact album memberships

```json
{
  "version": 1,
  "operations": [
    {
      "action": "merge_albums_keep_assets",
      "album": "2023-07-21_荆州-武汉",
      "source_albums": [
        "2023-07-18_荆州连续段",
        "2023-07-26_武汉连续段",
        "2023-08-02_荆州连续段"
      ],
      "expected_assets": 212
    }
  ]
}
```

The operation uses the exact union of current source-album memberships, not a date range. It fails if the target contains unrelated assets unless `allow_album_outside` is explicitly enabled. After verification, it deletes only the source album containers; the Photos assets remain.

## Required execution pattern

1. Inspect all execution-time album titles together.
2. Write one manifest for the grouped request or annual queue.
3. Run `batch --manifest ...` for dry-run validation.
4. Run `batch --manifest ... --apply` once after the exact grouped scope is authorized.
5. Consume `batch_complete`, deletion verification, export verification, and annual-coverage records. Never infer success from exit status alone.
