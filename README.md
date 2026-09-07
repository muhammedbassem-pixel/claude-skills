# claude-skills

A collection of security-focused [Claude Code](https://claude.com/claude-code) skills. Each
skill runs its tooling from an official Docker image, prompts for scope before scanning, writes
timestamped reports under your home directory, and can file findings as Jira tickets in the
**VM** project.

## Skills

| Skill | What it does | Tool (Docker image) |
|-------|--------------|---------------------|
| [`gitleaks-audit`](gitleaks-audit/) | Full-history secret scan across all branches/commits, unredacted report | gitleaks (`ghcr.io/gitleaks/gitleaks`) |
| [`aws-security-audit`](aws-security-audit/) | AWS security posture audit across all/specific regions | Prowler (`prowlercloud/prowler`) |
| [`amass-recon`](amass-recon/) | External perimeter recon / subdomain enumeration | OWASP Amass (`owaspamass/amass`) |
| [`dns-takeover-scan`](dns-takeover-scan/) | Subdomain-takeover detection (pairs with amass output) | dnsReaper + nuclei |
| [`secure-code-review`](secure-code-review/) | Multi-language SAST mapped to OWASP Top 10 + CWE/SANS Top 25 | Semgrep (`semgrep/semgrep`) + `dart analyze` |
| [`threat-modeling`](threat-modeling/) | STRIDE threat modeling: scope, DFD, trust boundaries, threat/risk registers | OWASP Threat Dragon (`owasp/threat-dragon`) |

Each skill has its own `README.md` with detailed usage and options.

## What is a skill?

A Claude Code skill is a folder containing a `SKILL.md` (a workflow Claude follows, with
YAML frontmatter describing when to use it) plus any supporting scripts and references. When
you ask Claude something matching a skill's description, it loads that skill and follows its
steps. See the [skills documentation](https://docs.claude.com/en/docs/claude-code/skills).

## Installation

Skills are discovered from two locations. Symlink (or copy) the skill folders into one:

- **Personal** — available in every project: `~/.claude/skills/`
- **Project** — shared with a repo via git: `<project>/.claude/skills/`

### Install all skills (personal)

```bash
git clone https://github.com/muhammedbassem-pixel/claude-skills.git
cd claude-skills
mkdir -p ~/.claude/skills
for skill in */; do
  ln -sfn "$(pwd)/${skill%/}" ~/.claude/skills/"${skill%/}"
done
```

Symlinks mean a `git pull` in this repo updates the installed skills automatically.

### Install a single skill

```bash
ln -sfn "$(pwd)/gitleaks-audit" ~/.claude/skills/gitleaks-audit
```

### Install into a project instead

```bash
mkdir -p /path/to/project/.claude/skills
ln -sfn "$(pwd)/secure-code-review" /path/to/project/.claude/skills/secure-code-review
```

### Verify

Start Claude Code and run `/skills` (or `/help`) to confirm the skills are listed. You can also
just ask, e.g. *"scan this repo for secrets"* or *"audit my AWS account"*, and Claude will pick
up the matching skill.

## Requirements

All skills need:

- **Docker** running (each skill pulls the latest official image at runtime)
- **`jq`**

Additionally, per skill:

- `aws-security-audit` — AWS CLI v2 + credentials with `SecurityAudit` and
  `job-function/ViewOnlyAccess` policies
- `secure-code-review` — no extra tools (Flutter reviews also use the `dart` image)
- `threat-modeling` — `openssl` (to generate Threat Dragon local-session keys)

**Jira ticket creation** (optional, all skills) needs either the Atlassian (Rovo) MCP
connector enabled in Claude, or these env vars for the REST fallback:

```bash
export JIRA_BASE_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="you@example.com"
export JIRA_API_TOKEN="…"   # https://id.atlassian.com/manage-profile/security/api-tokens
```

## Reports & safety

- Reports are written outside any scanned repo (under `~/gitleaks/`, `~/aws-audit/`,
  `~/amass-recon/`, `~/dns-takeover/`, `~/code-review/`) so unredacted secrets and findings
  can't be committed by accident. Treat them like credentials — don't commit or share them.
- The recon/scanning skills (`amass-recon`, `dns-takeover-scan`) probe external targets. Only
  scan domains and accounts you own or are explicitly authorized to test. Passive modes are the
  default; active modes require confirmation.
- All skills confirm with you before creating Jira tickets.
