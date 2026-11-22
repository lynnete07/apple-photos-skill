# Configurable archive policy

Read the current profile with `python3 scripts/profile.py show` before archive placement, source cleanup, RAW handling, Live Photo export, or cloud backup. If no profile exists, initialize safe defaults. Ask only for a missing choice that materially blocks the requested action.

## Safe defaults

- No archive root is assumed. Require an explicit absolute archive root before placing exports into a long-term archive.
- Apple Photos remains a separate review surface. Export never implies source deletion.
- Local-computer and external-drive source files remain in place after a verified copy.
- RAW files remain in place and are eligible for archive unless the current request or profile says otherwise.
- Live Photos export as `full_pair`: original still plus original paired motion resource.
- Cloud backup is disabled. Never infer a provider or destination.

## Policy application

- A current explicit request overrides the saved profile for that scope only.
- Treat profile cleanup preferences as workflow defaults, not blanket authorization for unrelated files.
- Before any configured source deletion, verify destination count, nonzero bytes, readability where practical, and checksums. Resolve every source path explicitly.
- Never overwrite a same-name file with different content.
- Do not merge, delete, transcode, or split paired media unless the selected policy explicitly allows it.
- Generic “photos” includes still images, videos, and Live Photos.

## Capture time

Export unmodified resources so embedded EXIF, HEIC, and QuickTime metadata remains intact. Also report the Photos `creationDate` as `photos_creation_date`, because Photos date corrections may not rewrite embedded metadata. Finder export timestamps are not capture timestamps.

Create XMP or JSON sidecars only when the user explicitly asks for portable metadata.

## Cloud backup

Cloud backup requires both an enabled profile setting and an explicit destination. Treat upload as a separate verified step. Never upload media, metadata, manifests, or logs merely because an archive export succeeded.
