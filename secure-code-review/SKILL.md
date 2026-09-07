---
name: secure-code-review
description: Perform a secure code review of PHP, Java, Python, React (JS/TS), Flutter (Dart), or Go code, combining automated SAST (Semgrep official Docker image, plus dart analyze for Flutter) with a manual review mapped to the OWASP Top 10 and CWE/SANS Top 25, and optionally create Jira tickets in the VM project. Use when the user asks for a security code review, secure code audit, SAST scan, OWASP Top 10 / SANS Top 25 review, or to find vulnerabilities in source code.
---

# Secure Code Review (OWASP Top 10 + SANS/CWE Top 25) + Jira

Review a codebase for security vulnerabilities across **PHP, Java, Python, React (JS/TS),
Flutter (Dart), and Go** — automated SAST via [Semgrep](https://semgrep.dev) plus manual
analysis mapped to the OWASP Top 10 and CWE/SANS Top 25 — and (on confirmation) create Jira
tickets in the **VM** project.

Read `references/checklist.md` (in this skill's directory) for the full category-by-category
and per-language review guide — use it to drive the manual pass.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user for the source path on disk** (AskUserQuestion or a direct question) — do not
   assume the cwd. Confirm the path exists. Optionally ask which languages/areas to focus on.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`.

## Step 2 — Run automated SAST

Run the bundled script — it pulls the **latest** official Semgrep image and scans with the
OWASP Top 10, CWE Top 25, security-audit, secrets, and per-language rule packs; if a
`pubspec.yaml` is present it also runs `dart analyze` (Semgrep's Dart support is only
experimental). Invoke it by full path:

```bash
bash "<this-skill-dir>/scripts/review.sh" <source-dir>
```

Reports go to `~/code-review/<name>_REPORT_<datetime>/`: `semgrep.sarif`, `semgrep.json`,
and (for Flutter) `dart-analyze.txt`. The script prints a severity summary and the top findings.

Env override: `SEMGREP_IMAGE=<image:tag>` (default `semgrep/semgrep:latest`).

Or run manually:

```bash
docker pull semgrep/semgrep:latest
docker run --rm -u "$(id -u):$(id -g)" -v "<src>:/src:ro" -v "<out>:/out" \
  semgrep/semgrep:latest semgrep scan \
  --config p/security-audit --config p/owasp-top-ten --config p/cwe-top-25 \
  --config p/java --config p/python --config p/php \
  --config p/react --config p/typescript --config p/golang \
  --metrics=off --sarif -o /out/semgrep.sarif /src
```

Notes:
- Go's registry pack is **`p/golang`** (`p/go` is a 404).
- `p/...` packs download rules from the registry (network needed) but require **no account**.
  Avoid `--config auto`, which logs in to the registry with your project URL.
- Semgrep applies only the rules matching each file's language, so bundling all packs is safe.
- For **Flutter/Dart**, `dart analyze` is a quality+lint baseline, not full security SAST —
  lean on the manual MASVS/MASTG review in the checklist.

## Step 3 — Triage and review

1. **Triage the SAST output** — read `semgrep.json`; sort findings severity-first. For each,
   confirm it's a true positive by reading the flagged code (`path:line`). Semgrep produces
   false positives; verify before reporting.
2. **Manual pass** — use `references/checklist.md` to cover what SAST misses: access-control
   logic (A01), insecure design (A04), auth flows (A07), and the per-language focus items.
3. **Optional SCA** — for OWASP A06 (vulnerable dependencies), run
   `docker run --rm -v "<src>:/src" aquasec/trivy fs /src`.
4. Produce a findings report: for each confirmed issue give severity, OWASP/CWE mapping, file
   and line, a description, and a remediation recommendation.

## Step 4 — Create Jira tickets in the VM project

**Always confirm with the user before creating tickets**, and ask which granularity:
- **One ticket per confirmed vulnerability** (recommended, at least for high/critical), or
- **One summary ticket** with the findings table.

### Preferred: Atlassian MCP tools

1. `getAccessibleAtlassianResources` → `cloudId`.
2. `getVisibleJiraProjects` → confirm the **VM** project key.
3. `getJiraProjectIssueTypesMetadata` for VM → pick issue type (default **Bug**).
4. `getJiraIssueTypeMetaWithFields` → discover required fields; fill them or ask the user.
5. `createJiraIssue`:
   - `cloudId`, `projectKey: VM`, `issueTypeName` from above
   - `summary`: `[Security] <OWASP/CWE> <short title> in <file>`
   - `description`: severity, OWASP Top 10 category + CWE id, file/line, code snippet, impact,
     remediation, and the report path on disk.

### Fallback: Jira REST API

`POST $JIRA_BASE_URL/rest/api/3/issue` with `JIRA_EMAIL`/`JIRA_API_TOKEN` basic auth, ADF
description, project key `VM`.

## Step 5 — Wrap up

Report: languages reviewed, confirmed-finding counts by severity, report directory, and any
Jira ticket keys with links. Note that SAST is a first pass — call out the manual-review
categories (access control, design, auth) that need human judgment.
