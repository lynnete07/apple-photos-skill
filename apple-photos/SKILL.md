---
name: apple-photos
description: Batch-analyze, organize, export, compare, review, and safely delete assets and albums in macOS Apple Photos through the public PhotoKit API. Use for low-decision annual photo review; time-and-frequency batch albums with existing-album reuse and verified catch-all coverage; favorites-as-neutral-markers workflows; durable decision queues; unmodified-original export with configurable Live Photo handling; archive comparison; and exact, verified album or subset deletion.
---

# Apple Photos

Use the bundled PhotoKit bridge. Never read or modify the private Photos database and never replace the bridge with one-off AppleScript or Swift automation.

## Agent portability

This `SKILL.md` is the canonical, agent-neutral contract and follows the open Agent Skills folder model. Do not require Codex-specific metadata to execute the workflow. `agents/openai.yaml` is an optional interface adapter only. Any compatible agent may use the bundled CLI as long as it runs locally on macOS, can execute terminal commands, and has authorized Photos access.

## Core semantics

- Interpret a generic request about “photos” as all Photos assets: still images, videos, and Live Photos. Exclude a media type only when the user says so.
- Count a Live Photo as one user-visible image asset even when full-pair export writes two resource files.
- Treat review albums as temporary visual work containers. Album membership never proves external-archive status.
- Treat the favorite flag as a neutral marker. Never infer keep or delete intent from the marker alone.
- Keep archive location, source cleanup, RAW handling, Live Photo export, and cloud backup user-configurable. Read [references/archive-policy.md](references/archive-policy.md) before archive or source-cleanup work.
- For marked-subset work, read [references/marker-workflow.md](references/marker-workflow.md).

## Commands

Run commands from this skill directory:

```bash
bash scripts/install.sh
scripts/apple-photos status
scripts/apple-photos inspect --album "Album name"
scripts/apple-photos scan --start "2022-01-01" --end "2023-01-01" --gap-hours 36
scripts/apple-photos validate-manifest --manifest /absolute/path/plan.json
scripts/apple-photos batch --manifest /absolute/path/plan.json
scripts/apple-photos batch --manifest /absolute/path/plan.json --apply
python3 scripts/profile.py init
python3 scripts/profile.py show
python3 scripts/review_queue.py init --queue /absolute/state/2022-review.json --year 2022
python3 scripts/compare_archive.py --source /absolute/export --archive /absolute/archive
```

Run `bash scripts/install.sh` once per agent session before the first bridge call. `batch` is a dry run. `batch --apply` repeats all preconditions before mutation. Read [references/manifest-schema.md](references/manifest-schema.md) before creating a manifest.

## User profile

Use `scripts/profile.py` only when archive or source-cleanup policy matters. The safe defaults keep all sources and RAW files, export complete Live Photo pairs, and disable cloud backup. An unset archive root blocks archive placement but does not block analysis, album organization, or Photos-only review.

- A saved profile is a default, not permission for an unexpected destructive action.
- An explicit current request overrides the profile for that request.
- Never copy another user's paths or policy assumptions into a new profile.
- Read [references/profile-schema.md](references/profile-schema.md) before changing the profile.

## Route requests

- Use `scan` for annual time/frequency analysis and existing-album coverage. Treat clusters as candidates, not factual trip names.
- Read [references/album-naming.md](references/album-naming.md) before presenting or creating review albums. Proposed titles are editable defaults; use the user's approved title literally.
- Reuse a complete existing album. Fill a partial match after approval. Create a new batch only when no suitable album covers the cluster.
- Create mutually exclusive review batches, then one verified language-aware or user-named annual catch-all. Prove full annual coverage with zero missing assets and no overlap between new batches and reused coverage.
- Use `inspect` for current counts, media types, Live Photos, marker split, GPS coverage, and execution-time expectations.
- Put all operations requested together into one manifest and one apply.
- Use exact album membership for merges and marker-based actions. Never substitute a broad date range.
- Export or delete all, marked, or unmarked assets only when the user explicitly names the subset and action.

## Annual review

Process one calendar year at a time. Follow [references/annual-review.md](references/annual-review.md).

1. Scan the complete local-calendar year without mutation.
2. Propose disjoint batches using time gaps, frequency, GPS, and device continuity. Suppress batches already covered by existing albums.
3. Present editable proposed names with their date range, asset count, evidence, and confidence. Apply any user naming template or per-album override before manifest creation.
4. After approval, create or fill only necessary albums and the annual catch-all in one manifest.
5. Verify that new batches, reused annual intersections, and the catch-all cover every annual asset exactly once.
6. Let the user review albums individually. Record explicit decisions without mutating Photos.
7. Execute the accepted annual queue in one current inspect, one grouped apply, and one final verification.

## Export originals

- Export unmodified original resource bytes. Never substitute an edited rendition.
- Export original video resources for videos.
- Set `live_photo_export` on each archive operation from the current request or profile:
  - `full_pair`: export the original still and paired motion resource. This is the public safe default.
  - `still_only`: export only the original still resource. Use only after the user chooses it.
- Preserve embedded EXIF, HEIC, QuickTime, or other source metadata by writing original resource bytes.
- Report `PHAsset.creationDate` as `photos_creation_date`; it reflects the date shown by Photos and may differ from embedded camera metadata after a Photos date correction.
- Never use Finder creation or modification time as capture time.
- Use a fresh empty output directory. Verify resource count, nonzero bytes, readability where practical, and SHA-256. Never overwrite or silently merge.
- Archive comparison includes every file format by default, including RAW. Exclude a suffix only when the user explicitly asks for it, using `--ignore-suffix`.

## Destructive gates

Require exact unique album titles, current asset and marker counts, and current authorization for the grouped scope. Dry-run first, recheck at apply time, and verify the protected opposite subset afterward.

Reject a plan when an asset targeted for deletion is also protected by another operation. Do not repeatedly retry authorization denial, iCloud download failure, duplicate titles, changed counts, or partial exports.

Deletion moves assets to Photos Recently Deleted. Recovery does not restore deleted album structure. State this after deletion.

## Acceptance criteria

- Annual batches plus reused coverage and the catch-all account for every image, video, and Live Photo with zero missing assets.
- Existing complete albums are reused instead of duplicated.
- Every newly proposed album title is explained, editable before apply, and replaced by the user's exact approved title when provided.
- Marker-based operations never infer intent and never modify the opposite subset.
- Every export uses original resources and reports asset count separately from resource-file count.
- Public defaults preserve local sources, Photos sources, RAW files, and complete Live Photo pairs.
- No profile, example, log, or output contains another user's name, archive path, or cloud destination.
- Final reports identify assets affected, resource files exported, albums preserved or removed, and exceptions.
