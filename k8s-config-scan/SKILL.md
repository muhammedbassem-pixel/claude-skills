---
name: k8s-config-scan
description: Scan Kubernetes configuration (manifests, Helm charts, kustomize) against security best practices with Trivy config + kube-linter (and optional kubescape frameworks NSA/CIS/MITRE), and hunt issues on a LIVE cluster with kube-bench (CIS Benchmark) and KubeHound (attack-path graph). Produces best-practice findings and optionally creates Jira tickets in the VM project. Use when the user asks to scan/lint K8s manifests or Helm charts, check Kubernetes security best practices, run a CIS benchmark on a cluster, or map Kubernetes attack paths.
---

# Kubernetes Config Scan + Cluster Hunt + Jira

Scan Kubernetes **configuration** (manifests / Helm / kustomize) against best practices with
[Trivy config](https://trivy.dev) + [kube-linter](https://github.com/stackrox/kube-linter)
(and optional [kubescape](https://kubescape.io) framework mapping), and — for a **live
cluster** — hunt issues with [kube-bench](https://github.com/aquasecurity/kube-bench) (CIS
Benchmark) and [KubeHound](https://github.com/DataDog/KubeHound) (attack-path graph). File
remediation items in the Jira **VM** project.

## Parallelize with subagents

Fan out subagents (launch several in ONE message) for independent work, then aggregate:
- one subagent per scanner tool, or per workload/namespace, to triage findings and draft
  remediation content;
- one subagent per High/Critical misconfiguration to draft its remediation ticket.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicates.

## Step 1 — Ask for scope, then verify preconditions

1. **Ask the user what to scan** (AskUserQuestion or a direct question):
   - a **directory of manifests / a Helm chart / kustomize dir** on disk (static best-practice
     scan — Step 2), and/or
   - a **live cluster** (CIS benchmark + attack-path hunt — Step 3). Confirm authorization for
     any live-cluster action.
2. Verify tooling: Docker daemon running (`docker info`) and `jq`. For live-cluster hunting also
   `kubectl` with a context pointing at the target cluster.

## Step 2 — Scan the configuration (manifests / Helm / kustomize)

Run the bundled script — it pulls **Trivy** and **kube-linter** (and **kubescape** if a
framework is requested), scans the directory, and writes a normalized `findings.json` plus a
markdown report. Invoke by full path:

```bash
bash "<this-skill-dir>/scripts/scan.sh" [-f nsa|cis-v1.23-t1.0.1|mitre|allcontrols] <manifests-dir>
```

- `-f` also runs kubescape against a compliance framework (adds NSA/CIS/MITRE control IDs).
- Output goes to `~/k8s-scan/<name>_REPORT_<datetime>/`: `trivy-config.json`,
  `kube-linter.json`, `kubescape.json` (if `-f`), a ticket-ready `findings.json` (tool,
  severity, check, target:line, message, remediation), and `k8s-report.md`.

Env overrides: `TRIVY_IMAGE`, `KUBELINTER_IMAGE`, `KUBESCAPE_IMAGE`.

Trivy `config` auto-detects K8s YAML, Helm, and kustomize in the tree and maps findings to AVD/
KSV IDs; kube-linter adds zero-config best-practice checks (run-as-non-root, read-only root FS,
privileged, resource limits, probes); kubescape adds explicit framework/control mapping.

## Step 3 — Hunt issues on a live cluster (kube-bench + KubeHound)

For a running cluster, use the cluster-hunt helper (**live cluster — authorization required**):

```bash
bash "<this-skill-dir>/scripts/hunt-cluster.sh" [-H]
```

- **kube-bench (default)** — runs the **CIS Kubernetes Benchmark** as an in-cluster Job with
  host access (kubelet/apiserver/etcd config, file permissions) and collects its JSON to
  `~/k8s-scan/cluster_<datetime>/kube-bench.json`. Note: kube-bench must land on a **node with
  host access**; managed control planes (EKS/GKE) restrict the master checks, and the Job needs
  RBAC to schedule with hostPath/hostPID.
- **KubeHound (`-H`)** — stands up its backend (JanusGraph + MongoDB + Jupyter via Docker
  Compose), dumps the live cluster (read-only RBAC is enough), and ingests it into an
  **attack-path graph**. Analysis is **interactive**: explore paths at
  `http://localhost:8888/notebooks/KubeHound.ipynb` with Gremlin/DSL (e.g. `kh.attacks()`).
  Requires the `kubehound` binary (from its GitHub releases) and Docker Compose; there is no
  tidy JSON report — query the graph. Stop the backend with `kubehound backend down`.

Read `references/cluster-hunting.md` for the manual commands and caveats.

## Step 4 — Present findings

Show the `k8s-report.md` table (tool, severity, check, target:line, issue, remediation) and the
CRITICAL/HIGH counts. For the cluster hunt, summarize kube-bench FAIL/WARN counts and any
notable KubeHound attack paths (privilege escalation, lateral movement to sensitive workloads).
Triage: prioritize privileged containers, missing non-root/read-only-root-fs, hostPath/hostPID,
over-permissive RBAC, and missing network policies.

## Step 5 — Create Jira tickets in the VM project

**Always confirm before creating tickets.** Ask granularity: **one ticket per
misconfiguration/control** (recommended for High/Critical) or a **summary ticket**. Drive
tickets from `findings.json` (each carries tool, check id, severity, target, message,
remediation). Use the Atlassian MCP flow (`getAccessibleAtlassianResources` →
`getVisibleJiraProjects` → `getJiraProjectIssueTypesMetadata` → `getJiraIssueTypeMetaWithFields`
→ `createJiraIssue`, `projectKey: VM`) or the REST API fallback (`POST
$JIRA_BASE_URL/rest/api/3/issue`, ADF description).

## Step 6 — Wrap up

Report: what was scanned (config and/or cluster), finding counts by severity, kube-bench
FAIL/WARN and any KubeHound findings, report directory, and any Jira ticket keys with links.
