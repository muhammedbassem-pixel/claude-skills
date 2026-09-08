---
name: image-scan
description: Scan a Docker/container image for vulnerabilities, secrets, and misconfigurations with Trivy (official Docker image), then recommend and generate a migration to a hardened distroless base image, optionally build and push the hardened image to Amazon ECR, and create Jira tickets in the VM project. Use when the user asks to scan a container/Docker image, check an image for CVEs, harden a Dockerfile, move to a distroless base, or push an image to ECR.
---

# Container Image Scan → Distroless → ECR + Jira

Scan a container image with [Trivy](https://trivy.dev), report its vulnerabilities, then help
migrate it to a minimal **distroless** base image to cut the attack surface — optionally
building and pushing the hardened image to **Amazon ECR** — and (on confirmation) file Jira
tickets in the **VM** project.

## Parallelize with subagents

When a scan returns **many CVEs**, fan out subagents (launch several in ONE message) to work
them in parallel, then aggregate:
- one subagent per package (or CVE batch) to assess exploitability/impact and confirm the
  fixed version, and draft the remediation-ticket content.

Do **not** fan out the Jira ticket-creation or the ECR push — a single agent does those after
your confirmation.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user which image to scan** (AskUserQuestion or a direct question): the image
   reference (`name:tag`, local or pullable). Optionally ask the severity focus (default
   `CRITICAL,HIGH`) and whether to only show fixable vulns.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`. For the ECR step also `aws`.

## Step 2 — Scan the image

Run the bundled script — it pulls the **latest** Trivy image and scans for vulnerabilities,
secrets, and misconfigurations, writing a JSON report, a normalized `findings.json`, and a
markdown report. Invoke by full path:

```bash
bash "<this-skill-dir>/scripts/scan.sh" [-s CRITICAL,HIGH] [-u] <image[:tag]>
```

- `-s` severities (default `CRITICAL,HIGH`); `-u` only vulns with a fix available.
- Output goes to `~/image-scan/<image>_REPORT_<datetime>/`: `trivy.json`, `findings.json`
  (ticket-ready: id, package, installed, fixed, severity, title, url), `image-report.md`.

Env override: `TRIVY_IMAGE` (default `aquasec/trivy:latest`).

Or run manually (mount the Docker socket so Trivy reads the local image; cache the vuln DB):

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.cache/trivy:/root/.cache/" \
  aquasec/trivy:latest image \
  --scanners vuln,secret,misconfig --severity CRITICAL,HIGH \
  --format json -o result.json <image:tag>
```

Also scan the **source Dockerfile** for misconfigurations before building:
`docker run --rm -v "$PWD:/src" aquasec/trivy:latest config /src/Dockerfile`.

## Step 3 — Present findings and recommend distroless

Show the user the `image-report.md` table (severity, CVE, package, installed→fixed, title) and
the fixable count. Then **recommend migrating to a distroless base** to remove the shell,
package manager, and OS utilities that carry most of the CVE surface:

1. Read the image's Dockerfile (ask for its path) and identify the language/runtime and whether
   the binary is static.
2. Using `references/distroless.md`, pick the right base
   (`gcr.io/distroless/static|base|cc|java21|nodejs22|python3-debian12`, `:nonroot`) and
   generate a **multi-stage Dockerfile**: full image to build, distroless final stage that
   copies only the artifact, exec-form `ENTRYPOINT`, non-root user, pinned Debian version.
3. Explain the caveats (no shell/pkg manager; use `:debug` to troubleshoot; language images
   still bundle their interpreter, so keep scanning).
4. Offer to build the new image and **re-scan it with Step 2** to prove the CVE reduction
   (before/after counts).

## Step 4 — (Optional) Build and push the hardened image to ECR

On the user's request, build the distroless image and push it to Amazon ECR:

```bash
docker build -t <app>:distroless -f Dockerfile.distroless .
bash "<this-skill-dir>/scripts/push-ecr.sh" [-p <profile>] [-r <region>] [-s] <app>:distroless <ecr-repo>[:tag]
```

The script resolves the account id (`aws sts get-caller-identity`), creates the repo if missing,
logs in (`aws ecr get-login-password | docker login`, token valid ~12h), tags, and pushes to
`<account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>`. `-s` enables scan-on-push (basic
scanning) and prints the ECR finding-severity counts. **Confirm with the user before pushing**
(it publishes an image to a shared registry). The pusher needs ECR permissions
(`GetAuthorizationToken`, `BatchCheckLayerAvailability`, `PutImage`, the layer-upload actions;
`CreateRepository` if the repo is new).

## Step 5 — Create Jira tickets in the VM project

**Always confirm before creating tickets.** Ask which granularity:
- **One ticket to migrate the image to distroless** (bundling the CVE reduction rationale), or
- **One ticket per critical/fixable CVE**, or a **summary ticket**.

Use the Atlassian MCP flow (`getAccessibleAtlassianResources` → `getVisibleJiraProjects` →
`getJiraProjectIssueTypesMetadata` → `getJiraIssueTypeMetaWithFields` → `createJiraIssue`) with
`projectKey: VM`, or the REST API fallback (`POST $JIRA_BASE_URL/rest/api/3/issue` with
`JIRA_EMAIL`/`JIRA_API_TOKEN`, ADF description). Drive per-CVE tickets from `findings.json`
(each carries image, CVE id, package, installed→fixed, severity, title, url).

## Step 6 — Wrap up

Report: image scanned, CVE counts by severity (and before/after if migrated), report directory,
the pushed ECR image reference if any, and any Jira ticket keys with links.
