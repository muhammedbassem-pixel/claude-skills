# threat-modeling

A Claude Code skill that facilitates **STRIDE threat modeling** following the
CyberDefense-ThreatModeling framework — scoping a system, building a data-flow diagram with
trust boundaries, running STRIDE analysis, producing the full artifact set (Mermaid diagrams +
OWASP Threat Dragon model + threat/risk registers), and filing High/Critical remediation items
in the Jira **VM** project.

## What it does

1. **Scopes the system** with you: business context, architecture, security controls, owners,
   in/out of scope.
2. **Scaffolds** the standard artifact set (`README.md`, `architecture.mmd`, `data-flow.mmd`,
   `threat-dragon.json`, `threat-model.md`, `threat-register.md`, `risks.md`) from templates.
3. Helps you **build the Mermaid diagrams** and **launch OWASP Threat Dragon locally** (Docker)
   for the collaborative DFD + STRIDE session.
4. Guides **STRIDE analysis** across every entity/process/store/flow and completes the threat &
   risk registers with a likelihood × impact rating.
5. On your confirmation, files **Jira tickets** in the **VM** project for High/Critical threats
   (Atlassian MCP connector, or REST API fallback).

## Methodology

Condensed in `references/methodology.md` (STRIDE, risk-rating matrix, trust zones, Definition of
Done). The Threat Dragon model format is documented in `references/threat-dragon-schema.md` so
the model can be edited in the app or authored by hand. Full org standards, guides, and real
example models live in the companion `CyberDefense-ThreatModeling/` repo.

## Installation

```bash
ln -sfn "$(pwd)/threat-modeling" ~/.claude/skills/threat-modeling      # personal
```

### Requirements

- Docker running (to launch Threat Dragon)
- `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "threat model the payments service"
- "run a STRIDE analysis on this architecture"
- "create a threat model for our new API and file tickets for high risks"

### Using the scaffold script directly

```bash
# create applications/<app-name>/ (default base 'applications') from templates
bash threat-modeling/scripts/scaffold.sh <app-name> [target-dir]

# launch OWASP Threat Dragon at http://localhost:3000 (use "Local session" — no OAuth)
bash threat-modeling/scripts/scaffold.sh --serve
```

Env override: `THREAT_DRAGON_IMAGE` (default `owasp/threat-dragon:stable`, or `:v2.6.2-arm64` on Apple Silicon).

## Files

```
threat-modeling/
├── SKILL.md                            # workflow Claude follows
├── README.md                           # this file
├── references/
│   ├── methodology.md                  # STRIDE process, risk rating, trust zones, DoD
│   └── threat-dragon-schema.md         # Threat Dragon v2.6.2 model format
├── templates/
│   ├── architecture.mmd  data-flow.mmd
│   ├── threat-model.md  threat-register.md  risks.md  README.md
│   └── threat-dragon.json              # minimal valid empty STRIDE model
└── scripts/
    └── scaffold.sh                     # scaffold artifacts / launch Threat Dragon
```
