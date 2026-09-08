---
name: amass-recon
description: Run external perimeter reconnaissance / attack-surface enumeration with OWASP Amass (official Docker image) to discover subdomains and assets for a target domain, produce a report of discovered subdomains (with resolved IPs), and optionally create Jira tickets in the VM project. Use when the user asks to enumerate subdomains, map an attack surface, run amass, do perimeter recon, or discover DNS assets for a domain.
---

# Amass Perimeter Recon + Jira

Enumerate the external attack surface of a domain with [OWASP Amass](https://github.com/owasp-amass/amass)
run from its official Docker image, and (on confirmation) create tickets in the Jira **VM** project.

> **Authorization first.** Only scan domains the user owns or is explicitly authorized to test.
> Passive mode (the default) queries third-party data sources and resolves names; **active mode
> touches the target directly** (zone transfers, cert grabs, brute force). Confirm authorization
> before using active mode.

## Parallelize with subagents

When scanning **several domains**, fan out subagents (launch several in ONE message) — one per
target domain (or netblock) — to enumerate and do follow-up analysis in parallel, then merge the
subdomain inventories into one report.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicates.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user before scanning** (AskUserQuestion or a direct question):
   - The **target domain(s)** (comma-separated for several).
   - **Passive or active?** Default to passive (safe, no direct probing). Only use active if the
     user confirms they are authorized to actively probe the target.
   - Confirm they have authorization to scan the target.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`.

## Step 2 — Run the recon

Run the bundled script — it pulls the **latest** official Amass image, runs `amass enum`,
then extracts the discovered names with `amass subs`, and builds a markdown report. Invoke it
by full path (your cwd is not this skill's folder):

```bash
bash "<this-skill-dir>/scripts/recon.sh" [-a] [-t <minutes>] example.com
```

- `-a` = active mode (`-active -brute`) — only with authorization.
- `-t` = enum timeout in minutes (default 30).
- Reports go to `~/amass-recon/<domain>_REPORT_<datetime>/` (created automatically):
  `subdomains.txt`, `subdomains_with_ips.txt`, `amass-report.md`, and the `asset.db` graph.

Env override: `AMASS_IMAGE=<image:tag>` (default `owaspamass/amass:latest`).

Or run manually with Docker (Amass is a two-step flow — enum writes a graph DB, `subs`
extracts names). The image runs as a **non-root** user, so the mounted output dir must be
writable by it (`chmod 777` the host dir):

```bash
docker pull owaspamass/amass:latest
mkdir -p out && chmod 777 out
# 1) enumerate (passive by default; add -active -brute for active mode)
docker run --rm -v "$PWD/out:/data" owaspamass/amass:latest \
  enum -d example.com -timeout 30 -dir /data
# 2) extract discovered names
docker run --rm -v "$PWD/out:/data" owaspamass/amass:latest \
  subs -names -d example.com -dir /data -o /data/subdomains.txt
```

Notes:
- **Passive is the default** in Amass v4/v5; `-active`/`-brute` opt into direct probing.
- Amass works with **zero config**, but adding data-source API keys (via a mounted
  `config.yaml` + `datasources.yaml`, passed with `-config`) substantially improves coverage.
- v5 removed `amass intel` and `amass db`; use `amass subs` to read results back out.

## Step 3 — Present the findings

Show the user:
- The subdomain count and the list from `subdomains.txt`.
- The name→IP mapping from `subdomains_with_ips.txt` (useful for spotting live hosts and
  netblocks worth follow-up).
- Point them at `amass-report.md` for the full writeup.

Flag anything notable for follow-up: subdomains pointing at third-party services (candidates
for takeover review), dev/staging hosts exposed externally, and unexpected netblocks.

## Step 4 — Create Jira tickets in the VM project

**Always confirm with the user before creating tickets**, and ask which granularity:
- **One summary ticket** with the full subdomain inventory (recommended for recon output), or
- **One ticket per notable finding** (e.g. a specific exposed/takeover-candidate host).

### Preferred: Atlassian MCP tools

1. `getAccessibleAtlassianResources` → `cloudId`.
2. `getVisibleJiraProjects` → confirm the **VM** project key.
3. `getJiraProjectIssueTypesMetadata` for VM → pick issue type (default **Task**; **Bug** for a
   specific vulnerability).
4. `getJiraIssueTypeMetaWithFields` → discover required fields; fill them or ask the user.
5. `createJiraIssue`:
   - `cloudId`, `projectKey: VM`, `issueTypeName` from above
   - `summary`: `Perimeter recon: <domain> — <N> subdomains discovered`
   - `description`: target(s), scan mode, date, the subdomain inventory (with IPs), and any
     flagged follow-ups, plus the report path on disk.

### Fallback: Jira REST API

`POST $JIRA_BASE_URL/rest/api/3/issue` with `JIRA_EMAIL`/`JIRA_API_TOKEN` basic auth, ADF
description, project key `VM`.

## Step 5 — Wrap up

Report: domain(s) scanned, mode, subdomain count, report directory, and any Jira ticket keys
with links. Recon output maps an attack surface — remind the user to handle it accordingly.
