---
name: dns-takeover-scan
description: Scan a domain or list of subdomains for subdomain-takeover vulnerabilities using dnsReaper (passive fingerprinting) and optionally nuclei takeover templates (active), both via official Docker images, produce a findings report, and optionally create Jira tickets in the VM project. Use when the user asks to check for subdomain takeover, scan DNS for dangling records, run dnsReaper or nuclei takeover checks, or assess dangling CNAME/NS risk.
---

# Subdomain Takeover Scan (dnsReaper + nuclei) + Jira

Check a domain or a list of subdomains for **subdomain-takeover** risk — dangling DNS records
pointing at unclaimed third-party services — using [dnsReaper](https://github.com/punk-security/dnsReaper)
for passive fingerprinting and, optionally, [nuclei](https://github.com/projectdiscovery/nuclei)
takeover templates for active confirmation. On confirmation, file tickets in the Jira **VM** project.

> **Authorization first.** Only scan domains the user owns or is authorized to test. dnsReaper's
> fingerprinting is largely passive (DNS + service checks); **nuclei actively sends HTTP requests
> to the targets** — only enable it (`-n`) with authorization.

This pairs well with `amass-recon`: feed its `subdomains.txt` in as the target list.

## Parallelize with subagents

Fan out subagents (launch several in ONE message) for independent work, then aggregate:
- split a **large domain list** into chunks, one subagent per chunk to scan and triage;
- one subagent per confirmed takeover to gather evidence (the dangling record, the claimable
  service) and draft the ticket content.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicate takeover tickets.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user before scanning**:
   - The **target**: a single domain, a comma-separated list, or a path to a file of subdomains
     (e.g. the `subdomains.txt` from an amass recon run).
   - **Passive only, or also active (nuclei)?** Default to dnsReaper-only (passive). Enable
     nuclei (`-n`) only if the user confirms authorization for active probing.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`.

## Step 2 — Run the scan

Run the bundled script — it normalizes the target into a domains file, pulls the **latest**
dnsReaper image and runs passive fingerprinting, and (with `-n`) pulls nuclei and runs its
takeover templates. Invoke by full path:

```bash
bash "<this-skill-dir>/scripts/scan.sh" [-n] <domains-file | domain[,domain2,...]>
```

- `-n` = also run nuclei takeover templates (active) — authorization required.
- Reports go to `~/dns-takeover/<label>_REPORT_<datetime>/`: `domains.txt`,
  `dnsreaper-results.json`, `nuclei-results.jsonl` (if `-n`), and `takeover-report.md`.

Env overrides: `DNSREAPER_IMAGE` (default `punksecurity/dnsreaper:latest`),
`NUCLEI_IMAGE` (default `projectdiscovery/nuclei:latest`).

Or run manually:

```bash
# dnsReaper — passive, zero-config; container workdir is /etc/dnsreaper
docker pull punksecurity/dnsreaper:latest
docker run --rm -v "$PWD:/etc/dnsreaper" punksecurity/dnsreaper \
  file --filename /etc/dnsreaper/domains.txt \
  --out /etc/dnsreaper/dnsreaper-results --out-format json

# nuclei — active takeover templates; cache templates in a named volume
docker pull projectdiscovery/nuclei:latest
docker run --rm -v nuclei-templates:/root/nuclei-templates -v "$PWD:/app" \
  projectdiscovery/nuclei -l /app/domains.txt -tags takeover -jsonl -o /app/nuclei-results.jsonl
```

Notes:
- dnsReaper providers are **positional subcommands** (`single --domain`, `file --filename`),
  not a `--provider` flag. `single`/`file` need no credentials.
- dnsReaper confidence is `CONFIRMED` / `POTENTIAL` / `UNLIKELY` — prioritize CONFIRMED.
- nuclei auto-downloads templates on first run; the named volume caches them between runs.
- nuclei's takeover set uses `-tags takeover` (templates live under `http/takeovers/`).

## Step 3 — Present the findings

Show the user the `takeover-report.md` tables:
- **dnsReaper**: domain, matched service signature (e.g. `aws_s3`, `azure_traffic_manager`),
  confidence, and the more-info URL. Lead with CONFIRMED findings.
- **nuclei** (if run): template id, severity, host.

For each takeover candidate, explain the risk (an attacker could claim the dangling resource
and serve content on the subdomain) and the fix (remove the dangling DNS record or reclaim the
resource). Note false positives are possible — CONFIRMED/high-severity should be verified.

## Step 4 — Create Jira tickets in the VM project

**Always confirm with the user before creating tickets**, and ask which granularity:
- **One ticket per confirmed takeover** (recommended), or
- **One summary ticket** with the findings table.

### Preferred: Atlassian MCP tools

1. `getAccessibleAtlassianResources` → `cloudId`.
2. `getVisibleJiraProjects` → confirm the **VM** project key.
3. `getJiraProjectIssueTypesMetadata` for VM → pick issue type (default **Bug**).
4. `getJiraIssueTypeMetaWithFields` → discover required fields; fill them or ask the user.
5. `createJiraIssue`:
   - `cloudId`, `projectKey: VM`, `issueTypeName` from above
   - `summary`: `Subdomain takeover: <domain> (<service>)`
   - `description`: vulnerable domain, matched service/template, confidence/severity, the
     dangling record type (CNAME/NS/A), remediation (remove record or reclaim resource), and
     the report path on disk.

### Fallback: Jira REST API

`POST $JIRA_BASE_URL/rest/api/3/issue` with `JIRA_EMAIL`/`JIRA_API_TOKEN` basic auth, ADF
description, project key `VM`.

## Step 5 — Wrap up

Report: targets scanned, tools run (passive / active), finding counts, report directory, and
any Jira ticket keys with links.
