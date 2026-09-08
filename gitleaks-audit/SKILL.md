---
name: gitleaks-audit
description: Run a full-history gitleaks secret scan across ALL branches and commits of a git repo, produce an unredacted findings report (commit, file, line numbers, rule, secret, author), and optionally create Jira tickets in the VM project for remediation. Use when the user asks to scan a repo for secrets, run gitleaks, check for leaked credentials, audit git history for credentials, scan for hardcoded API keys/tokens/passwords, or file secret-leak tickets in Jira.
---

# Gitleaks Full-History Audit + Jira

Scan every commit on every branch of the target repository with gitleaks, build a complete
unredacted report, and (on confirmation) create remediation tickets in the Jira **VM** project.

## Parallelize with subagents

When the scan returns **many findings**, fan out subagents (launch several in ONE message) to
work them in parallel, then aggregate:
- one subagent per unique secret (or a batch of them) to confirm whether it is still live vs.
  already rotated, identify the owning service/system, and draft the rotation-ticket content.

Do **not** fan out the Jira ticket-creation step — a single agent creates tickets after your
confirmation, so the same secret can't spawn duplicate tickets.

## Step 1 — Preconditions

1. **Always ask the user for the repo path on disk before scanning** (use AskUserQuestion or
   a direct question) — do not assume the current working directory, even if it is a git repo.
   Offer the cwd as a suggested option, but wait for the user to confirm or provide a path.
   Verify the given path exists and is a git repo (`git -C <path> rev-parse --git-dir`) before
   proceeding; if not, ask again.
2. Verify tooling. Gitleaks runs via its **official Docker image** (`ghcr.io/gitleaks/gitleaks`)
   — no local install needed. Check the daemon is up; fall back to a local binary only if
   Docker is unavailable:
   ```bash
   docker info >/dev/null 2>&1 && echo "docker OK" \
     || command -v gitleaks >/dev/null && echo "binary OK" \
     || echo "start Docker or: brew install gitleaks"
   command -v jq >/dev/null || { [ "$(uname)" = "Darwin" ] && brew install jq; }
   ```
3. Make sure all remote branches are locally known — gitleaks' `--all` only walks refs that
   exist locally (skip this if using the bundled script in Step 2; it fetches internally):
   ```bash
   git -C <repo> fetch --all --prune --tags
   ```

## Step 2 — Scan all branches and all commits

Run the bundled script (preferred — it pulls the **latest** gitleaks Docker image, fetches
refs, scans, and generates both reports; it falls back to a local gitleaks binary if Docker
is down).
Your shell's cwd is the target repo, NOT this skill's folder, so invoke the script by its
full path relative to the directory containing this SKILL.md:

```bash
bash "<this-skill-dir>/scripts/scan.sh" <repo-path> [output-dir]
```

Env overrides: `GITLEAKS_MODE=docker|binary` forces an execution mode;
`GITLEAKS_IMAGE=<image:tag>` pins the image (default `ghcr.io/gitleaks/gitleaks:latest`).

Reports always go under `~/gitleaks/<repo-name>_REPORT_<datetime>/` (created automatically,
one timestamped directory per run) — deliberately outside the scanned repo so the unredacted
report cannot be committed by accident. The script does this by default; if you run gitleaks
manually, create the same directory first:

```bash
OUT=~/gitleaks/"$(basename <repo-path>)_REPORT_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
```

Or run it manually with Docker. Pull first — `docker run` won't refresh an already-cached
`:latest` tag, and the scan must use the newest gitleaks release. The key is
`--log-opts="--all --full-history"` (quoted, so it reaches gitleaks as one value), which
makes gitleaks walk **every ref and every commit**, not just the current branch. Mount the
repo read-only, mount an output dir for the report, and mark the mounted repo as a git
`safe.directory` (host UID ≠ container UID, otherwise git aborts with "dubious ownership"):

```bash
docker pull ghcr.io/gitleaks/gitleaks:latest
docker run --rm \
  -v "<repo-path>:/repo:ro" \
  -v "<output-dir>:/out" \
  -e GIT_CONFIG_COUNT=1 \
  -e GIT_CONFIG_KEY_0=safe.directory \
  -e GIT_CONFIG_VALUE_0='*' \
  ghcr.io/gitleaks/gitleaks:latest \
  git /repo \
  --log-opts="--all --full-history" \
  --report-format json \
  --report-path /out/gitleaks-report.json \
  --exit-code 0
```

Without Docker, the local-binary equivalent is:

