# lsa-platform

> **Hinweis / Note:** Dies ist ein Demonstrations- und Lernprojekt, kein
> Produktivsystem. Es wurde gebaut, um technische Fähigkeiten mit lauffähigem
> Code zu belegen. Es besteht keine Verbindung zu ICER, ÜGK, PISA oder Switch,
> und alle Daten sind synthetisch. / This is a demonstration and learning
> project, not production experience. It exists to evidence technical skills
> with working code. It has no affiliation with ICER, ÜGK, PISA, or Switch,
> and all data is synthetic.

A small end-to-end platform for a **fictional** large-scale competency
assessment: synthetic data generation (R), validated ingestion into PostgreSQL
(Python), weighted analysis with small-cell suppression (R package), an
aggregate-only FastAPI service, and the operations layer around it (Bash,
Docker, Kubernetes, Terraform for OpenStack, CI/CD).

**Status: under construction.** This README is expanded as phases land; see
the commit history for progress. The full documentation, architecture diagram,
and requirements map arrive in the final phase.

## Repository layout (grows per phase)

| Path | Purpose |
| ---- | ------- |
| `Makefile` | The documented interface to everything: `make help` |

## License

[MIT](LICENSE)
