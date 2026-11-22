# Apple Photos Agent Skill

[简体中文](README.zh-CN.md)

A safety-gated Apple Photos skill for people who want to review large photo libraries without making hundreds of repetitive decisions.

It analyzes one calendar year at a time, groups assets into review batches, reuses existing albums, creates a verified catch-all album, treats Favorites as neutral selection markers, exports unmodified originals, compares archives by SHA-256, and executes only explicitly approved deletion plans.

## Who it is for

- People with large, long-running Apple Photos libraries.
- People who prefer explicit rules and predictable workflows, including neurodivergent users and anyone affected by decision fatigue.
- People who keep a separate long-term archive and need safe export and comparison steps.
- Users of Codex, Claude Code, WorkBuddy, or another Agent Skills-compatible local agent who want PhotoKit automation without directly modifying the private Photos database.

## What problem it solves

Typical photo cleanup creates a loop of tiny decisions: identify a batch, make an album, decide what Favorites mean, export, compare, delete, and check again. This skill separates those concerns:

1. **Analyze:** find time-and-frequency clusters without changing Photos.
2. **Contain:** create mutually exclusive review albums and one verified yearly remainder album.
3. **Mark:** use Favorites as a neutral marker for any temporary subset.
4. **Decide:** record explicit keep, export, delete, merge, or close-batch decisions.
5. **Execute:** dry-run the grouped plan, recheck counts, apply once, and verify the result.

## Highlights

- Covers still images, videos, and Live Photos whenever a request says “photos.”
- Reuses complete existing albums instead of creating duplicates.
- Proves annual coverage with zero missing assets.
- Exports unmodified original resources and preserves embedded metadata.
- Defaults to complete Live Photo pairs; still-only export requires an explicit choice.
- Treats Favorites as markers, never as an automatic keep/delete rule.
- Uses current album membership and exact counts before destructive work.
- Keeps Photos sources, local sources, RAW files, and cloud backup safe by default.
- Uses Apple's public PhotoKit API and never reads or edits the private Photos database.

## Requirements

- macOS with Apple Photos.
- Xcode Command Line Tools (`xcrun` and the Swift compiler).
- Python 3.
- A local AI agent that can load Agent Skills and run terminal commands, such as Codex, Claude Code, or WorkBuddy.
- Full Photos Library access when macOS requests it.

The skill runs locally. It does not upload your photos or metadata.

## Agent compatibility

The complete `apple-photos/` folder follows the open Agent Skills layout: `SKILL.md` is the canonical contract, while `scripts/` and `references/` contain executable and progressively loaded support material. The optional `agents/openai.yaml` file improves Codex presentation but is not required by other agents.

| Agent | Installation |
|---|---|
| Codex | Copy `apple-photos/` to `~/.codex/skills/apple-photos/`, then restart Codex. |
| Claude Code | Copy it to `~/.claude/skills/apple-photos/` for personal use, or `.claude/skills/apple-photos/` inside a project. Invoke it as `/apple-photos`. |
| WorkBuddy | Download the release ZIP and use **Add Skill → Upload Skill** to import the local package. Invoke it from the Skills area, with `/apple-photos`, or by a matching natural-language request. |
| Other agents | Install the complete folder in that product's Agent Skills directory. If automatic discovery is unavailable, tell the agent to read `apple-photos/SKILL.md` before acting. |

The agent must run locally on the Mac that owns the Photos library. A remote or cloud-only agent cannot access the local System Photo Library unless it is connected to a trusted macOS runner with Photos permission.

See [Agent compatibility](docs/AGENT-COMPATIBILITY.md) for detailed installation and runtime behavior.

## Install for Codex

```bash
git clone https://github.com/lynnete07/apple-photos-skill.git
mkdir -p ~/.codex/skills
cp -R apple-photos-skill/apple-photos ~/.codex/skills/
cd ~/.codex/skills/apple-photos
bash scripts/install.sh
scripts/apple-photos status
```

Restart Codex after installing so the skill can be discovered. For Claude Code and WorkBuddy, use the agent-specific paths or upload flow above.

## Start with prompts, not commands

Most users should invoke the skill through their agent in natural language. Use `$apple-photos` in Codex, `/apple-photos` in Claude Code or WorkBuddy, or the installed skill name supported by the current client:

```text
Use $apple-photos to analyze my 2024 photos and videos. Only analyze; do not create or delete anything.
```

```text
Use $apple-photos to create the approved 2024 review batches and a catch-all album for every 2024 asset not covered by a batch or an existing album.
```

