# lsa-platform — the documented interface to everything in this repository.
# Run `make help` for the list of targets. Targets are added as phases land.

SHELL := /bin/bash

.DEFAULT_GOAL := help

SEED ?= 20260908

.PHONY: help hooks lint data

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

data: ## Generate the synthetic dataset into data/raw (SEED=... to override)
	Rscript r/datagen/generate.R --seed $(SEED) --out data/raw

hooks: ## Install the git pre-commit hooks
	pre-commit install

lint: ## Run all pre-commit checks against the whole tree
	pre-commit run --all-files
