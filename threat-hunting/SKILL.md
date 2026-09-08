---
name: threat-hunting
description: Threat-hunt across three surfaces — search public threat intelligence for indicators (abuse.ch ThreatFox), hunt vulnerable AND malicious dependencies used in a codebase (OSV-Scanner + GuardDog), and inspect logs for Indicators of Compromise (iocextract + grep) — then optionally create Jira tickets in the VM project. Use when the user asks to threat hunt, check dependencies for malicious/typosquatted packages, look up an IP/domain/hash reputation, search threat intel, or scan logs for IoCs.
---

# Threat Hunting (packages · intel · logs) + Jira

Hunt threats across three surfaces and (on confirmation) raise Jira tickets in the **VM**
project:
- **Packages** — vulnerable *and* malicious dependencies in a codebase ([OSV-Scanner](https://github.com/google/osv-scanner) + [GuardDog](https://github.com/DataDog/guarddog)).
- **Intel** — look up indicators against public threat intelligence ([abuse.ch ThreatFox](https://threatfox.abuse.ch)).
- **Logs** — match Indicators of Compromise against logs ([iocextract](https://github.com/InQuest/iocextract) + grep).

## Parallelize with subagents

Fan out subagents (launch several in ONE message) for independent work, then aggregate:
- one subagent per surface (packages / intel / logs) to run and triage in parallel;
- for a large dependency set, one subagent per ecosystem or per flagged package to confirm
  maliciousness and draft ticket content;
- one subagent per matched IoC to enrich it via intel and assess blast radius.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicates.

## Step 1 — Ask what to hunt, then verify preconditions

Ask the user which surface(s) to hunt and for the inputs: a **code/project path** (packages), a
**logs path** plus an **IoC/feed source** (logs), and/or **indicators** to look up (intel).
Verify: Docker running (`docker info`) and `jq`; for intel, a free abuse.ch key in
`$ABUSECH_KEY` (from https://auth.abuse.ch/).

## Step 2 — Hunt malicious/vulnerable packages

```bash
bash "<this-skill-dir>/scripts/hunt-packages.sh" [-e pypi|npm] <project-dir>
```

- **OSV-Scanner** finds known-vulnerable deps and, importantly, **malicious packages** —
  OpenSSF `MAL-` advisories (typosquats, hijacks) surface alongside CVEs and are called out
  separately in the report.
- `-e pypi|npm` also runs **GuardDog** (heuristic malware detection) against `requirements.txt`
  / `package.json` — it downloads and analyzes each referenced package (network required).
- Output to `~/threat-hunting/<name>_PACKAGES_<datetime>/`: `osv.json`, `osv-findings.json`
  (ticket-ready, with a `malicious` flag), `guarddog.json` (if `-e`), `packages-report.md`.

**Malicious packages are urgent** — flag them first and recommend immediate removal/replacement.

## Step 3 — Search public threat intelligence

```bash
export ABUSECH_KEY=...   # free key from https://auth.abuse.ch/
bash "<this-skill-dir>/scripts/intel-lookup.sh" <ioc>          # one IP/domain/URL/hash
bash "<this-skill-dir>/scripts/intel-lookup.sh" -f iocs.txt    # a list
```

Queries **ThreatFox** and prints, per indicator, whether it matched and — if so — the threat
type, associated malware, confidence, and first-seen date. Use it to triage indicators found in
Step 4, or to check dependencies/hosts you're suspicious of. Other sources (VirusTotal, OTX,
GreyNoise) need their own free API keys — note that to the user if broader coverage is wanted.

## Step 4 — Inspect logs for IoCs

```bash
bash "<this-skill-dir>/scripts/hunt-logs.sh" -i <ioc-source> <logs-path>
```

`-i` is a threat report / feed / IoC list; `iocextract` pulls IPs, URLs, domains, hashes, and
emails from it (**refanging** defanged forms like `hxxp://` and `1[.]2[.]3[.]4`), then the
extracted IoCs are matched against the logs with fixed-string grep. Output to
`~/threat-hunting/logs_<datetime>/`: `iocs.txt`, `hits.txt` (matching log lines, file:line),
`matched-iocs.txt` (which indicators hit, by count), `log-hunt-report.md`.

Enrich any matched IoC with Step 3 before concluding, and treat matches as leads to confirm, not
proof on their own.

## Step 5 — Create Jira tickets in the VM project

**Always confirm before creating tickets.** Recommend granularity: **one ticket per malicious
package** (urgent), **one per confirmed IoC/incident lead**, or a **summary ticket**. Drive
tickets from `osv-findings.json` / `matched-iocs.txt`. Use the Atlassian MCP flow
(`getAccessibleAtlassianResources` → `getVisibleJiraProjects` → `getJiraProjectIssueTypesMetadata`
→ `getJiraIssueTypeMetaWithFields` → `createJiraIssue`, `projectKey: VM`) or the REST API
fallback (`POST $JIRA_BASE_URL/rest/api/3/issue`, ADF description).

## Step 6 — Wrap up

Report per surface: malicious/vulnerable package counts, intel hits, and log IoC matches;
report directories; and any Jira ticket keys with links. Lead with anything malicious or
confirmed-active.
