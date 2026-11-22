# Review-album naming

Album titles are editable organizational labels. They never determine which assets belong to a candidate cluster. Cluster membership comes from the analyzed date range and asset identifiers; later exact-album actions use the title currently present in Photos.

## Default proposal

Use the user's working language. The default batch pattern is:

```text
YYYY-MM-DD_<label>
```

The date is the earliest `PHAsset.creationDate` in the cluster, interpreted in the Mac's local time zone. Report the complete start/end range separately; do not make a long title merely to encode the end date.

Choose the label in this order:

1. **Existing complete coverage:** reuse the exact existing album title. Do not rename or create another album.
2. **User-confirmed subject or place:** use the user's wording exactly.
3. **High-confidence evidence:** propose a concise place or subject only when GPS, metadata, or visible evidence supports it. Mark it as a proposal until the user approves it.
4. **Unknown concentrated event:** use `待识别主题` in Chinese or `Review topic` in English.
5. **Unknown multi-day or multi-burst cluster:** use `待识别连续段` in Chinese or `Review sequence` in English.

When a broad location is reliable but the event is unknown, a label such as `西安待识别主题` or `Xi'an review topic` is acceptable. Do not guess a specific venue, person, trip, or event.

The language-aware annual catch-all defaults to:

```text
YYYY_未进入批次
YYYY_Unbatched
```

Do not create the catch-all when the computed remainder is empty.

## Required analysis output

For every create/fill proposal, show:

- proposed title;
- start and end time;
- asset count and media mix;
- evidence used for the label;
- naming confidence: high, medium, or unknown;
- coverage decision: reuse, fill existing, or create new;
- `editable: yes` for every new title.

Recommended table:

| Proposed title | Capture range | Assets | Evidence | Confidence | Coverage | Editable |
|---|---|---:|---|---|---|---|
| `2024-08-24_Xi'an` | `2024-08-24 10:12`—`18:46` | 63 | GPS concentrated in Xi'an | high | create new | yes |
| `2024-09-02_Review sequence` | `2024-09-02`—`09-04` | 118 | multi-day, two bursts, no reliable place | unknown | create new | yes |

Do not create albums during an analysis-only request.

## User overrides

Before manifest creation, accept any of these without arguing for the default:

- a different title for one proposed album;
- a global template or separator;
- another language;
- no date prefix;
- a different date format;
- a custom unknown-label or catch-all title.

Use the final approved string literally. The only hard title requirements are:

- non-empty;
- exact and uniquely resolvable in Photos;
- not shared by two different proposed batches;
- not misleadingly reused for unrelated existing contents without explicit approval.

If a proposed title collides with an unrelated existing album, stop and offer a semantic qualifier or a user-selected title. Never append an unexplained numeric suffix automatically.

## Rename after creation

The user may rename a review album directly in Photos. Before any later export, merge, queue execution, or deletion:

1. inspect current exact album titles;
2. replace stale titles in pending manifests and decision queues;
3. recheck unique resolution and current membership;
4. do not infer that a missing old title means the assets were deleted.

Existing albums are preserved and reused under their current titles unless the user explicitly requests a rename.
