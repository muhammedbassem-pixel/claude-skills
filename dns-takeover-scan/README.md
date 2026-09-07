# dns-takeover-scan

A Claude Code skill that scans a domain or list of subdomains for **subdomain-takeover**
vulnerabilities using [dnsReaper](https://github.com/punk-security/dnsReaper) (passive
fingerprinting) and optionally [nuclei](https://github.com/projectdiscovery/nuclei) takeover
templates (active), both via official Docker images — and can file findings in the Jira **VM**
project.

> **Authorization required.** dnsReaper fingerprinting is largely passive; nuclei actively
> probes targets. Only scan domains you own or are authorized to test.

## What it does

1. **Asks for scope first**: a domain, a comma-separated list, or a subdomains file (e.g. from
   the `amass-recon` skill). Asks passive-only vs. also-active (nuclei).
2. Pulls the **latest** dnsReaper image (`punksecurity/dnsreaper:latest`) and runs passive
   takeover fingerprinting (zero-config); with `-n`, also pulls nuclei
   (`projectdiscovery/nuclei:latest`) and runs its `takeover`-tagged templates.
3. Writes `domains.txt`, `dnsreaper-results.json`, `nuclei-results.jsonl` (if active), and a
   markdown report to `~/dns-takeover/<label>_REPORT_<datetime>/`.
4. On your confirmation, files Jira tickets in the **VM** project (Atlassian MCP, or REST
   fallback) — one per confirmed takeover or a summary ticket.

## Installation

```bash
ln -s "$(pwd)/dns-takeover-scan" ~/.claude/skills/dns-takeover-scan      # personal
```

### Requirements

- Docker running
- `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "check example.com for subdomain takeover"
- "run dnsReaper on this subdomains.txt and file tickets for confirmed takeovers"
- "scan these hosts for dangling DNS with dnsReaper and nuclei"

### Running the scanner directly

```bash
bash dns-takeover-scan/scripts/scan.sh [-n] [-o output-dir] <domains-file | domain[,domain2,...]>
```

| Option / env | Default | Purpose |
|--------------|---------|---------|
| `-n` | off | Also run nuclei takeover templates (**active** — authorization required) |
| `-o <dir>` | `~/dns-takeover/<label>_REPORT_<datetime>` | Output directory |
| `DNSREAPER_IMAGE` | `punksecurity/dnsreaper:latest` | Pin dnsReaper image/tag |
| `NUCLEI_IMAGE` | `projectdiscovery/nuclei:latest` | Pin nuclei image/tag |

## Notes

- dnsReaper `single`/`file` providers are zero-config (no API keys) for scanning a given list.
- dnsReaper confidence levels: `CONFIRMED` / `POTENTIAL` / `UNLIKELY` — prioritize CONFIRMED.
- nuclei caches templates in a named Docker volume (`nuclei-templates`) between runs.
- Pairs with `amass-recon`: pass its `subdomains.txt` as the target file.

## Files

```
dns-takeover-scan/
├── SKILL.md          # skill definition + workflow Claude follows
├── README.md         # this file
└── scripts/
    └── scan.sh       # normalize targets -> dnsReaper (+ nuclei) -> markdown report
```
