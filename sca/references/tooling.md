# SCA tooling notes

## Why Trivy + OSV-Scanner

**Trivy** (`aquasec/trivy`) is the one tool that covers all three SCA pillars in a single pass:
- **SBOM** — `trivy fs --format cyclonedx -o sbom.cdx.json <dir>` (also `--format spdx-json`).
- **Vulnerabilities** — `--scanners vuln` (on by default) reads lockfiles across ecosystems.
- **License risk** — `--scanners license` (off by default; must be enabled) classifies licenses
  into risk categories. `--license-full` also scans source/LICENSE files (slower).

**OSV-Scanner** (`ghcr.io/google/osv-scanner`) cross-checks vulnerabilities against the
independent **OSV.dev** database (`scan source -r`). It also flags **malicious** packages
(OpenSSF `MAL-` advisories) and can scan an existing SBOM (`--sbom <file>`). It does not generate
SBOMs or classify licenses.

Union the two vuln feeds for coverage; use Trivy for SBOM + license.

## Alternatives

- **Syft** (`anchore/syft`) — best-in-class SBOM cataloger (`syft <dir> -o cyclonedx-json`);
  broader package cataloging than Trivy if the SBOM itself is the deliverable.
- **Grype** (`anchore/grype`) — vuln scanner that consumes a Syft SBOM (`grype sbom:./sbom.json
  -o json`, `--fail-on high`) using the Anchore feed — a third independent vuln source.

## Vuln DBs / network

All scanners are OSS and need no account. Their vuln DBs are fetched over the network on run and
cached (Trivy caches under `~/.cache/trivy`, mounted by the script). For air-gapped use,
pre-fetch the DB and run Trivy with `--skip-db-update --offline-scan`.

## Turning findings into tickets

- **Vulns** — one ticket per vulnerable *package* bundling its advisories + the target fixed
  version; prioritize fixable + direct dependencies.
- **Licenses** — one compliance ticket for forbidden/restricted licenses incompatible with how
  the software is distributed.
