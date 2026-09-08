# Security

Demonstration project; the measures below are real and verifiable in this
repository (files and CI jobs are linked), but the system has never carried
real data or production traffic. Data-protection specifics live in
[datenschutz.md](datenschutz.md), network topology in [network.md](network.md).

## Threat model

| Asset | Threat | Mitigation | Residual risk |
| ----- | ------ | ---------- | ------------- |
| Student-level microdata (synthetic here, sensitive in the real analogue) | Exfiltration through the public API | API connects as `lsa_api`, which the database refuses SELECT on base tables ([0003](../db/migrations/0003_roles.sql)); aggregate-only endpoints; suppression triple-enforced (view, R package, API guard) with tests on each layer | A bug in the *views themselves* could aggregate too finely; mitigated by review and the response-shape tests |
| Database credentials | Leakage via git, image layers, or logs | No secret is ever in a file that git sees (`.env` ignored, roles created NOLOGIN in migrations, credentials attached at deploy time); gitleaks runs in pre-commit and CI; JSON logs never log connection strings | Secrets still live in process env and cluster Secret objects; a cluster admin can read them (that is the k8s trust model) |
| API availability | Crash loops, node maintenance, resource starvation | Liveness/readiness probes, resource requests and limits, 2+ replicas with a PodDisruptionBudget ([k8s/base](../k8s/base)) | Single-node database; a real deployment uses a managed HA database |
| Supply chain | Compromised or vulnerable base images and dependencies | Digest-pinned bases, multi-stage builds, `apt-get upgrade` at build, Trivy gate failing CI on fixable HIGH/CRITICAL, SBOMs (Syft), `pip-audit`, Terraform provider lock file | Digest pins go stale; refreshing them is a deliberate, reviewed change, and the Trivy gate turns red when staleness starts to matter |
| Audit trail | Tampering by a compromised API | `lsa_api` may only INSERT into `api_audit_log` ([0004](../db/migrations/0004_audit.sql)) — it cannot read or rewrite history | The admin role can; protecting against a malicious DBA needs an external log sink |
| Cloud perimeter | Exposed management ports | Security groups: 80/443 public, SSH only from an explicit admin CIDR (the module refuses `0.0.0.0/0`), database reachable only from the app security group ([infra/security.tf](../infra/security.tf)) | The module is validated but has never been applied; see its README |

## Least privilege, concretely

| Principal | May | May not |
| --------- | --- | ------- |
| `lsa_admin` | run migrations, ingest (DELETE + COPY) | is not used by any long-running service |
| `lsa_api` | SELECT on the three published views; INSERT into the audit log | read any base table, read the audit log |
| `lsa_analyst` | SELECT on base tables and views | write anything, read the audit log |
| containers | run as uid 10001, read-only root filesystem, all capabilities dropped, seccomp `RuntimeDefault`, no privilege escalation | root, writable rootfs, host access |

The privilege split is asserted by CI ([sql job](../.github/workflows/ci.yml))
and by a test that connects with the API's own credentials and expects
`InsufficientPrivilege` ([test_api.py](../python/tests/test_api.py)).

## Secrets handling

- Configuration is environment-only ([.env.example](../.env.example) is the
  contract; `.env` is gitignored).
- Migrations create roles `NOLOGIN` and passwordless; credentials are
  attached out-of-band by [bootstrap.sh](../scripts/bootstrap.sh) from the
  environment, so no migration file ever contains a secret.
- The Kubernetes Secret is created at deploy time
  ([kind-up.sh](../scripts/kind-up.sh)), never committed; the kustomization
  documents the expected keys. A real cluster would use sealed secrets or an
  external secrets operator.
- Images bake in no configuration at all — the same image runs in compose,
  kind, and CI with different environments.
- **Rotation**: change the value in the secret store, re-run
  `bootstrap.sh` (an idempotent `ALTER ROLE`), restart the API pods
  (`kubectl rollout restart`). Nothing needs rebuilding, which is the point
  of keeping secrets out of images.

## Scanning and provenance in CI

- **gitleaks** — every push, plus a pre-commit hook.
- **Trivy** — both images, fails on fixable HIGH/CRITICAL.
- **Syft** — SPDX SBOM per image, kept as build artifacts.
- **pip-audit** — Python dependency advisories.
- **terraform validate + tflint**, **kubeconform** — IaC correctness.

## Reporting

See [SECURITY.md](../SECURITY.md) in the repository root.
