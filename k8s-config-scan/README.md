# k8s-config-scan

A Claude Code skill that scans **Kubernetes configuration** (manifests / Helm / kustomize)
against security best practices, and hunts issues on a **live cluster** — filing findings in
the Jira **VM** project.

## What it does

1. **Config scan** — pulls **Trivy config** + **kube-linter** (and optional **kubescape** for
   NSA/CIS/MITRE framework mapping), scans a manifests/Helm/kustomize directory, and writes a
   normalized `findings.json` + markdown report to `~/k8s-scan/<name>_REPORT_<datetime>/`.
2. **Live-cluster hunt** — **kube-bench** runs the CIS Kubernetes Benchmark as an in-cluster Job
   and collects JSON; **KubeHound** (`-H`) builds an attack-path graph (JanusGraph + Jupyter)
   for interactive exploration.
3. Files remediation tickets in the **VM** project (Atlassian MCP or REST fallback).

## Tools

| Purpose | Tool |
|---------|------|
| Manifest/Helm/kustomize misconfig | Trivy `config` (`aquasec/trivy`) |
| Best-practice lint (zero-config) | kube-linter (`stackrox/kube-linter`) |
| Framework mapping (NSA/CIS/MITRE) | kubescape (`quay.io/kubescape/kubescape`) |
| CIS Benchmark on a live cluster | kube-bench (`aquasec/kube-bench`) |
| Attack-path graph on a live cluster | KubeHound (`DataDog/KubeHound`) |

## Installation

```bash
ln -sfn "$(pwd)/k8s-config-scan" ~/.claude/skills/k8s-config-scan      # personal
```

### Requirements

- Docker running; `jq`
- For live-cluster hunting: `kubectl` with a context on the target cluster (and, for KubeHound,
  Docker Compose + the `kubehound` binary)
- For Jira tickets: the Atlassian (Rovo) MCP connector, or `JIRA_BASE_URL`, `JIRA_EMAIL`,
  `JIRA_API_TOKEN` env vars

## Usage

In Claude Code, ask e.g.:

- "scan these K8s manifests against best practices"
- "lint our Helm chart for security issues"
- "run the CIS benchmark on the cluster and map attack paths"

### Running the scripts directly

```bash
# config scan (manifests / Helm / kustomize); -f adds a kubescape framework
bash k8s-config-scan/scripts/scan.sh [-f nsa|cis-v1.23-t1.0.1|mitre|allcontrols] <manifests-dir>

# live-cluster hunt: kube-bench (CIS); -H also sets up KubeHound attack-path graph
bash k8s-config-scan/scripts/hunt-cluster.sh [-H]
```

## Notes

- Trivy `config` auto-detects K8s YAML, Helm, and kustomize and maps to AVD/KSV IDs; kube-linter
  is zero-config best-practice linting; kubescape adds explicit control IDs for compliance.
- **Live-cluster tools require authorization.** kube-bench must run on a node with host access
  (managed EKS/GKE restrict the master checks). KubeHound stands up a heavy backend and is
  **interactive** (Gremlin/DSL) — see `references/cluster-hunting.md`.

## Files

```
k8s-config-scan/
├── SKILL.md                       # workflow Claude follows
├── README.md                      # this file
├── references/
│   └── cluster-hunting.md         # kube-bench + KubeHound live-cluster commands & caveats
└── scripts/
    ├── scan.sh                    # Trivy config + kube-linter (+ kubescape) -> findings.json
    └── hunt-cluster.sh            # kube-bench CIS Job (+ optional KubeHound graph)
```