```text
Use $apple-photos to delete the unmarked assets in album “2024-08-24_Review”, keep the album, and verify that marked assets are untouched.
```

```text
Use $apple-photos to export unmodified originals from album “2024-10-03_Hong Kong” to /Volumes/Archive/Photos. Export complete Live Photo pairs and do not delete anything.
```

## Review-album naming

Album names in an analysis are editable proposals, not fixed system identifiers. The default pattern is:

```text
YYYY-MM-DD_<label>
```

- `YYYY-MM-DD` is the earliest Photos capture date in the proposed cluster, interpreted in the Mac's local time zone.
- A high-confidence, user-confirmed place or subject becomes the label, such as `2024-10-03_Hong Kong`.
- If the subject is uncertain, a concentrated event defaults to `Review topic`; a multi-day or multi-burst cluster defaults to `Review sequence`.
- The annual catch-all defaults to `YYYY_Unbatched` in English or `YYYY_未进入批次` when the user's working language is Chinese.
- An existing album that already covers the batch keeps its exact current name.

Before album creation, the analysis must show the proposed name, date range, asset count, evidence, and naming confidence. The user may rename one album, provide a naming template, change the language or separator, omit the date prefix, or rename the catch-all. The final manifest uses the approved title literally; the asset selection does not depend on the wording of the title. Titles only need to be non-empty and uniquely resolvable.

Example analysis output:

| Proposed album | Capture range | Assets | Naming evidence | Confidence | Editable |
|---|---|---:|---|---|---|
| `2024-08-24_Xi'an` | Aug 24, 10:12–18:46 | 63 | GPS concentrated in Xi'an; one-day shoot | High | Yes |
| `2024-09-02_Review sequence` | Sep 2–4 | 118 | Three continuous days and two bursts; no reliable place | Unknown | Yes |
| `2024_Unbatched` | Remaining annual assets | 27 | Computed by annual coverage verification | Functional | Yes |

If the user renames an album later in Apple Photos, the agent must re-inspect current titles and update any pending queue or manifest before another operation. See [Album naming rules](apple-photos/references/album-naming.md).

## Command-line entry points

The agent uses these bundled commands:

```bash
bash scripts/install.sh
scripts/apple-photos status
scripts/apple-photos inspect --album "Album name"
scripts/apple-photos scan --start "2024-01-01" --end "2025-01-01" --gap-hours 36
scripts/apple-photos validate-manifest --manifest /absolute/path/plan.json
scripts/apple-photos batch --manifest /absolute/path/plan.json
scripts/apple-photos batch --manifest /absolute/path/plan.json --apply
```

`batch` is a dry run. `batch --apply` repeats all safety checks before mutation.

## Safe defaults

| Setting | Public default |
|---|---|
| Photos assets after export | Keep |
| Local or external-drive sources | Keep |
| RAW files | Include and preserve |
| Live Photos | Export original still + paired motion resource |
| Cloud backup | Disabled |
| Archive path | Unset; must be configured |

These defaults are configurable, but a saved profile never grants blanket permission for an unrelated destructive action.

## Important safety behavior

- Deleting a Photos asset deletes it globally, not only from one album.
- Deleted assets move to **Recently Deleted**. Recovering them does not restore deleted album structure.
- Album titles must resolve uniquely.
- A changed asset count, authorization denial, iCloud download failure, duplicate title, or verification failure stops the operation.
- Export and delete can share one plan so deletion starts only after selected originals have been exported and verified.

Read [Safety model](docs/SAFETY.md) before the first destructive workflow.

## Repository layout

```text
apple-photos-skill/
├── apple-photos/          # Install this complete folder as the skill
│   ├── SKILL.md
│   ├── agents/
│   ├── references/
│   └── scripts/
├── docs/                  # Safety and cross-agent documentation
└── tests/                 # Public validation fixtures and tests
```

Keep the `apple-photos` directory structure unchanged when installing or redistributing it.

## Scope and limitations

- The skill works with the System Photo Library exposed through PhotoKit.
- iCloud-only originals must be downloadable before export can finish.
- Finder creation time is not capture time. The skill preserves original embedded metadata and separately reports the date shown by Photos.
- Archive comparison includes every format, including RAW, unless the user explicitly excludes a suffix.
- The skill does not infer people, events, or trip names from images. It proposes review batches from time, frequency, location, and device continuity.

## Contributing and security

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md). Never include real photo-library identifiers, personal paths, or private metadata in issues or test fixtures.

## License

[MIT](LICENSE)
