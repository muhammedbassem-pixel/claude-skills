# amass-recon

A Claude Code skill that performs external perimeter reconnaissance / attack-surface
enumeration with [OWASP Amass](https://github.com/owasp-amass/amass) — discovering
subdomains and assets for a target domain — and can file findings in the Jira **VM** project.

> **Authorization required.** Only scan domains you own or are explicitly authorized to test.
> Passive mode is the default; active mode probes the target directly.

## What it does

1. **Asks for scope first**: target domain(s), passive vs. active, and confirms authorization.
2. Pulls the **latest** official Amass Docker image (`owaspamass/amass:latest`) and runs
   `amass enum`, then extracts discovered names with `amass subs`.
3. Writes reports to `~/amass-recon/<domain>_REPORT_<datetime>/` — `subdomains.txt`,
   `subdomains_with_ips.txt`, a markdown report, and the `asset.db` graph.
4. On your confirmation, creates a Jira ticket in the **VM** project (Atlassian MCP connector,
   or REST API fallback) — a summary inventory or per-finding tickets.

## Installation

```bash
ln -s "$(pwd)/amass-recon" ~/.claude/skills/amass-recon      # personal
# or: ln -s "$(pwd)/amass-recon" <project>/.claude/skills/amass-recon
```

### Requirements

- Docker running
- `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "enumerate subdomains of example.com"
- "map the attack surface for acme.com and file a ticket"
- "run amass recon on these domains (passive only)"

### Running the scanner directly

```bash
bash amass-recon/scripts/recon.sh [-a] [-t minutes] [-o output-dir] <domain[,domain2,...]>
```

| Option / env | Default | Purpose |
|--------------|---------|---------|
| `-a` | off | Active mode (`-active -brute`) — **authorization required** |
| `-t <minutes>` | `30` | Enum timeout |
| `-o <dir>` | `~/amass-recon/<domain>_REPORT_<datetime>` | Output directory |
| `AMASS_IMAGE` | `owaspamass/amass:latest` | Pin a specific image/tag |

## Notes

- Passive is the default in Amass v4/v5; active/brute opts into direct probing of the target.
- Amass runs with zero config, but mounting a `config.yaml` + `datasources.yaml` with data-source
  API keys (via `-config`) greatly improves coverage.
- The container runs as a non-root user, so the script `chmod 777`s the output dir so results
  can be written to the mount.

## Files

```
amass-recon/
├── SKILL.md          # skill definition + workflow Claude follows
├── README.md         # this file
└── scripts/
    └── recon.sh      # pull image → amass enum → amass subs → markdown report
```
