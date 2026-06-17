IMAGE       ?= d1-health-api
TAG         ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo local)
APP_VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo 0.0.0-dev)
BA          := --build-arg APP_VERSION=$(APP_VERSION) --build-arg GIT_SHA=$(TAG)

.PHONY: help lint test build build-distroless build-naive sizes run scan clean down

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	 awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

lint: ## Lint Dockerfiles with hadolint
	hadolint --failure-threshold error Dockerfile Dockerfile.distroless

VENV   := .venv
PYTHON := $(VENV)/bin/python
PIP    := $(VENV)/bin/pip

$(VENV):
	python3 -m venv $(VENV)

test: $(VENV) ## Run unit tests
	$(PIP) install -r app/requirements.txt pytest httpx2 -q
	$(PYTHON) -m pytest -q

build: ## Build the optimized slim image
	docker build -f Dockerfile $(BA) -t $(IMAGE):slim .

build-distroless: ## Build the distroless image
	docker build -f Dockerfile.distroless $(BA) -t $(IMAGE):distroless .

build-naive: ## Build the anti-pattern image (comparison only)
	docker build -f Dockerfile.naive -t $(IMAGE):naive .

sizes: build-naive build build-distroless ## Build all variants and print the size table
	@echo ""
	@echo "VARIANT                    SIZE"
	@docker images --format '{{.Repository}}:{{.Tag}}|{{.Size}}' \
	  | grep '^$(IMAGE):' | sort \
	  | awk -F'|' '{printf "%-26s %s\n", $$1, $$2}'

run: ## Run locally via compose
	APP_VERSION=$(APP_VERSION) GIT_SHA=$(TAG) docker compose up --build

scan: build ## Trivy scan the slim image (a preview of D5)
	trivy image --severity HIGH,CRITICAL $(IMAGE):slim

down: ## Stop and remove D1 containers and network (images and volumes kept)
	docker compose down

clean: ## Remove D1 containers/network AND the three built images
	docker compose down
	-docker rmi $(IMAGE):naive $(IMAGE):slim $(IMAGE):distroless 2>/dev/null || true
