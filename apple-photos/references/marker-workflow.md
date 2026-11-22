# Favorite marker workflow

Use three independent concepts:

- Album: the temporary review batch.
- Favorite flag: a neutral selection marker inside that album.
- Operation: the explicit action applied to all, marked, or unmarked assets.

Never infer that marked assets should be kept or deleted. Re-inspect immediately before execution because changing the favorite flag changes the selection.

## Operation matrix

| Intent | All | Marked | Unmarked |
|---|---|---|---|
| Export originals | `archive_album` | `archive_favorites_album` | `archive_unfavorites_album` |
| Delete subset, keep album | `delete_album_assets_keep_album` | `delete_favorite_assets_keep_album` | `delete_unfavorite_assets_keep_album` |
| Delete subset, remove album | `delete_album_assets_and_album` | `delete_favorite_assets_and_album` | `delete_unfavorite_assets_and_album` |

`delete_album_keep_assets` removes only the temporary container and keeps every asset.

`move_favorites_to_album_delete_unfavorites_and_source` is the explicit close-and-carry-forward operation: add the current marked subset to an existing `container_album`, globally delete the current unmarked subset, then remove the source album. It fails before mutation if the destination already contains any unmarked deletion target.

For marked/unmarked deletion, set `expected_assets` to the current whole-album count and set `expected_favorite` or `expected_unfavorite` to the selected subset count. The bridge protects the opposite subset even when the album is removed.

## Export then delete

When the user requests export followed by deletion, put the matching archive and delete actions in one manifest. The bridge exports and verifies every selected original before starting deletion. Use the same selector on both actions:

- Marked: `archive_favorites_album` then `delete_favorite_assets_keep_album` or `delete_favorite_assets_and_album`.
- Unmarked: `archive_unfavorites_album` then `delete_unfavorite_assets_keep_album` or `delete_unfavorite_assets_and_album`.

Export does not clear favorite flags. Deletion moves selected assets to Recently Deleted. If the user wants only the marker cleared while keeping assets, stop and report that marker-state mutation is not yet supported; never substitute deletion.

## Natural-language mapping

- “收藏/已收藏/标记的” means the marked subset.
- “未收藏/未标记的” means the unmarked subset.
- “导出收藏” does not imply deletion.
- “删除收藏” does not imply removal of the album.
- Remove the album only when the user explicitly says to delete the album, close the batch, or uses equivalent wording.
- If the user says “保留收藏，删除其余”, select unmarked assets for deletion. This is an explicit instruction, not a default interpretation of favorites.
- If the user says “把收藏移到另一个相册，删除未收藏及原相册”, use the close-and-carry-forward action; do not simulate it as separate commands.
