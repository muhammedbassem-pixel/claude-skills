# Threat-intel sources & tooling notes

## Supply-chain (packages)

- **OSV-Scanner** (`ghcr.io/google/osv-scanner`) — queries OSV.dev (anonymous, no account) for
  known-vulnerable deps. Crucially it also surfaces **malicious packages**: OpenSSF
  `malicious-packages` advisories carry the **`MAL-`** ID prefix (typosquats, account hijacks).
  `hunt-packages.sh` flags these separately — treat any `MAL-` hit as urgent.
- **GuardDog** (`ghcr.io/datadog/guarddog`) — heuristic detection of malicious PyPI/npm/Go
  packages (obfuscation, install hooks, suspicious metadata). It **downloads and analyzes** each
  referenced package, so it needs network. Complements OSV: OSV = known advisories, GuardDog =
  behavioral/unknown.
- **Trivy fs** (`aquasec/trivy`) — `trivy fs --scanners vuln,license <dir>` for known-vuln deps
  + license issues; not a malicious-package detector.

## Public threat intelligence

None of the mainstream feeds are fully anonymous anymore — all are free-tier but key-gated:

| Source | Access | Covers |
|--------|--------|--------|
| abuse.ch ThreatFox / URLhaus / MalwareBazaar | **Free Auth-Key** (one key, all three) — https://auth.abuse.ch/ | IP/domain/URL/hash IoCs, malware |
| AlienVault OTX | Free API key | pulses, IoCs |
| VirusTotal | Free API key (4 req/min, 500/day) | files/URLs/IPs/domains |
| GreyNoise | Free community key | internet-scan noise / IP context |

`intel-lookup.sh` uses ThreatFox (`$ABUSECH_KEY`). ThreatFox search endpoint:

```bash
curl -sS -H "Auth-Key: $ABUSECH_KEY" -X POST https://threatfox-api.abuse.ch/api/v1/ \
  -d '{"query":"search_ioc","search_term":"<ioc>"}'
```

MalwareBazaar (hash) and URLhaus (host/URL) use the same key with their own endpoints
(`mb-api.abuse.ch`, `urlhaus-api.abuse.ch`) if you need file- or URL-specific detail.

## Log IoC inspection

- **iocextract** (pip; needs `requests`) — extracts IPs, URLs, hashes, emails from arbitrary
  text and **refangs** defanged indicators (`hxxp://`, `1[.]2[.]3[.]4`, `evil[.]com`). Run with
  no extractor flags to get all types; `-r` to refang.
- **grep -F** — fixed-string match of the extracted IoCs against logs (fast, dependency-light).
  `hunt-logs.sh` also derives bare hostnames from any extracted URLs so domain IoCs match log
  lines that reference the host without a scheme/path.
- **Windows EVTX / structured telemetry** — for Sigma-rule hunting use **Chainsaw**
  (WithSecure, EVTX) or **Zircolite** (Sigma over EVTX/JSON/auditd). Out of scope for the
  bundled scripts (which target arbitrary text logs) but the right tool for event logs.

Treat every match as a **lead to confirm**, not proof: enrich matched IoCs via the intel
lookup, check timestamps/context, and rule out benign coincidences before escalating.
