# lsa-platform — the documented interface to everything in this repository.
# Run `make help` for the list of targets. Targets are added as phases land.

SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help hooks lint

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

hooks: ## Install the git pre-commit hooks
	pre-commit install

lint: ## Run all pre-commit checks against the whole tree
	pre-commit run --all-files
