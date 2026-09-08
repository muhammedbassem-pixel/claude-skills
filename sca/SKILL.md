---
name: sca
description: Software Composition Analysis — generate an SBOM and scan a project's third-party dependencies for known vulnerabilities and license risk across ecosystems (npm, pip, Go, Maven, Gradle, Ruby, PHP, Rust, …) with Trivy (SBOM + vuln + license) cross-checked by OSV-Scanner, then optionally create Jira tickets in the VM project. Use when the user asks for SCA, an SBOM, a dependency/vulnerability audit, a license-compliance check, or to scan third-party/open-source components.
---

# Software Composition Analysis (SBOM · vulns · licenses) + Jira

Analyze a project's third-party dependencies: generate an **SBOM**, find **known-vulnerable
dependencies**, and flag **license risk** — using [Trivy](https://trivy.dev) (SBOM + vuln +
license in one pass) cross-checked by [OSV-Scanner](https://github.com/google/osv-scanner) — and
(on confirmation) raise Jira tickets in the **VM** project.

## Parallelize with subagents

Fan out subagents (launch several in ONE message) for independent work, then aggregate:
- for a **monorepo / many services**, one subagent per module/lockfile directory to run the scan
  and triage in parallel;
- one subagent per severity tier (or per vulnerable package) to confirm the fixed version and
  draft the upgrade-ticket content;
- one subagent to review the **license** findings (forbidden/restricted) while others handle
  vulns.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicates.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user for the project path on disk** (AskUserQuestion or a direct question) — do not
   assume the cwd. Optionally ask the severity floor (default `CRITICAL,HIGH,MEDIUM`) and whether
   license compliance matters for this project.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`.

## Step 2 — Run the SCA scan

Run the bundled script — it generates a CycloneDX SBOM, scans dependencies for vulnerabilities
and license risk with Trivy, and cross-checks vulns with OSV-Scanner. Invoke by full path:

```bash
bash "<this-skill-dir>/scripts/sca.sh" [-s CRITICAL,HIGH,MEDIUM] <project-dir>
```

Output goes to `~/sca/<name>_REPORT_<datetime>/`:
- `sbom.cdx.json` — CycloneDX SBOM (feed to other tools, or attach to a release)
- `vuln-findings.json` — ticket-ready vulns (advisory, package, installed→fixed, severity, url)
- `license-findings.json` — license risk (category, license, package, severity)
- `trivy-sca.json`, `osv.json` — raw scanner output
- `sca-report.md` — summary + vulnerable-deps table + license-risk table

Env overrides: `TRIVY_IMAGE`, `OSV_IMAGE`.

Or run manually:

```bash
docker run --rm -v "$PWD:/src:ro" -v "$PWD/out:/out" aquasec/trivy:latest \
  fs --scanners vuln,license --format json -o /out/trivy-sca.json /src
docker run --rm -v "$PWD:/src:ro" ghcr.io/google/osv-scanner:latest \
  scan source -r --format json /src > out/osv.json
```

Notes:
- Trivy reads the common lockfiles across ecosystems (npm/yarn/pnpm, pip/poetry/pipenv, go.mod,
  Cargo.lock, Gemfile.lock, composer.lock, Maven pom, Gradle) — scan a directory with lockfiles
  committed for the most accurate, transitive results.
- **License risk categories** (Trivy → severity): `forbidden` (CRITICAL), `restricted` (HIGH),
  `reciprocal` (MEDIUM), `notice`/`permissive`/`unencumbered` (LOW), `unknown`. Treat
  forbidden/restricted as blockers for distributed software.
- OSV-Scanner uses an independent feed (OSV.dev); differences between it and Trivy are normal —
  union the two for coverage.

## Step 3 — Triage and prioritize

1. **Vulnerabilities** — sort by severity; prioritize those with a **fixed version available**
   (`fixed` non-empty) and those on a direct (not deep-transitive) dependency. Confirm the
   upgrade path (does bumping the top-level dep pull the fixed version?).
2. **Licenses** — review forbidden/restricted findings against how the software is distributed;
   flag anything incompatible with the project's license.
3. Produce a prioritized remediation list: package, current→target version, severity, and effort.

## Step 4 — Create Jira tickets in the VM project

**Always confirm before creating tickets.** Ask granularity: **one ticket per vulnerable
package** (bundling its CVEs and the target version — recommended), a **license-compliance
ticket**, or a **summary ticket**. Drive tickets from `vuln-findings.json` /
`license-findings.json`. Use the Atlassian MCP flow (`getAccessibleAtlassianResources` →
`getVisibleJiraProjects` → `getJiraProjectIssueTypesMetadata` → `getJiraIssueTypeMetaWithFields`
→ `createJiraIssue`, `projectKey: VM`) or the REST API fallback (`POST
$JIRA_BASE_URL/rest/api/3/issue`, ADF description).

## Step 5 — Wrap up

Report: dependency counts, vulnerable-dep counts by severity (and fixable), license risk
(forbidden/restricted), the SBOM path, report directory, and any Jira ticket keys with links.
Recommend committing lockfiles and wiring this scan into CI to catch regressions.
