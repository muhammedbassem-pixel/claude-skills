# Threat Model — <Application Name>

## Scope
- **Application:** <name>
- **Business owner:** <name/team>
- **Engineering owner:** <name/team>
- **Environment(s):** <Dev / Test / Production>
- **In scope:** <components>
- **Out of scope:** <components>

## Assumptions
- <e.g. Identity Provider enforces MFA>
- <e.g. Internal service communication uses mTLS>
- <e.g. Secrets managed through Vault; databases not publicly accessible>

## Assets (what we protect)
- <sensitive data, credentials, business-critical processes>

## Security objectives
- <confidentiality / integrity / availability goals, compliance: PCI DSS, GDPR, SOC 2, ISO 27001, …>

## Architecture summary
See `architecture.mmd` and `data-flow.mmd`.

## Trust boundaries
| Boundary | From zone | To zone | Controls at crossing |
|----------|-----------|---------|----------------------|
| | | | authn / authz / encryption / validation / logging |

## High-level threats & existing controls
Summarize the top STRIDE findings; full detail in `threat-register.md`.

## Data flows
| Source | Destination | Protocol | Auth | Encryption | Data class | Crosses boundary? |
|--------|-------------|----------|------|-----------|------------|-------------------|
| | | | | | | |
