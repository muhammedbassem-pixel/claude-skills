---
name: iac-scan
description: Scan Infrastructure-as-Code and Kubernetes manifests for security misconfigurations against best practices — Terraform, CloudFormation, ARM/Bicep, Dockerfile, Serverless, and Kubernetes/Helm/kustomize — with Checkov (broad framework coverage) + Trivy config, then optionally create Jira tickets in the VM project. Use when the user asks to scan IaC, Terraform/CloudFormation/ARM/Bicep, a Dockerfile, or Kubernetes/Helm manifests for misconfigurations, run Checkov, or check infra config against best practice/CIS.
---

# IaC & Kubernetes Manifest Scan + Jira

Scan Infrastructure-as-Code and Kubernetes manifests for security misconfigurations with
[Checkov](https://www.checkov.io) (broad framework coverage — Terraform, CloudFormation,
ARM/Bicep, Dockerfile, Serverless, Kubernetes, Helm, kustomize) and [Trivy config](https://trivy.dev)
as a fast second opinion — and (on confirmation) raise Jira tickets in the **VM** project.

> **Related skill:** for a *Kubernetes-specialized* scan (kube-linter/kubescape framework
> mapping) or a **live-cluster** hunt (kube-bench CIS + KubeHound attack paths), use
> `k8s-config-scan`. This skill is the broad **multi-IaC** scanner (Terraform/CFN/ARM/Bicep/
> Dockerfile/Serverless + K8s/Helm from files).

## Parallelize with subagents

Fan out subagents (launch several in ONE message) for independent work, then aggregate:
- one subagent per **IaC type / stack directory** (terraform/, cloudformation/, k8s/, …) to scan
  and triage in parallel;
- one subagent per severity tier (or per resource) to confirm the misconfiguration and draft the
  remediation-ticket content.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicates.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user for the IaC path on disk** (AskUserQuestion or a direct question) — do not
   assume the cwd. Optionally ask whether to restrict to one framework (e.g. `terraform`) and the
   severity focus.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`.

## Step 2 — Run the scan

Run the bundled script — it runs Checkov across all detected IaC frameworks (built-in policies,
no account/network) and Trivy config as a second opinion, then normalizes both into a
ticket-ready `findings.json`. Invoke by full path:

```bash
bash "<this-skill-dir>/scripts/scan.sh" [-f terraform|cloudformation|arm|bicep|dockerfile|serverless|kubernetes|helm] [-s HIGH,CRITICAL] <iac-dir>
```

Output goes to `~/iac-scan/<name>_REPORT_<datetime>/`: `checkov.json`, `trivy-config.json`, a
normalized `findings.json` (tool, check id, severity, resource, file:line, guideline), and
`iac-report.md`.

Env overrides: `CHECKOV_IMAGE`, `TRIVY_IMAGE`.

Or run manually:

```bash
docker run --rm -v "$PWD:/iac:ro" bridgecrew/checkov -d /iac -o json --compact --quiet --soft-fail
docker run --rm -v "$PWD:/iac:ro" aquasec/trivy:latest config /iac --severity HIGH,CRITICAL --format json
```

Notes:
- Checkov auto-detects frameworks when `-f` is omitted and scans them all in one pass; findings
  carry stable `CKV_*` IDs and a `guideline` remediation URL.
- For **Terraform modules**, add `--download-external-modules` to resolve external module sources
  (needs network) — otherwise remote modules aren't evaluated.
- Checkov covers **Bicep and Serverless** (Trivy config does not); Trivy config is a fast second
  pass with `AVD-*` IDs. Union the two.
- Checkov has no Ansible framework — if Ansible is in scope, note it (Trivy/other tools cover it).

## Step 3 — Triage and present

Show the `iac-report.md` table and the CRITICAL/HIGH counts. Confirm true positives by reading
the flagged resource (`file:line`). Prioritize: public exposure (open security groups, public
buckets), missing encryption, over-permissive IAM, disabled logging, and container/Dockerfile
issues (root user, unpinned base images). De-duplicate where Checkov and Trivy flag the same
resource.

## Step 4 — Create Jira tickets in the VM project

**Always confirm before creating tickets.** Ask granularity: **one ticket per
misconfiguration** (recommended for High/Critical) or a **summary ticket**. Drive tickets from
`findings.json` (each carries tool, check id, severity, resource, file:line, guideline). Use the
Atlassian MCP flow (`getAccessibleAtlassianResources` → `getVisibleJiraProjects` →
`getJiraProjectIssueTypesMetadata` → `getJiraIssueTypeMetaWithFields` → `createJiraIssue`,
`projectKey: VM`) or the REST API fallback (`POST $JIRA_BASE_URL/rest/api/3/issue`, ADF
description).

## Step 5 — Wrap up

Report: what was scanned, finding counts by tool and severity, report directory, and any Jira
ticket keys with links. Recommend wiring the scan into CI (pre-merge) to catch misconfigurations
before apply/deploy.
