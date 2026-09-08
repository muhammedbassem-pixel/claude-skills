# IaC scan coverage & best-practice categories

## Tools

- **Checkov** (`bridgecrew/checkov`) — primary. Broadest framework coverage; built-in policies
  run fully offline. Frameworks: `terraform, terraform_plan, cloudformation, arm, bicep,
  dockerfile, serverless, kubernetes, helm, kustomize, secrets, github_actions, gitlab_ci,
  openapi, json, yaml, …` (no `ansible`). Findings: `CKV_*` ID + `guideline` URL. Restrict with
  `--framework <name>`; resolve remote TF modules with `--download-external-modules`.
- **Trivy config** (`aquasec/trivy`) — fast second opinion. Covers Terraform, CloudFormation,
  ARM, Dockerfile, Kubernetes, Helm in one pass (`AVD-*` IDs, `https://avd.aquasec.com/misconfig/<ID>`).
  Does not cover Bicep or Serverless.

Union both feeds; de-duplicate where they flag the same resource.

## What to prioritize (across cloud IaC)

- **Public exposure** — open security groups / NSGs (`0.0.0.0/0` to sensitive ports), public S3/
  blob/bucket ACLs & policies, public DB instances, public load balancers.
- **Encryption** — unencrypted storage/volumes/databases, missing KMS/CMK, no encryption in
  transit, unencrypted snapshots.
- **IAM / access** — wildcard actions/resources, over-permissive roles, no MFA, long-lived keys,
  privilege escalation paths.
- **Logging & monitoring** — disabled CloudTrail/flow logs/audit logs, no access logging on
  buckets/LBs.
- **Network** — default VPC use, missing segmentation, permissive egress, no private endpoints.
- **Containers / Dockerfile** — running as root, unpinned/`latest` base images, secrets in
  layers, no healthcheck, added capabilities.
- **Kubernetes/Helm** — privileged/hostPath/hostNetwork, no resource limits, no securityContext,
  default service accounts, missing network policies.

## Turning findings into tickets

One ticket per misconfiguration for High/Critical (resource + file:line + the `CKV_*`/`AVD-*` ID
+ guideline URL + fix), or a summary ticket for lower severities. Wire the scan into CI to gate
merges before `terraform apply` / deploy.
