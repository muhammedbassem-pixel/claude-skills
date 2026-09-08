# iac-scan

A Claude Code skill that scans **Infrastructure-as-Code and Kubernetes manifests** for security
misconfigurations against best practices — Terraform, CloudFormation, ARM/Bicep, Dockerfile,
Serverless, and Kubernetes/Helm/kustomize — and files findings in the Jira **VM** project.

> **Related:** `k8s-config-scan` is the Kubernetes-specialized skill (kube-linter/kubescape +
> live-cluster kube-bench/KubeHound). `iac-scan` is the broad **multi-IaC** scanner.

## What it does

1. **Asks for the IaC path** and verifies Docker + jq.
2. Runs **Checkov** (`bridgecrew/checkov`) across all detected IaC frameworks (built-in policies,
   no account/network) and **Trivy config** (`aquasec/trivy`) as a fast second opinion.
3. Writes `checkov.json`, `trivy-config.json`, a normalized ticket-ready `findings.json`, and
   `iac-report.md` to `~/iac-scan/<name>_REPORT_<datetime>/`.
4. Triages by severity, then — on your confirmation — files Jira tickets in the **VM** project
   (Atlassian MCP or REST fallback).

## Coverage

| IaC type | Checkov | Trivy config |
|----------|---------|--------------|
| Terraform / terraform_plan | ✅ | ✅ |
| CloudFormation | ✅ | ✅ |
| ARM | ✅ | ✅ |
| Bicep | ✅ | — |
| Dockerfile | ✅ | ✅ |
| Serverless | ✅ | — |
| Kubernetes / Helm / kustomize | ✅ | ✅ (K8s/Helm) |

Checkov findings carry `CKV_*` IDs + a guideline URL; Trivy uses `AVD-*` IDs. Union the two.

## Installation

```bash
ln -sfn "$(pwd)/iac-scan" ~/.claude/skills/iac-scan      # personal
```

### Requirements

- Docker running; `jq`
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "scan our Terraform for misconfigurations"
- "run Checkov on this repo's IaC"
- "check these CloudFormation and Dockerfile for security issues"

### Running the scanner directly

```bash
bash iac-scan/scripts/scan.sh [-f terraform|cloudformation|arm|bicep|dockerfile|serverless|kubernetes|helm] [-s HIGH,CRITICAL] <iac-dir>
```

| Option / env | Purpose |
|--------------|---------|
| `-f <framework>` | Restrict Checkov to one framework (default: all, auto-detected) |
| `-s <sev>` | Trivy severities (default `HIGH,CRITICAL`) |
| `CHECKOV_IMAGE` / `TRIVY_IMAGE` | Pin scanner image/tag |

## Notes

- Checkov auto-detects frameworks and scans them all in one pass; add
  `--download-external-modules` (edit the script) to resolve remote Terraform modules.
- Checkov covers Bicep and Serverless (Trivy config does not); no Ansible framework in Checkov.
- Findings are built-in-policy only — no account or network needed for the bundled checks.

## Files

```
iac-scan/
├── SKILL.md              # workflow Claude follows
├── README.md             # this file
├── references/
│   └── coverage.md       # framework coverage + IaC best-practice categories
└── scripts/
    └── scan.sh           # Checkov (all frameworks) + Trivy config -> findings.json + report
```
