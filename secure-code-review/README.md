# secure-code-review

A Claude Code skill for secure code review of **PHP, Java, Python, React (JS/TS), Flutter
(Dart), and Go** — automated SAST with [Semgrep](https://semgrep.dev) (official Docker image)
plus a manual review mapped to the **OWASP Top 10** and **CWE/SANS Top 25** — that can file
findings in the Jira **VM** project.

## What it does

1. **Asks for the source path first** and verifies Docker + jq.
2. Pulls the **latest** official Semgrep image (`semgrep/semgrep:latest`) and scans with the
   `p/owasp-top-ten`, `p/cwe-top-25`, `p/security-audit`, `p/secrets`, and per-language packs
   (`p/java`, `p/python`, `p/php`, `p/react`, `p/typescript`, `p/golang`). For Flutter it also
   runs `dart analyze` (Semgrep's Dart support is experimental).
3. Writes `semgrep.sarif`, `semgrep.json`, and `dart-analyze.txt` to
   `~/code-review/<name>_REPORT_<datetime>/` and prints a severity summary + top findings.
4. Claude then triages true/false positives, does a manual pass against
   `references/checklist.md`, and — on your confirmation — files Jira tickets in the **VM**
   project (Atlassian MCP connector, or REST API fallback).

## Language coverage

| Language | Automated | Notes |
|----------|-----------|-------|
| PHP, Java, Python, Go | Semgrep (GA) | + optional Psalm / SpotBugs+find-sec-bugs / Bandit / gosec |
| React (JS/TS/JSX/TSX) | Semgrep (GA) | + optional eslint-plugin-security, njsscan |
| Flutter (Dart) | `dart analyze` | Semgrep Dart is experimental; manual MASVS/MASTG review |

## Installation

```bash
ln -s "$(pwd)/secure-code-review" ~/.claude/skills/secure-code-review      # personal
# or per-project under <project>/.claude/skills/
```

### Requirements

- Docker running
- `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "do a secure code review of this repo"
- "run a SAST scan on ~/git/api and check OWASP Top 10"
- "security-review the Flutter app and open Jira tickets for criticals"
- "pull all our org repos and scan them one by one"

### Running the scanner directly

Single codebase:

```bash
bash secure-code-review/scripts/review.sh [-o output-dir] <source-dir>
```

All repos in an org/group (clones each and scans one by one, then aggregates):

```bash
# GitHub org/user (uses gh; must be authenticated)
bash secure-code-review/scripts/scan-org.sh <github-org>

# Any git host — a file with one clone URL per line
bash secure-code-review/scripts/scan-org.sh -f clone-urls.txt
```

| Option / env | Default | Purpose |
|--------------|---------|---------|
| `-l <n>` | `200` | Limit number of repos (GitHub mode) |
| `-o <dir>` | `~/code-review/<org>_ORGSCAN_<datetime>` | Output directory |
| `-k` | off | Keep full clones (default: shallow, deleted after each scan) |
| `SEMGREP_IMAGE` | `semgrep/semgrep:latest` | Pin a specific image/tag |

The org scan writes, under `~/code-review/<org>_ORGSCAN_<datetime>/`:
- `summary.md` — per-repo Error/Warning/Info/Total counts
- `findings-by-repo.md` — every finding grouped under its repo name (severity, rule, file:line,
  OWASP/CWE, message) — ready to open tickets from
- `findings.json` — the same as `{ "<repo>": [ {finding…}, … ] }` for driving ticket creation
- `reports/<repo>/` — full per-repo output (`findings.md`, `findings.json`, `semgrep.sarif`, …)

Org mode needs `git`, and `gh` (authenticated) for GitHub enumeration; the `-f` URL-file mode
works with any host (GitLab/Bitbucket/self-hosted).

## Notes

- Registry packs need network but **no Semgrep account**; the script disables telemetry and
  avoids `--config auto` (which would log in with your project URL).
- Semgrep produces false positives — findings must be triaged before filing tickets.
- For dependency CVEs (OWASP A06), layer in Trivy/OSV-Scanner:
  `docker run --rm -v "$PWD:/src" aquasec/trivy fs /src`.

## Files

```
secure-code-review/
├── SKILL.md              # skill definition + workflow Claude follows
├── README.md             # this file
├── references/
│   └── checklist.md      # OWASP Top 10 + CWE Top 25 review guide, per-language
└── scripts/
    ├── review.sh         # pull Semgrep -> SAST (+ dart analyze) -> severity summary
    └── scan-org.sh       # enumerate + clone all org repos, review each, aggregate summary.md
```
