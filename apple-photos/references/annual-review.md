# Annual review workflow

Use this workflow for one calendar year at a time. Temporary albums isolate visual review batches; they do not represent external-archive folders.

## Annual capture

1. Scan every `PHAsset` in the Mac's current local-calendar-year interval. “Photos” includes images, videos, and Live Photos.
2. Build disjoint batch ranges from time gaps and shooting frequency, with GPS and device continuity as supporting clues.
   Use [album-naming.md](album-naming.md) to produce editable title proposals; naming never changes cluster membership.
3. Compare every candidate cluster with existing user albums by asset identifier:
   - Full cover by one album: mark `reuse`; report whether any cluster asset is missing and do not propose a new album.
   - Partial cover: mark `fill existing`; show matched and missing counts and prefer adding the missing range to the best-fitting album after approval.
   - No suitable cover: mark `create new` and propose `create_album_from_date_range`.
4. Never create a second review album for a cluster already fully covered by an existing album, even when its title or year is imperfect. Flag mixed-date or outside-range contents separately.
5. Add one `create_remainder_album` operation. Its language-aware default is `YYYY_未进入批次` for Chinese or `YYYY_Unbatched` for English, but use a user-supplied catch-all title literally. Set `exclude_albums` to new mutually exclusive batch albums and `reuse_albums` to existing albums accepted as coverage. Existing reused albums may contain assets outside the year; only their annual intersection counts.
6. Require these invariants before and after apply:
   - `overlapping_batch_memberships == 0`
   - `new_reuse_overlap == 0`
   - `annual_assets == batched_unique_assets + reused_unique_assets + remainder_assets`
   - `captured_unique_assets == annual_assets`
   - `missing == 0`
7. If the remainder is zero, do not create a new empty album. Still emit successful annual-coverage verification.

## Durable decision queue

Keep one queue per active year outside the configured archive root, under the current agent's state directory or another non-archive directory. Do not mix queue state, manifests, or logs into the media archive.

Use `scripts/review_queue.py` to create and update the queue. Recording decisions changes only this local JSON file and never calls Photos:

```bash
python3 scripts/review_queue.py init --queue /absolute/state/2022-review.json --year 2022
python3 scripts/review_queue.py record --queue /absolute/state/2022-review.json --album "2022-05-08_待识别主题" --decision delete_all
python3 scripts/review_queue.py show --queue /absolute/state/2022-review.json
```

Recommended state shape:

```json
{
  "version": 1,
  "year": 2022,
  "albums": {
    "2022-05-08_待识别主题": {"decision": "delete_all"},
    "2022-06-16_待识别主题": {"decision": "delete_remaining"},
    "2022-08-31_待识别连续段": {"decision": "delete_unmarked_remove_album"},
    "2022_未进入批次": {"decision": "remove_album_keep_assets"}
  }
}
```

Natural-language mapping:

| User decision | Queue value | Photos mutation while recording |
|---|---|---|
| 整批删除 | `delete_all` | None |
| 已移出保留内容，删除当前剩余 | `delete_remaining` | None |
| 删除已标记，保留相册 | `delete_marked_keep_album` | None |
| 删除已标记并结束批次 | `delete_marked_remove_album` | None |
| 删除未标记，保留相册 | `delete_unmarked_keep_album` | None |
| 删除未标记并结束批次 | `delete_unmarked_remove_album` | None |
| 全部保留，只清理临时相册 | `remove_album_keep_assets` | None |

Unreviewed albums stay out of the queue and remain unchanged.

## Execute the queue

1. Inspect all queued albums together immediately before manifest creation.
2. Use current membership as the source of truth. Ignore historical creation counts.
3. Map decisions:
   - `delete_all` or `delete_remaining` → `delete_album_assets_and_album`
   - `delete_marked_keep_album` → `delete_favorite_assets_keep_album`
   - `delete_marked_remove_album` → `delete_favorite_assets_and_album`
   - `delete_unmarked_keep_album` → `delete_unfavorite_assets_keep_album`
   - `delete_unmarked_remove_album` → `delete_unfavorite_assets_and_album`
   - `remove_album_keep_assets` → `delete_album_keep_assets`
4. Treat the favorite flag only as the user's current selection marker. Do not convert it into a keep/delete decision without an explicit queue value.
5. For whole deletion, protect current favorites unless the user explicitly authorizes deleting them.
6. Set `expected_assets` plus the selected `expected_favorite` or `expected_unfavorite` from the final inspect.
7. Dry-run the complete manifest, then apply the whole year in one PhotoKit transaction.
8. Verify unique deletion identifiers, the protected opposite subset, album removal/preservation, and zero unresolved operations.
9. Remove the annual queue only after all verification succeeds. Keep it intact on failure.

## Decision-load rules

- Analyze and execute one year at a time.
- Do not mutate Photos when merely recording a decision.
- Do not ask about an album shrinking before final inspect; that is expected after manual curation or earlier deletion.
- Stop for new assets after final inspect, duplicate titles, favorite deletion without authorization, scope expansion, or verification failure.
- Present unresolved albums and exceptions only. Do not repeatedly restate completed decisions.
