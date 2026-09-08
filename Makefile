# lsa-platform — the documented interface to everything in this repository.
# Run `make help` for the list of targets. Targets are added as phases land.

SHELL := /bin/bash

.DEFAULT_GOAL := help

SEED ?= 20260908

.PHONY: help hooks lint data migrate lint-sql install-py lint-py test-py ingest check-r bootstrap backup smoke lint-shell

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

data: ## Generate the synthetic dataset into data/raw (SEED=... to override)
	Rscript r/datagen/generate.R --seed $(SEED) --out data/raw

migrate: ## Apply pending database migrations (connection from environment/.env)
	./scripts/migrate.sh

lint-sql: ## Lint all SQL with sqlfluff
	sqlfluff lint db/

install-py: ## Create python/.venv and install the package with dev extras
	cd python && python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'

lint-py: ## Ruff + mypy on the Python package
	cd python && .venv/bin/ruff check . && .venv/bin/mypy

test-py: ## Run the Python test suite (DB tests need POSTGRES_* env)
	cd python && .venv/bin/pytest --cov=lsa

ingest: ## Validate and load data/raw into PostgreSQL
	python/.venv/bin/lsa-ingest load --data-dir data/raw --report-dir data/reports

bootstrap: ## Migrate, set up the API role, generate + ingest data (idempotent)
	./scripts/bootstrap.sh

backup: ## Dump the database to backups/ (pg_dump custom format)
	./scripts/db_backup.sh

smoke: ## Run the smoke-test suite against a running API (BASE_URL=... to override)
	./scripts/smoke_test.sh --base-url $(or $(BASE_URL),http://localhost:8000)

lint-shell: ## Shellcheck all operations scripts
	shellcheck scripts/*.sh

check-r: ## R CMD check the lsar analysis package
	cd r/lsar && Rscript -e 'roxygen2::roxygenise()'
	R CMD build r/lsar --no-manual
	R CMD check lsar_*.tar.gz --no-manual
	rm -rf lsar_*.tar.gz lsar.Rcheck

hooks: ## Install the git pre-commit hooks
	pre-commit install

lint: ## Run all pre-commit checks against the whole tree
	pre-commit run --all-files
