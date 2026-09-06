# gitleaks-audit

A Claude Code skill that scans a git repository for leaked secrets across **all branches
and all commits** using [gitleaks](https://github.com/gitleaks/gitleaks), produces an
**unredacted** findings report, and can file remediation tickets in the Jira **VM** project.

## What it does

1. **Asks you for the repo path on disk first** — it never assumes the current directory.
2. Pulls the **latest** official Docker image (`ghcr.io/gitleaks/gitleaks:latest`) and runs
   gitleaks over the repo's full history (`--log-opts="--all --full-history"`); falls back
   to a local `gitleaks` binary if Docker isn't running.
3. Generates two reports — JSON plus a markdown summary — under
   `~/gitleaks/<repo-name>_REPORT_<datetime>/`, with, per finding:
   rule, **raw secret value (never redacted)**, file path, line range, commit SHA,
   branches containing the commit, whether the secret is still **live at the default
   branch HEAD**, author, date, entropy, and fingerprint.
4. On your confirmation, creates Jira tickets in the **VM** project (via the Atlassian MCP
   connector, or the Jira REST API as fallback) — one ticket per unique secret
   (recommended) or a single summary ticket.

## Installation

Copy or symlink the skill where Claude Code discovers skills:

```bash
# personal (all projects)
ln -s "$(pwd)/gitleaks-audit" ~/.claude/skills/gitleaks-audit

# or per-project
ln -s "$(pwd)/gitleaks-audit" <project>/.claude/skills/gitleaks-audit
```

### Requirements

- Docker running (preferred), **or** `gitleaks` installed locally (`brew install gitleaks`)
- `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, **or** env vars
  `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` for the REST fallback

## Usage

In Claude Code, just ask — the skill triggers on prompts like:

- "scan this repo for secrets"
- "run gitleaks on ~/git/backend and check every branch"
- "check for leaked credentials in git history"
- "scan for hardcoded API keys and open Jira tickets for what you find"

Claude runs the scan, shows you the findings table, and **asks for confirmation before
creating any Jira ticket** (tickets contain the raw secret values).

### Running the scanner directly

```bash
bash gitleaks-audit/scripts/scan.sh <repo-path> [output-dir]
```

| Env var | Default | Purpose |
|---------|---------|---------|
| `GITLEAKS_MODE` | `auto` | Force `docker` or `binary` execution |
| `GITLEAKS_IMAGE` | `ghcr.io/gitleaks/gitleaks:latest` | Pin a specific image/tag |

Reports always land under `~/gitleaks/<repo-name>_REPORT_<datetime>/` (created automatically,
one timestamped directory per run) — intentionally **outside** the scanned repo so the
unredacted report can't be committed by accident:

- `gitleaks-report.json` — raw gitleaks findings
- `gitleaks-report.md` — summary header + findings table + full per-finding detail

## Notes & caveats

- **Reports contain live secrets.** Handle them like credentials: don't commit them,
  don't paste them anywhere you wouldn't paste a password.
- `--all` only scans refs that exist locally; the script runs
  `git fetch --all --prune --tags` first, but repos with no remote are scanned as-is.
- A repo's own `.gitleaks.toml` allowlist is honored automatically and can suppress
  findings — check it if results look thin.
- Gitleaks' built-in config ignores well-known example keys (e.g. AWS's
  `AKIAIOSFODNN7EXAMPLE`), so planted doc samples won't appear.
- If gitleaks reports **0 commits scanned** on a repo that has history, something broke
  the underlying `git log` (e.g. git-crypt writing to stderr) — treat it as a failed scan,
  not a clean one.

## Files

```
gitleaks-audit/
├── SKILL.md          # skill definition + workflow Claude follows
├── README.md         # this file
└── scripts/
    └── scan.sh       # fetch refs → scan (Docker/binary) → build JSON + markdown reports
```
