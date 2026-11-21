# ReOpenSCAD: local convenience targets.
#
#   make            show this help
#   make run        build (release) and run at http://127.0.0.1:5180
#
# Every variable below can be overridden on the command line, e.g.
#   make run PORT=5200 DATA_DIR=~/cad-designs

MANIFEST := web/backend/Cargo.toml

# Designs live outside web/ so the server never has them under its web root.
DATA_DIR ?= $(HOME)/.local/share/reopenscad
HOST     ?= 127.0.0.1
PORT     ?= 5180

# Homebrew's rustup installs the toolchain but does not put cargo/rustc on
# PATH, so prepend the active toolchain's bin directory when rustup knows it.
TOOLCHAIN_BIN := $(shell dirname "$$(rustup which cargo 2>/dev/null)" 2>/dev/null)
ifneq ($(TOOLCHAIN_BIN),.)
export PATH := $(TOOLCHAIN_BIN):$(PATH)
endif
CARGO ?= cargo

# Container settings (Bazzite ships podman; `make ... CONTAINER=docker` works too).
CONTAINER ?= podman
IMAGE     ?= reopenscad:local
CONTAINER_NAME ?= reopenscad
CONTAINER_PORT ?= 8080
VOLUME    ?= reopenscad-data

.DEFAULT_GOAL := help
.PHONY: help run dev build check test test-all test-one fmt lint clean \
        image container-run container-stop container-logs health

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "  Data dir: $(DATA_DIR)   Address: http://$(HOST):$(PORT)"

# --- Running -----------------------------------------------------------------

run: ## Build optimised and run the app locally
	@mkdir -p "$(DATA_DIR)"
	REOPENSCAD_DATA_DIR="$(DATA_DIR)" $(CARGO) run --release --manifest-path $(MANIFEST) -- --host $(HOST) --port $(PORT)

dev: ## Run an unoptimised build (faster to compile, slower to render)
	@mkdir -p "$(DATA_DIR)"
	REOPENSCAD_DATA_DIR="$(DATA_DIR)" $(CARGO) run --manifest-path $(MANIFEST) -- --host $(HOST) --port $(PORT)

health: ## Ask a running server whether it is up
	@curl -fsS http://$(HOST):$(PORT)/api/health && echo

# --- Building and testing ----------------------------------------------------

build: ## Build the release binary (web/backend/target/release/reopenscad-server)
	$(CARGO) build --release --manifest-path $(MANIFEST)

check: ## Type-check without building
	$(CARGO) check --all-targets --manifest-path $(MANIFEST)

# Release mode: several tests assert on speed and fail in a debug build.
test: ## Run the server's unit tests (release mode)
	$(CARGO) test --release --manifest-path $(MANIFEST) --bin reopenscad-server

test-all: ## Run every test, including the integration/parity suites
	$(CARGO) test --release --manifest-path $(MANIFEST)

test-one: ## Run tests matching NAME, e.g. make test-one NAME=encoded_paths
	@test -n "$(NAME)" || { echo "usage: make test-one NAME=<test name filter>"; exit 2; }
	$(CARGO) test --release --manifest-path $(MANIFEST) --bin reopenscad-server -- $(NAME)

fmt: ## Format the Rust sources
	$(CARGO) fmt --manifest-path $(MANIFEST)

lint: ## Run clippy
	$(CARGO) clippy --all-targets --manifest-path $(MANIFEST)

clean: ## Remove build output (does not touch your designs)
	$(CARGO) clean --manifest-path $(MANIFEST)

# --- Container (rehearsal for the NAS) ----------------------------------------

image: ## Build the container image
	$(CONTAINER) build -t $(IMAGE) web/

# Published on 127.0.0.1 only. Designs go to a named volume; `:U` hands it to
# the image's non-root user (uid 65532).
container-run: ## Run the image locally (http://127.0.0.1:8080 by default)
	$(CONTAINER) run -d --rm --name $(CONTAINER_NAME) \
		-p 127.0.0.1:$(CONTAINER_PORT):8080 \
		-v $(VOLUME):/data:U \
		-e REOPENSCAD_DATA_DIR=/data \
		-e REOPENSCAD_PUBLIC_ORIGIN=http://127.0.0.1:$(CONTAINER_PORT) \
		$(IMAGE)
	@echo "Running at http://127.0.0.1:$(CONTAINER_PORT)  (make container-stop to stop)"

container-stop: ## Stop the running container
	-$(CONTAINER) stop $(CONTAINER_NAME)

container-logs: ## Follow the container's logs
	$(CONTAINER) logs -f $(CONTAINER_NAME)
