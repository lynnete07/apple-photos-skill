# Apple Photos Agent Skill

[简体中文](README.zh-CN.md)

A safety-gated skill for reviewing large Apple Photos libraries with fewer repetitive decisions.

It analyzes one calendar year at a time, groups photos into review batches, reuses existing albums, creates a verified catch-all album, treats Favorites as neutral selection markers, exports unmodified originals, and executes only explicitly approved deletion plans.

## Who it is for

- People with large, long-running Apple Photos libraries.
- People who prefer explicit rules and predictable workflows, including neurodivergent users and anyone affected by decision fatigue.
- People who use Codex, Claude Code, WorkBuddy, or another Agent Skills-compatible local agent.

## Workflow

1. **Analyze:** find clusters from capture time, frequency, location, and device continuity without changing Photos.
2. **Contain:** reuse complete existing albums, create non-overlapping review albums, and verify a yearly catch-all album.
3. **Mark:** use Favorites as a temporary marker for any subset; Favorites never automatically mean keep or delete.
4. **Act:** execute only the approved keep, export, delete, merge, or close-batch decisions.
5. **Verify:** recheck current membership and exact counts before and after every mutation.

“Photos” includes still images, videos, and Live Photos. Exports use unmodified original resources and preserve embedded metadata. Live Photos default to the original still and paired motion resource; still-only export requires an explicit choice.

The skill uses Apple's public PhotoKit API. It never reads or edits the private Photos database.

## Requirements

- macOS with Apple Photos.
- Xcode Command Line Tools (`xcrun` and the Swift compiler).
- Python 3.
- A local AI agent that can load Agent Skills and run terminal commands.
- Full Photos Library access when macOS requests it.

All processing runs locally. The skill does not upload photos or metadata.

## Agent compatibility

The complete `apple-photos/` folder follows the open Agent Skills layout. `SKILL.md` is the canonical contract; `scripts/` and `references/` contain its executable and supporting resources. `agents/openai.yaml` is an optional Codex adapter, not a dependency.

| Agent | Installation |
|---|---|
| Codex | Copy `apple-photos/` to `~/.codex/skills/apple-photos/`, then restart Codex. |
| Claude Code | Copy it to `~/.claude/skills/apple-photos/`, or `.claude/skills/apple-photos/` inside a project. Invoke `/apple-photos`. |
| WorkBuddy | Download the release ZIP and use **Add Skill → Upload Skill**. |
| Other agents | Install the complete folder in the product's Agent Skills directory, or ask the agent to read `apple-photos/SKILL.md` before acting. |

The agent must run on the Mac that owns the Photos library, or use a trusted macOS runner with Photos permission. See [Agent compatibility](docs/AGENT-COMPATIBILITY.md) for details.

## Start with natural language

Use the installed skill name or the invocation syntax supported by your agent:

```text
Use the apple-photos skill to analyze all my 2026 photos and videos. Only analyze; do not create or delete anything.
```

```text
Create the approved 2026 review albums and one catch-all album for every 2026 asset not covered by a batch or an existing album.
```

```text
Delete the unmarked assets in album “2026-05-16_Family gathering,” keep the album, and verify that marked assets are untouched.
```

```text
Export unmodified originals from album “2026-09-12_Graduation ceremony” to my archive. Export complete Live Photo pairs and do not delete anything.
```

## Review-album naming

Names produced during analysis are editable proposals, not fixed identifiers. The default pattern is:

```text
YYYY-MM-DD_<label>
```

- The date is the earliest Photos capture date in the cluster, interpreted in the Mac's local time zone.
- A user-confirmed or high-confidence event becomes the label, for example `2026-05-16_Family gathering`.
- An uncertain concentrated event defaults to `Review topic`.
- An uncertain multi-day or multi-burst cluster defaults to `Review sequence`.
- The yearly catch-all defaults to `YYYY_Unbatched` in English or `YYYY_未进入批次` in Chinese.
- If an existing album already covers the batch, the skill reuses its current name instead of creating another album.

The analysis shows the proposed name, capture range, asset count, evidence, confidence, existing-album coverage, and whether the title is editable:

| Proposed album | Capture range | Assets | Evidence | Confidence | Editable |
|---|---|---:|---|---|---|
| `2026-05-16_Family gathering` | May 16, 10:12–18:46 | 63 | One-day burst; event confirmed by user | High | Yes |
| `2026-09-02_Review sequence` | Sep 2–4 | 118 | Three continuous days; subject unknown | Unknown | Yes |
| `2026_Unbatched` | Remaining annual assets | 27 | Annual coverage verification | Functional | Yes |

Before creation, the user may rename one album or change the naming template, language, separator, date prefix, or catch-all title. The final manifest uses the approved title literally; asset selection does not depend on title wording.

If an album is renamed later in Photos, the agent must re-inspect current titles and update pending queues or manifests before another operation. See [Album naming rules](apple-photos/references/album-naming.md).

## Safe defaults

| Setting | Public default |
|---|---|
| Photos assets after export | Keep |
| Local or external-drive sources | Keep |
| RAW files | Include and preserve |
| Live Photos | Export original still and paired motion resource |
| Archive path | Unset; the user must provide it |

A saved profile never grants blanket permission for an unrelated destructive action.

## Safety rules

- Deleting a Photos asset deletes it globally, not only from one album.
- Deleted assets move to **Recently Deleted**. Recovering them does not restore deleted album structure.
- Album titles must resolve uniquely.
- A changed asset count, authorization denial, iCloud download failure, duplicate title, or verification failure stops the operation.
- Export and delete may share one plan, but deletion begins only after selected originals are exported and verified.

Read the [Safety model](docs/SAFETY.md) before the first destructive workflow.

## Scope

- The skill works with the System Photo Library exposed through PhotoKit.
- iCloud-only originals must be downloadable before export can finish.
- Finder creation time is not capture time. The skill preserves embedded metadata and separately reports the date shown by Photos.
- Archive comparison uses SHA-256 and includes every format unless the user explicitly excludes one.
- The skill does not infer people, events, or trip names from images. It proposes batches from metadata and asks the user to confirm uncertain labels.

Install or redistribute the complete `apple-photos/` folder without changing its internal structure. See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md) for release and contribution details.

## License

[MIT](LICENSE)
