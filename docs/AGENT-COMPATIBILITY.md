# Agent compatibility

The installable unit is the complete `apple-photos/` folder. It follows the [open Agent Skills structure](https://agentskills.io/home): a required `SKILL.md` plus optional scripts, references, and client adapters.

## Shared runtime requirements

Every agent must:

- run locally on macOS with Apple Photos;
- have terminal access to `bash`, Python 3, `xcrun`, and the Swift compiler;
- receive Full Photos Library access from macOS;
- preserve the skill folder structure;
- read `SKILL.md` as the canonical workflow;
- dry-run destructive manifests and require explicit current authorization before apply.

A cloud-only agent cannot operate the user's local Photos library. It needs a trusted macOS runner connected to that library and authorized by the user.

## Codex

```bash
mkdir -p ~/.codex/skills
cp -R apple-photos ~/.codex/skills/
cd ~/.codex/skills/apple-photos
bash scripts/install.sh
```

Restart Codex, then invoke `$apple-photos` or use a natural-language request matching the skill description.

## Claude Code

Personal installation:

```bash
mkdir -p ~/.claude/skills
cp -R apple-photos ~/.claude/skills/
cd ~/.claude/skills/apple-photos
bash scripts/install.sh
```

For one repository, install at `.claude/skills/apple-photos/`. Invoke `/apple-photos` or ask Claude naturally. Claude Code can load the open-standard `SKILL.md`; the OpenAI adapter is not required. See the official [Claude Code skills documentation](https://code.claude.com/docs/en/skills).

## WorkBuddy

Download the release ZIP, then choose **Add Skill → Upload Skill** and select the local package. WorkBuddy performs its own security review before installation. After installation, enable the skill and invoke it from the Skills area, with `/apple-photos`, or with a matching natural-language request. See the official [WorkBuddy Skills documentation](https://www.workbuddy.ai/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Skills).

The uploaded package includes executable scripts that access the local Photos library. Review the source, keep destructive permissions conservative, and allow Photos access only when WorkBuddy runs the expected bridge.

## Other Agent Skills clients

Install the complete folder in the client's documented skill directory. If the client supports only a prompt file, it may read `SKILL.md`, but it must also expose terminal execution and local macOS Photos permissions for the operational workflows to work.

Client-specific metadata is optional. No client adapter may override the safety gates in `SKILL.md`.
