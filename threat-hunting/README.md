# threat-hunting

A Claude Code skill that hunts threats across three surfaces — **public threat intel**,
**dependency/supply-chain**, and **logs** — and files findings in the Jira **VM** project.

## What it does

1. **Packages** — [OSV-Scanner](https://github.com/google/osv-scanner) finds known-vulnerable
   deps **and malicious packages** (OpenSSF `MAL-` advisories); [GuardDog](https://github.com/DataDog/guarddog)
   adds heuristic malware detection for PyPI/npm.
2. **Intel** — looks up IPs/domains/URLs/hashes against [abuse.ch ThreatFox](https://threatfox.abuse.ch)
   (free Auth-Key).
3. **Logs** — extracts IoCs from a feed/report with [iocextract](https://github.com/InQuest/iocextract)
   (refanging defanged indicators) and matches them against your logs.
4. Files remediation/incident tickets in the **VM** project (Atlassian MCP or REST fallback).

## Installation

```bash
ln -sfn "$(pwd)/threat-hunting" ~/.claude/skills/threat-hunting      # personal
```

### Requirements

- Docker running; `jq`; `curl`
- For intel lookups: a free abuse.ch Auth-Key in `$ABUSECH_KEY` (https://auth.abuse.ch/)
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "hunt our repo for malicious or vulnerable packages"
- "look up 198.51.100.77 in threat intel"
- "scan these logs for IoCs from this threat report"

### Running the scripts directly

```bash
# malicious + vulnerable dependencies (-e adds GuardDog for pypi/npm)
bash threat-hunting/scripts/hunt-packages.sh [-e pypi|npm] <project-dir>

# threat-intel lookup (abuse.ch ThreatFox) — needs $ABUSECH_KEY
bash threat-hunting/scripts/intel-lookup.sh <ioc>            # or: -f iocs.txt

# inspect logs for IoCs pulled from a report/feed
bash threat-hunting/scripts/hunt-logs.sh -i <ioc-source> <logs-path>
```

## Notes

- **Malicious packages (`MAL-`) are urgent** — `hunt-packages.sh` calls them out separately from
  ordinary CVEs. Recommend immediate removal/replacement.
- Public feeds are free but key-gated (abuse.ch/OTX/VT/GreyNoise); see `references/sources.md`.
- Log matches are **leads to confirm**, not proof — enrich matched IoCs via the intel lookup.

## Files

```
threat-hunting/
├── SKILL.md                 # workflow Claude follows
├── README.md                # this file
├── references/
│   └── sources.md           # intel sources, key requirements, tooling notes
└── scripts/
    ├── hunt-packages.sh      # OSV-Scanner (+ GuardDog) -> vulnerable & malicious deps
    ├── intel-lookup.sh       # abuse.ch ThreatFox IoC lookup
    └── hunt-logs.sh          # iocextract -> grep logs for IoCs
```
