# aws-security-audit

A Claude Code skill that audits an AWS environment's security posture with
[Prowler](https://github.com/prowler-cloud/prowler) — across **all regions or specific
ones** — and can file remediation tickets in the Jira **VM** project.

## What it does

1. **Asks for scope first**: AWS profile, all regions vs. specific ones, optional severity
   filter — and shows you the account identity (`aws sts get-caller-identity`) before scanning.
2. Pulls the **latest stable** official Prowler Docker image (`prowlercloud/prowler:stable`)
   and runs the full check suite (or your severity/compliance subset).
3. Writes reports under `~/aws-audit/<account-id>_REPORT_<datetime>/` — CSV, OCSF JSON, and
   HTML, plus per-framework compliance CSVs — and prints FAIL counts by severity.
4. On your confirmation, creates Jira tickets in the **VM** project (Atlassian MCP connector,
   or Jira REST API fallback) — one per failed check (recommended) or a single summary ticket.

## Installation

```bash
# personal (all projects)
ln -s "$(pwd)/aws-security-audit" ~/.claude/skills/aws-security-audit

# or per-project
ln -s "$(pwd)/aws-security-audit" <project>/.claude/skills/aws-security-audit
```

### Requirements

- Docker running
- `aws` CLI v2 + `jq`
- AWS credentials with read access — recommended managed policies:
  `arn:aws:iam::aws:policy/SecurityAudit` and
  `arn:aws:iam::aws:policy/job-function/ViewOnlyAccess`
- For Jira tickets: the Atlassian (Rovo) MCP connector, **or** `JIRA_BASE_URL`,
  `JIRA_EMAIL`, `JIRA_API_TOKEN` env vars for the REST fallback

## Usage

In Claude Code, just ask — the skill triggers on prompts like:

- "audit my AWS environment"
- "run a security scan on AWS account X, eu-west-1 only"
- "check our AWS for misconfigurations and open Jira tickets for critical findings"
- "run the CIS benchmark against AWS"

### Running the scanner directly

```bash
bash aws-security-audit/scripts/audit.sh -p <profile> [-r "eu-west-1 us-east-1" | -r all] [-s "critical high"] [output-dir]
```

| Option / env | Default | Purpose |
|--------------|---------|---------|
| `-p <profile>` | `$AWS_PROFILE` or `default` | AWS profile to scan with |
| `-r <regions>` | `all` | Space-separated region list, or `all` |
| `-s <severities>` | all | e.g. `"critical high"` |
| `PROWLER_IMAGE` | `prowlercloud/prowler:stable` | Pin a specific image/tag |

Credentials are injected as short-lived env vars via `aws configure export-credentials`
(SSO/MFA/assume-role friendly); if that's unavailable, `~/.aws` is mounted read-only.

## Notes

- Prowler exits 3 when checks fail; the script passes `-z` so findings don't read as errors.
- SSO profiles: run `aws sso login --profile <p>` before auditing.
- Reports contain account IDs and resource ARNs — keep them out of git.

## Files

```
aws-security-audit/
├── SKILL.md          # skill definition + workflow Claude follows
├── README.md         # this file
└── scripts/
    └── audit.sh      # verify creds → pull image → prowler scan → severity summary
```
