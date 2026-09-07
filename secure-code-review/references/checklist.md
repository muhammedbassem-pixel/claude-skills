# Secure Code Review Checklist — OWASP Top 10 (2021) + CWE/SANS Top 25

Use the Semgrep output as the automated first pass, then review manually against these
categories. Semgrep rule packs map to these: `p/owasp-top-ten`, `p/cwe-top-25`,
`p/security-audit`, `p/secrets`.

## OWASP Top 10 (2021)

- **A01 Broken Access Control** — missing authorization checks, IDOR, path traversal
  (CWE-22), CSRF (CWE-352), force-browsing, privilege escalation. Verify every sensitive
  endpoint enforces authz server-side, not just in the UI.
- **A02 Cryptographic Failures** — plaintext secrets/PII, weak algorithms (MD5/SHA1/DES),
  hardcoded keys (CWE-798), missing TLS, weak randomness (CWE-338). Check key management.
- **A03 Injection** — SQL (CWE-89), OS command (CWE-78), LDAP, XPath, NoSQL, and XSS
  (CWE-79). Look for string-concatenated queries/commands; require parameterization/escaping.
- **A04 Insecure Design** — missing rate limiting, no threat model for sensitive flows,
  business-logic abuse. This is review-only; tools rarely catch it.
- **A05 Security Misconfiguration** — debug enabled in prod, default creds, verbose errors
  (CWE-209), permissive CORS, missing security headers, open cloud buckets.
- **A06 Vulnerable & Outdated Components** — old dependencies with known CVEs. Complement
  Semgrep with an SCA scan (Trivy / OSV-Scanner) against lockfiles.
- **A07 Identification & Authentication Failures** — weak password policy, missing MFA,
  session fixation, predictable tokens, credential stuffing exposure.
- **A08 Software & Data Integrity Failures** — insecure deserialization (CWE-502), unsigned
  updates, untrusted CI/CD input.
- **A09 Security Logging & Monitoring Failures** — missing audit logs on auth/authz events,
  logging secrets, no alerting.
- **A10 SSRF** (CWE-918) — user-controlled URLs in server-side requests; validate/allowlist.

## CWE/SANS Top 25 — high-frequency IDs to grep for

CWE-79 XSS, CWE-787 out-of-bounds write, CWE-89 SQLi, CWE-416 use-after-free, CWE-78 OS
command injection, CWE-20 improper input validation, CWE-125 out-of-bounds read, CWE-22 path
traversal, CWE-352 CSRF, CWE-434 unrestricted upload, CWE-862 missing authorization, CWE-476
NULL deref, CWE-287 improper authentication, CWE-190 integer overflow, CWE-502 deserialization,
CWE-77 command injection, CWE-119 buffer bounds, CWE-798 hardcoded credentials, CWE-918 SSRF,
CWE-306 missing auth for critical function, CWE-362 race condition, CWE-269 improper privilege
management, CWE-94 code injection, CWE-863 incorrect authorization, CWE-276 default permissions.

## Per-language focus & complementary scanners

- **PHP** — SQLi via raw `mysqli_query`/string concat, `eval`/`system`/`exec`, unserialize()
  (CWE-502), file inclusion (LFI/RFI), `$_GET`/`$_POST` used unsanitized. Pack: `p/php`.
  Complement: Psalm `--taint-analysis`.
- **Java** — SQLi via `Statement` (use `PreparedStatement`), XXE in parsers, deserialization,
  SSRF, Spring authz gaps, Log4Shell-style lookups. Pack: `p/java`. Complement: SpotBugs +
  find-sec-bugs.
- **Python** — `subprocess`/`os.system` with shell=True (CWE-78), `pickle`/`yaml.load`
  (CWE-502), `eval`/`exec`, Flask/Django template & ORM injection, hardcoded secrets. Pack:
  `p/python`. Complement: Bandit (`bandit -r .`).
- **React / JS / TS** — `dangerouslySetInnerHTML` (XSS), `eval`, prototype pollution, insecure
  `postMessage`, secrets in client bundles, open redirects. Packs: `p/react`, `p/typescript`,
  `p/javascript`. Complement: eslint-plugin-security, njsscan.
- **Flutter / Dart** — Semgrep Dart support is experimental; rely on `dart analyze` (with a
  hardened `analysis_options.yaml`) plus manual review against **OWASP MASVS/MASTG**: insecure
  storage (shared_prefs/plaintext), hardcoded secrets/API keys in the bundle, weak TLS / no
  cert pinning, insecure WebView, deep-link handling.
- **Go** — SQLi via `fmt.Sprintf` into queries, command injection via `os/exec`, SSRF, weak
  crypto/rand, path traversal. Pack: `p/golang`. Complement: gosec (`gosec ./...`).

## SCA (all languages) — OWASP A06

Run Trivy or OSV-Scanner against the repo's lockfiles to flag vulnerable/outdated dependencies:
`docker run --rm -v "$PWD:/src" aquasec/trivy fs /src`.
