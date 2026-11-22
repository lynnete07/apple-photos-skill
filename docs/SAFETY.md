# Safety model

Apple Photos stores one asset globally and lets many albums reference it. Removing an asset from an album is not the same as deleting the asset. This skill therefore treats every global deletion as a destructive operation.

## Trust boundaries

- Access Photos only through Apple's public PhotoKit API.
- Never read or edit the private Photos database.
- Keep all analysis and execution local unless the user separately requests a cloud operation.
- Never infer permission to delete from an archive, album name, Favorite flag, or saved profile.

## Before mutation

The agent must:

1. Resolve every album title uniquely.
2. Inspect current membership and marker counts.
3. Build one explicit manifest for the requested scope.
4. Run the manifest without `--apply`.
5. Reject changed counts, conflicting operations, duplicate titles, missing originals, or unauthorized Favorite deletion.
6. Receive current authorization for the grouped destructive scope.

## During mutation

- Use one PhotoKit change transaction for the grouped plan.
- When export and deletion are combined, complete and verify every selected resource before deletion begins.
- Protect the opposite marked or unmarked subset.
- Stop instead of retrying an authorization denial, iCloud download failure, or partial export.

## After mutation

- Verify affected asset identifiers, album existence, protected subsets, and unresolved operations.
- Report assets and resource files separately because one Live Photo can produce two files.
- State that deleted assets moved to Recently Deleted and that album structure is not restored with recovered assets.

## Recovery

Apple Photos keeps deleted assets in Recently Deleted for a limited period. Recover there as soon as possible after an accidental deletion. Albums removed by the operation may need to be recreated manually.

## Data minimization

Do not paste real local identifiers, filenames, GPS coordinates, faces, personal paths, or exported manifests into a public issue. Replace them with synthetic examples that preserve the failing structure.
