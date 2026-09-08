# Contributing

This is a personal demonstration project, but it is built to be worked on
like a real one.

## Setup

```bash
git clone https://github.com/jastephan63/lsa-platform
cd lsa-platform
cp .env.example .env        # adjust the passwords
make hooks                  # install pre-commit hooks
make install-py             # python venv + dev tools
```

`make help` lists every documented entry point. The full local stack is
`make up` (Docker) or `make kind-up` (Kubernetes-in-Docker).

## Ground rules

- **Conventional commits** (`feat(scope): …`, `fix(ci): …`); one logical
  change per commit.
- **Everything green before merge.** Every CI job is required; none may be
  skipped or tolerated red. What CI runs, you can run locally first:
  `make lint lint-sql lint-shell lint-py test-py check-r validate-k8s validate-tf`.
- **No secrets in git, ever** — configuration through the environment only.
  gitleaks runs in pre-commit and CI, but the hook is the second line of
  defence, not the first.
- **Synthetic data only.** Never commit generated data or add a data source
  that is not the seeded generator.
- Match the style around you; comments explain constraints, not restate
  code.

## Security

See [SECURITY.md](SECURITY.md).
