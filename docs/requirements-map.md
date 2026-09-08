# Requirements map / Anforderungs-Zuordnung

Jede Zeile verbindet eine Anforderung aus dem Stellenprofil mit dem
konkreten, lauffähigen Beleg in diesem Repository und dem CI-Job, der ihn
bei jedem Push prüft. Alle CI-Jobs sind Pflicht; der Badge im
[README](../README.md) zeigt den aktuellen Stand.
*Ehrlicher Rahmen: Demonstrationsprojekt mit synthetischen Daten — was neu
für mich war, steht im README unter „Was ich dabei gelernt habe".*

| Anforderung (Stellenprofil) | Beleg im Code | Geprüft durch CI-Job |
| --------------------------- | ------------- | -------------------- |
| **Python** | [Ingest-CLI](../python/lsa/ingest) mit pydantic-Validierung und transaktionalem COPY-Load; [FastAPI-Service](../python/lsa/api) mit Request-IDs und JSON-Logging; [Tests](../python/tests) (20, inkl. DB-Integration) | `python` (ruff, mypy strict, pytest + Coverage, auf 3.11 **und** 3.12) |
| **Bash/Shell-Scripting** | [scripts/](../scripts): migrate, bootstrap, backup/restore, smoke-tests, Log-Filter, kind-up — alle `set -euo pipefail`, alle mit `--help` | `shell` (shellcheck + `--help`-Check) |
| **Git & CI/CD** | Konventionelle Commits in Phasen (Historie), [ci.yml](../.github/workflows/ci.yml) mit 12 Pflicht-Jobs, [release.yml](../.github/workflows/release.yml) (Tag → GHCR-Images + SBOM + Release), [Pre-commit-Hooks](../.pre-commit-config.yaml) | die Pipeline selbst; `hygiene` |
| **R** | [Datengenerator](../r/datagen/generate.R) (zweistufige PPS-Stichprobe, Rasch-Modell, Plausible Values); [Paket `lsar`](../r/lsar) mit roxygen2-Doku und testthat-Tests: gewichtete Schätzung nach Rubin, Kleinzellen-Unterdrückung | `datagen` (Reproduzierbarkeit), `r-package` (R CMD check; ein Test erzwingt **exakte** Übereinstimmung von R- und SQL-Schätzern) |
| **Linux/Unix-Umfeld** | Alles läuft in Linux-Containern; [Dockerfiles](../docker) (non-root, read-only FS), Prozess-, Signal- und Rechte-Details in den Scripts und Manifesten | jeder containerbasierte Job |
| **SQL** | [Versionierte Migrationen](../db/migrations) mit FKs, Checks, Indizes; analytische Views inkl. kommentierter CTE-/Window-Function-Query ([0002](../db/migrations/0002_views.sql)); [Rollen-Trennung](../db/migrations/0003_roles.sql) | `sql` (sqlfluff; Migrationen auf leerer DB, Idempotenz, Schema- und Privilegien-Assertions) |
| **Command-Line-Proficiency** | Das [Makefile](../Makefile) als dokumentierte Schnittstelle (`make help`); jede Komponente ist ein CLI-Werkzeug mit `--help` | `shell`; alle Make-Targets werden in CI benutzt |
| **Docker** | [Multi-Stage-Builds](../docker) mit digest-gepinnten Basen, HEALTHCHECK, uid 10001; [compose.yaml](../compose.yaml): ganze Plattform mit einem Befehl | `containers` (Build beider Images + Trivy-Gate + SBOM) |
| **Kubernetes** | [Kustomize-Base + dev/prod-Overlays](../k8s): Probes, Requests/Limits, Ingress, ConfigMap, referenziertes Secret (nie committed), StatefulSet (+ Managed-DB-Abwägung), Default-Deny-NetworkPolicies, PodSecurityContext, PDB; [kind-up.sh](../scripts/kind-up.sh) | `k8s-validate` (kubeconform, strict); `e2e-kind` (echtes Deployment auf kind + Smoke-Tests durch den Ingress) |
| **Terraform** | [infra/](../infra): OpenStack-Modul — Netz, Subnetz, Router, Security Groups, Keypair, Instanzen, Floating IP; dokumentierte Variablen/Outputs, Remote-State dokumentiert | `terraform` (fmt, validate, tflint, terraform-docs-Abgleich) |
| **Cloud-IaaS-Konzepte (OpenStack)** | Provider-Wahl wegen Switch Engines; Neutron-Konzepte im Modul; [Modul-README](../infra/README.md) mit ehrlicher Reichweite („validiert, nie applied") | `terraform` |
| **Netzwerkgrundlagen** | [docs/network.md](network.md): Traffic-Pfad mit Diagramm, Ports, Cluster-DNS, TLS-Terminierung, Security-Groups vs. NetworkPolicies | `e2e-kind` beweist den Pfad Client→Ingress→Service→Pod→DB praktisch |
| **Security-Basics** | [docs/security.md](security.md): Threat-Model-Tabelle, Least Privilege auf jeder Ebene, Secret-Handhabung samt Rotation | `secrets` (gitleaks), `containers` (Trivy, SBOM), `dependency-audit` (pip-audit); `sql` und `python` asserten die Privilegien-Trennung |
| **Bewusstsein für Datenschutz und Datensicherheit** | [docs/datenschutz.md](datenschutz.md): Privacy by Design, Pseudonymisierung, Aufbewahrungs-Policy, DSG/DSGVO-Einordnung; Kleinzellen-Unterdrückung **dreifach im Code** (View, R, API-Guard) | Tests auf allen drei Ebenen schlagen fehl, sobald eine zu kleine Zelle publiziert würde (`r-package`, `python`, `e2e-kind`) |

## Zwei Belege, die ich hervorheben würde

1. **R und SQL müssen sich einig sein:** [test-db.R](../r/lsar/tests/testthat/test-db.R)
   berechnet die gewichteten Kantonsmittel im R-Paket und vergleicht sie
   Zeile für Zeile mit der SQL-View — inklusive identischer
   Unterdrückungsentscheidungen. Zwei Implementierungen als gegenseitige
   Verifikation statt als Risiko.
2. **Least Privilege ist getestet, nicht behauptet:**
   [test_api.py](../python/tests/test_api.py) verbindet sich mit den
   Credentials der API-Rolle und erwartet `InsufficientPrivilege` beim
   Zugriff auf Einzeldaten; der `sql`-CI-Job prüft dieselbe Trennung auf
   Datenbankebene.
