---
name: aws-security-audit
description: Run a security audit of an AWS environment with Prowler (official Docker image) across all regions or specific ones, produce CSV/JSON/HTML reports with failed findings by severity, and optionally create Jira tickets in the VM project for remediation. Use when the user asks to audit AWS security, scan an AWS account, run Prowler, check AWS misconfigurations, run a CIS benchmark on AWS, or review cloud security posture.
---

# AWS Security Audit (Prowler) + Jira

Audit an AWS account's security posture with [Prowler](https://github.com/prowler-cloud/prowler)
run from its official Docker image, covering **all regions by default** or only the regions the
user picks, and (on confirmation) create remediation tickets in the Jira **VM** project.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user before scanning** (AskUserQuestion or a direct question):
   - Which **AWS profile** to use (offer `default`; list candidates from `aws configure list-profiles`).
   - **All regions or specific ones?** All regions is Prowler's default. If they want specific
     regions, offer the enabled ones:
     `aws ec2 describe-regions --query "Regions[].RegionName" --output text --profile <profile>`
   - Optional **severity filter** (`critical high` is a common choice for a first pass; empty = all).
2. Verify tooling: Docker daemon running (`docker info`), `aws` CLI, `jq`.
3. Verify credentials and show the user which account will be scanned **before** running:
   ```bash
   aws sts get-caller-identity --profile <profile>
   ```
   The identity needs read access — the officially recommended policies are
   `arn:aws:iam::aws:policy/SecurityAudit` and `arn:aws:iam::aws:policy/job-function/ViewOnlyAccess`.
   For SSO profiles, run `aws sso login --profile <profile>` first if the token is expired.

## Step 2 — Run the audit

Run the bundled script — it pulls the **latest stable** Prowler image, injects short-lived
credentials via `aws configure export-credentials` (works with SSO/MFA/assumed roles; falls
back to mounting `~/.aws` read-only), runs the scan, and prints a severity summary.
Your shell's cwd is NOT this skill's folder — invoke it by full path:

```bash
bash "<this-skill-dir>/scripts/audit.sh" -p <profile> [-r "eu-west-1 us-east-1" | -r all] [-s "critical high"]
```

Reports always go under `~/aws-audit/<account-id>_REPORT_<datetime>/` (created automatically):
`.csv`, `.ocsf.json`, and `.html`, plus per-framework compliance CSVs under `compliance/`.

Env override: `PROWLER_IMAGE=<image:tag>` (default `prowlercloud/prowler:stable`).

Or run manually with Docker:

```bash
docker pull prowlercloud/prowler:stable
docker run --rm \
  $(aws configure export-credentials --profile <profile> --format env-no-export | sed 's/^/-e /') \
  -v "<output-dir>:/home/prowler/output" \
  prowlercloud/prowler:stable aws \
  -f eu-west-1 us-east-1 \
  -M csv json-ocsf html \
  -z
```

Notes:
- Omit `-f` entirely to scan **all regions** (Prowler's default).
- `-z` (`--ignore-exit-code-3`) — Prowler otherwise exits 3 when any check FAILs, which would
  read as a command failure.
- Other useful flags: `--severity critical high`, `--compliance cis_3.0_aws`,
  `--services s3 iam ec2`, `--excluded-region <r>`. List options with
  `prowler aws --list-compliance` / `--list-checks` / `--list-services`.

## Step 3 — Present the findings

Show the user:
- The severity summary the script prints (FAIL counts per severity + total).
- The top findings: read the OCSF JSON and list FAILed checks sorted severity-first, with
  check id, title, severity, region, and affected resource:
  ```bash
  jq -r '[.[] | select(.status_code == "FAIL")]
    | sort_by(.severity) | .[]
    | "\(.severity) | \(.metadata.event_code) | \(.finding_info.title) | \(.resources[0].region // "-") | \(.resources[0].uid // "-")"' \
    <report>.ocsf.json
  ```
  (Field layout can shift between Prowler versions — if a path is null, inspect one finding
  with `jq '.[0]'` and adapt.)
- Point them at the HTML report for browsing everything.

## Step 4 — Create Jira tickets in the VM project

**Always confirm with the user before creating tickets**, and ask which granularity:
- **One ticket per FAILed check** (recommended for critical/high only — one remediation task
  each), listing every affected resource/region under it, or
- **One summary ticket** with the severity table and top findings.

### Preferred: Atlassian MCP tools

1. `getAccessibleAtlassianResources` → `cloudId`.
2. `getVisibleJiraProjects` → confirm the **VM** project key.
3. `getJiraProjectIssueTypesMetadata` for VM → pick issue type (default **Bug**; fallback **Task**).
4. `getJiraIssueTypeMetaWithFields` → discover required fields; fill them or ask the user.
5. `createJiraIssue` per ticket:
   - `cloudId`, `projectKey: VM`, `issueTypeName` from above
   - `summary`: `AWS security: <check-id> — <check title> (<account-id>)`
   - `description`: severity, AWS account id, check id + title + description, affected
     resources (ARN/uid + region, one line each), compliance frameworks it maps to,
     Prowler's remediation recommendation text and doc link if present in the finding,
     and the report path on disk.

### Fallback: Jira REST API

Same as the gitleaks-audit skill: `POST $JIRA_BASE_URL/rest/api/3/issue` with
`JIRA_EMAIL`/`JIRA_API_TOKEN` basic auth, ADF description, project key `VM`.

## Step 5 — Wrap up

Report: account scanned, regions covered, FAIL counts by severity, report directory, and any
Jira ticket keys with links. The reports may contain resource ARNs and account details —
they live under `~/aws-audit/` outside any repo; don't commit them.
