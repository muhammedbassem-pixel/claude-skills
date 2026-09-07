# Threat Modeling Methodology (STRIDE)

Condensed from the CyberDefense-ThreatModeling framework (Workshop.md, Engineering-Governance.md).
Threat models are **living documents** kept in version control, produced before implementation.

## Lifecycle

Design → Prepare Workshop → Threat Dragon Session → STRIDE Analysis → Risk Prioritization →
Engineering Backlog → Mermaid Documentation → Pull Request Review → Continuous Maintenance.

Re-run whenever architecture, infrastructure, security, business scope, or operations change
(new service, auth/authz change, new cloud account, new compliance requirement, incident,
pentest findings, annual review).

## The five questions a threat model answers

1. What are we building? 2. What are we trying to protect? 3. What could go wrong?
4. What controls already exist? 5. What additional mitigations are required? (+ who owns each)

## Workshop scope (Step 1)

Document: application name, business owner, engineering owner, environment(s),
components in scope, components out of scope, assumptions, known limitations.
Keep models small — one bounded context / service at a time.

## Build the Data Flow Diagram (Step 2)

Identify and place:
- **External entities** — end users, mobile apps, third-party APIs, IdPs, payment gateways.
- **Processes** — API gateway, auth service, backend services, workers, notification service.
- **Data stores** — PostgreSQL, Redis, S3/object storage, secrets manager/Vault.
- **Data flows** — every significant communication path (browser→API, API→DB, CI/CD→K8s, …).
- **Trust boundaries** — wherever the trust level changes (Internet→DMZ, Public→Private,
  Cluster→Cloud services, CI/CD→Prod, Org→Third party).

For every data flow record: source, destination, protocol, authentication, encryption,
data classification, and whether it crosses a trust boundary.

## STRIDE (Step 3)

Apply to **every** external entity, process, data store, and data flow:

| Category | Question |
|----------|----------|
| **S**poofing | Can an attacker impersonate a user, service, or system? |
| **T**ampering | Can data or configuration be modified without authorization? |
| **R**epudiation | Can actions occur without reliable audit evidence? |
| **I**nformation Disclosure | Can sensitive information be exposed? |
| **D**enial of Service | Can the system be made unavailable or degraded? |
| **E**levation of Privilege | Can an attacker gain permissions they should not have? |

For each identified threat document: description, attack scenario, existing controls,
proposed mitigations, likelihood, impact, risk rating, and engineering owner.

At each trust-boundary crossing verify: caller authenticated? authorization enforced?
communication encrypted? request validated? activity logged? least-privilege applied?

## Risk rating

Rate **Likelihood** and **Impact** each on Low(1)/Medium(2)/High(3); Risk = the higher-weighted
combination:

| | Impact Low | Impact Medium | Impact High |
|-|-----------|---------------|-------------|
| **Likelihood High** | Medium | High | **Critical** |
| **Likelihood Medium** | Low | Medium | High |
| **Likelihood Low** | Low | Low | Medium |

Prioritize by public attack surface, privileged systems, sensitive data, and critical business
processes. High and Critical risks **must** have remediation tasks with an engineering owner.

## Definition of Done (artifacts)

Threat Dragon model, architecture diagram, data-flow diagram, trust boundaries, STRIDE
assessment, threat register, risk register, security backlog, engineering owners assigned.
Quality of documentation matters more than quantity of threats.

## Trust zones reference

Internet (untrusted) · Edge (CDN/WAF/LB/API GW) · Internal Network · Kubernetes Cluster ·
Cloud Services · CI/CD · Identity · Restricted (databases, secrets, keys, sensitive workloads).