```bash
gitleaks git <repo-path> \
  --log-opts="--all --full-history" \
  --report-format json \
  --report-path gitleaks-report.json \
  --exit-code 0
```

Rules:
- **NEVER pass `--redact`.** The report must contain the real secret values so the team can
  identify exactly which credentials to rotate. Do not mask, truncate, or elide secrets in the
  report file or the summary you show the user.
- Use `--exit-code 0` so a non-empty finding set doesn't read as a command failure
  (gitleaks otherwise exits 1 on findings).
- Older gitleaks (< 8.19) uses `gitleaks detect --source <repo> --log-opts="--all --full-history"`
  — same flags otherwise.
- Sanity-check the scan output: if gitleaks reports **0 commits scanned** on a repo with
  history, something intercepted `git log` (known gitleaks issue when git writes to stderr,
  e.g. git-crypt) — investigate rather than reporting "clean".
- If the repo has a `.gitleaks.toml`, gitleaks picks it up automatically; mention to the user
  if it contains an allowlist, since that suppresses findings.

## Step 3 — Build the findings report

**If you used the bundled script, this step is already done** — read `<output-dir>/gitleaks-report.md`
and show the user its summary and table. Only build the report manually if you ran gitleaks yourself.

Each JSON finding contains: `RuleID`, `Description`, `File`, `SymlinkFile`, `StartLine`,
`EndLine`, `StartColumn`, `EndColumn`, `Secret`, `Match`, `Entropy`, `Commit`, `Author`,
`Email`, `Date`, `Message`, `Tags`, `Fingerprint` (and sometimes `Link`).

Gitleaks does not record which branches contain a commit — add that yourself:

```bash
git -C <repo> branch -a --contains <commit-sha> --format='%(refname:short)'
```

Produce a markdown report with, per finding:

| # | Rule | Secret (unredacted) | File | Lines | Commit | Branches | Live@HEAD | Author | Date |

Plus a summary header: total findings, unique secrets (dedupe by `Secret` value), unique
files, rules triggered, and whether each secret is still present at the default branch HEAD
(live in the tree) vs. only in history — check with `git grep -F <secret> <default-branch>`.

Show the user the summary and the full table.

## Step 4 — Create Jira tickets in the VM project

Ticket creation posts secrets into a shared system — **always confirm with the user before
creating tickets**, and ask which granularity they want:

- **One ticket per unique secret** (recommended — each secret has one rotation task), listing
  every commit/file/line occurrence of that secret, or
- **One summary ticket** containing the whole findings table.

### Preferred: Atlassian MCP tools

If the Atlassian (Rovo) MCP tools are connected:

1. `getAccessibleAtlassianResources` → get `cloudId`.
2. `getVisibleJiraProjects` → confirm the **VM** project key exists.
3. `getJiraProjectIssueTypesMetadata` for VM → pick issue type (default **Bug**; fall back to **Task**).
4. `getJiraIssueTypeMetaWithFields` for the chosen type → discover required fields; populate
   any mandatory custom fields (components, priority, ...) or ask the user for values.
5. `createJiraIssue` per ticket with:
   - `cloudId`: from step 1
   - `projectKey`: `VM`
   - `issueTypeName`: the type chosen in step 3
   - `summary`: `Leaked secret: <RuleID> in <repo-name> (<file>)`
   - `description` (full detail, unredacted):
     - Rule / description
     - Secret value
     - Repository
     - File path + start–end lines
     - Commit SHA, author, email, date, commit message
     - Branches containing the commit, and whether it is live at default-branch HEAD
     - Fingerprint
     - Remediation checklist: rotate the credential, purge from history if required
       (`git filter-repo`), move to a secret manager, add a pre-commit gitleaks hook.

### Fallback: Jira REST API

If MCP is unavailable, use the REST API with env vars `JIRA_BASE_URL`, `JIRA_EMAIL`,
`JIRA_API_TOKEN` (never hardcode the token):

```bash
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "$JIRA_BASE_URL/rest/api/3/issue" \
  -d @ticket.json
```

`ticket.json` uses `{"fields": {"project": {"key": "VM"}, "issuetype": {"name": "Bug"}, "summary": ..., "description": <ADF doc>}}`.
Description must be Atlassian Document Format (ADF) for API v3.

## Step 5 — Wrap up

Report to the user: number of findings, report file paths, and the created Jira ticket keys
with links. Remind them the report files contain live secrets — they live under `~/gitleaks/`
outside any repo by default; if the user relocated them into a repo, suggest adding the path
to `.gitignore`.
