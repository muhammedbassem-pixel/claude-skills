# sca

A Claude Code skill for **Software Composition Analysis**: generate an SBOM and scan a project's
third-party dependencies for known **vulnerabilities** and **license risk** across ecosystems —
filing findings in the Jira **VM** project.

## What it does

1. **Asks for the project path** and verifies Docker + jq.
2. Generates a **CycloneDX SBOM** and scans dependencies for vulnerabilities + license risk with
   **Trivy** (`aquasec/trivy`), then cross-checks vulns with **OSV-Scanner**
   (`ghcr.io/google/osv-scanner`) for independent coverage.
3. Writes `sbom.cdx.json`, ticket-ready `vuln-findings.json` and `license-findings.json`, the raw
   scanner output, and `sca-report.md` to `~/sca/<name>_REPORT_<datetime>/`.
4. Triages by severity/fixability and license category, then — on your confirmation — files Jira
   tickets in the **VM** project (Atlassian MCP or REST fallback).

## Ecosystems

Reads the common lockfiles/manifests: npm (`package-lock.json`), yarn, pnpm, pip
(`requirements.txt`), Poetry, Pipenv, Go (`go.mod`), Rust (`Cargo.lock`), Ruby
(`Gemfile.lock`), PHP (`composer.lock`), Maven (`pom.xml`), and Gradle. Commit lockfiles for
accurate transitive results.

## Installation

```bash
ln -sfn "$(pwd)/sca" ~/.claude/skills/sca      # personal
```

### Requirements

- Docker running; `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "run SCA on this repo"
- "generate an SBOM and check our dependencies for CVEs"
- "check our third-party libraries for license risk and open tickets"

### Running the scanner directly

```bash
bash sca/scripts/sca.sh [-s CRITICAL,HIGH,MEDIUM] [-o output-dir] <project-dir>
```

| Option / env | Purpose |
|--------------|---------|
| `-s <sev>` | Vulnerability severities to report (default `CRITICAL,HIGH,MEDIUM`) |
| `TRIVY_IMAGE` / `OSV_IMAGE` | Pin scanner image/tag |

## Notes

- **License risk categories** (Trivy → severity): forbidden (CRITICAL), restricted (HIGH),
  reciprocal (MEDIUM), notice/permissive/unencumbered (LOW), unknown. Treat forbidden/restricted
  as blockers for distributed software.
- Trivy and OSV-Scanner use different vuln feeds; the union gives the best coverage.
- The CycloneDX SBOM (`sbom.cdx.json`) can be attached to releases or fed to other tools
  (including OSV-Scanner's `--sbom` mode).

## Files

```
sca/
├── SKILL.md              # workflow Claude follows
├── README.md             # this file
├── references/
│   └── tooling.md        # tool choices, ecosystems, license categories
└── scripts/
    └── sca.sh            # Trivy SBOM+vuln+license (+ OSV cross-check) -> findings + report
```
