# image-scan

A Claude Code skill that scans a container image for vulnerabilities/secrets/misconfigurations
with [Trivy](https://trivy.dev), recommends and generates a migration to a hardened
**distroless** base image, can build and push the hardened image to **Amazon ECR**, and files
findings in the Jira **VM** project.

## What it does

1. **Asks which image to scan** (and severity focus), verifies Docker + jq.
2. Pulls the **latest** Trivy image (`aquasec/trivy:latest`) and scans for vulnerabilities,
   secrets, and misconfigurations.
3. Writes `trivy.json`, a ticket-ready `findings.json`, and `image-report.md` to
   `~/image-scan/<image>_REPORT_<datetime>/`.
4. Recommends and generates a **distroless multi-stage Dockerfile** (Go/Node/Java/Python) to
   cut the attack surface, and offers to rebuild + re-scan to prove the CVE reduction.
5. Optionally builds and pushes the hardened image to **ECR** (creates the repo, logs in, tags,
   pushes, optional scan-on-push) — on your confirmation.
6. Files Jira tickets in the **VM** project (Atlassian MCP or REST fallback).

## Installation

```bash
ln -sfn "$(pwd)/image-scan" ~/.claude/skills/image-scan      # personal
```

### Requirements

- Docker running
- `jq`
- For the ECR step: AWS CLI v2 + credentials with ECR push permissions
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "scan the image myapp:latest for vulnerabilities"
- "check this Docker image for CVEs and move it to distroless"
- "harden our Dockerfile and push the distroless image to ECR"

### Running the scripts directly

```bash
# scan an image
bash image-scan/scripts/scan.sh [-s CRITICAL,HIGH] [-u] <image[:tag]>

# push a (hardened) local image to ECR
bash image-scan/scripts/push-ecr.sh [-p profile] [-r region] [-s] <local-image> <ecr-repo[:tag]>
```

| Option / env | Purpose |
|--------------|---------|
| `-s <sev>` (scan) | Severities, default `CRITICAL,HIGH` |
| `-u` (scan) | Only vulnerabilities with a fix available |
| `-s` (push) | Enable scan-on-push (basic ECR scanning) |
| `TRIVY_IMAGE` | Pin the Trivy image/tag |

## Notes

- `references/distroless.md` has the base-image selection table and multi-stage Dockerfile
  patterns for Go, Node.js, Java, and Python, plus the caveats (no shell, `:nonroot`, exec-form
  entrypoint, keep scanning).
- Distroless language images still bundle their interpreter (Node/CPython/JRE), so re-scan after
  migrating to confirm — and quantify — the improvement.
- ECR login tokens are valid ~12h; the push script re-logs in each run.

## Files

```
image-scan/
├── SKILL.md              # workflow Claude follows
├── README.md             # this file
├── references/
│   └── distroless.md     # base-image table + multi-stage Dockerfile patterns + caveats
└── scripts/
    ├── scan.sh           # Trivy image scan -> trivy.json + findings.json + report
    └── push-ecr.sh       # create repo, login, tag, push to ECR (+ optional scan-on-push)
```
