---
name: threat-modeling
description: Facilitate STRIDE threat modeling for an application or infrastructure component following the CyberDefense-ThreatModeling framework — scope the system, build a data-flow diagram and trust boundaries, run STRIDE analysis, produce the full artifact set (Mermaid diagrams, OWASP Threat Dragon model, threat register, risk register), launch Threat Dragon locally via Docker, and optionally create Jira tickets in the VM project for High/Critical risks. Use when the user asks to threat model, run a STRIDE analysis, create/update a threat model, run a threat modeling workshop, build a Threat Dragon model, or assess architectural security risk.
---

# Threat Modeling (STRIDE + OWASP Threat Dragon)

Facilitate a threat-modeling workshop and produce a complete, version-controlled threat model
following the CyberDefense-ThreatModeling framework. Read `references/methodology.md` (in this
skill's directory) for the condensed STRIDE process, risk rating, and trust-zone reference —
follow it throughout.

The companion framework repo (methodology, standards, and real Threat Dragon examples) lives at
`CyberDefense-ThreatModeling/`; point the user there for org standards and reference models.

## Parallelize with subagents

Fan out subagents (launch several in ONE message) for independent work, then merge into the
registers:
- one subagent per **component / trust-boundary** to run STRIDE and propose threats with
  likelihood/impact;
- one subagent per **High/Critical threat** to draft the remediation-ticket content.

Do **not** fan out the Jira ticket-creation step — one agent files tickets after your
confirmation to avoid duplicates.

## Step 1 — Scope the system (ask the user)

Gather before modeling (AskUserQuestion or direct questions):
- **What** is being modeled (application / service / infra component) and its **name**.
- **Business context**: purpose, users, critical assets, compliance needs (PCI DSS, GDPR, …).
- **Architecture**: components, external integrations, cloud/K8s, data stores.
- **Security**: authentication, authorization, secrets management, network, existing controls,
  logging, CI/CD.
- **Owners**: business owner and engineering owner; environment(s); what's in/out of scope.

Keep it to one bounded context — model a single service, not the whole enterprise.

## Step 2 — Scaffold the artifacts

Create the standard artifact set from templates (run the script by full path — cwd is not the
skill dir):

```bash
bash "<this-skill-dir>/scripts/scaffold.sh" <app-name> [target-dir]
```

This creates `<target-dir>/<app-name>/` (default base `applications/`) with `README.md`,
`architecture.mmd`, `data-flow.mmd`, `threat-dragon.json`, `threat-model.md`,
`threat-register.md`, and `risks.md`. If the user is working inside the framework repo, use its
`applications/` directory.

## Step 3 — Build the diagrams

Fill in, from the scope discussion:
- **`architecture.mmd`** — components, external systems, trust zones, communication paths
  (architecture level, no code detail).
- **`data-flow.mmd`** — external entities, processes, data stores, data flows, and **trust
  boundaries** (subgraphs). Label each flow with protocol + auth. Use the Data Flow table in
  `threat-model.md` to record source/destination/protocol/auth/encryption/data-class/boundary.

Draw trust boundaries wherever the trust level changes (Internet→Edge, Public→Private,
Cluster→Cloud, CI/CD→Prod, Org→Third party).

## Step 4 — Run Threat Dragon and apply STRIDE

Launch OWASP Threat Dragon locally for the collaborative DFD + STRIDE session:

```bash
bash "<this-skill-dir>/scripts/scaffold.sh" --serve   # http://localhost:3000
```

Click **"Login to Local Session"** to open/save the model from disk (no git-provider OAuth needed). Build the
DFD to match `data-flow.mmd`, then apply STRIDE to **every** external entity, process, data
store, and data flow:

| S | T | R | I | D | E |
|---|---|---|---|---|---|
| Spoofing | Tampering | Repudiation | Information Disclosure | Denial of Service | Elevation of Privilege |

For each threat capture: description, attack scenario, existing controls, proposed mitigation,
likelihood, impact, risk rating, and engineering owner. At every trust-boundary crossing, verify
authn, authz, encryption, input validation, logging, and least privilege.

Save the model over `<app>/threat-dragon.json`.

## Step 5 — Complete the registers

- **`threat-register.md`** — one row per threat (ID, component/flow, STRIDE, description, attack
  scenario, existing controls, likelihood, impact, risk, recommendation, owner, status). Use the
  risk-rating matrix in `references/methodology.md`.
- **`risks.md`** — accepted and residual risks with justification/owner/review date.
- **`threat-model.md`** — scope, assumptions, assets, objectives, trust-boundary table, and a
  summary of top threats.

Every **High** and **Critical** threat must have a remediation action with an engineering owner.

## Step 6 — Create Jira tickets in the VM project

**Always confirm with the user before creating tickets.** File the security backlog — recommend
**one ticket per High/Critical threat** (each is a remediation task); offer a single summary
ticket as an alternative.

### Preferred: Atlassian MCP tools

1. `getAccessibleAtlassianResources` → `cloudId`.
2. `getVisibleJiraProjects` → confirm the **VM** project key.
3. `getJiraProjectIssueTypesMetadata` for VM → pick issue type (default **Task**; **Bug** for a
   concrete vulnerability).
4. `getJiraIssueTypeMetaWithFields` → discover required fields; fill them or ask the user.
5. `createJiraIssue`:
   - `cloudId`, `projectKey: VM`, `issueTypeName` from above
   - `summary`: `[Threat Model] <app>: <STRIDE> <short threat title>`
   - `description`: threat id + STRIDE category, component/flow, attack scenario, risk rating
     (likelihood × impact), existing controls, recommended mitigation, engineering owner, and a
     link/path to the threat model artifacts.

### Fallback: Jira REST API

`POST $JIRA_BASE_URL/rest/api/3/issue` with `JIRA_EMAIL`/`JIRA_API_TOKEN` basic auth, ADF
description, project key `VM`.

## Step 7 — Wrap up

Confirm the Definition of Done artifacts are present (Threat Dragon model, architecture & data-flow
diagrams, trust boundaries, STRIDE assessment, threat register, risk register, security backlog,
owners assigned). Remind the user to open a Pull Request for security review **before
implementation**, and that the threat model is a living document to revisit on architecture,
security, or compliance changes.
