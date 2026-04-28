# Makefile for setting up ROS Noetic build cache and cloning repos
# NOTE: this is not a traditional Makefile, but a script-like structure
# Usage: make [target]

# Configurable variables (edit as needed)
CACHE_DIR := ../race_stack_cache/humble

# Phony targets
.PHONY: \
	help \
	default_setup \
	default_setup_car \
	setup_cache \
	build_base \
	build_full \
	launch_car \
	fix_repo_tokens

help: ## Show available targets and their descriptions
	@echo "\n\033[33mHelper Makefile for the ForzaETH race_stack setup.\033[0m"
	@echo "\nUsage:\n\tmake [target]"
	@echo "\nAvailable [target]s:"
	@grep -E '^[a-zA-Z_-]+:.*?## ' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# HIGH-LEVEL TARGETS
default_setup: export_env edit-json-arm check-registry setup_cache build_base build_sim ## Setup the race_stack on a new computer, with the simulator
default_setup_car: export_env edit-json-jetson check-registry setup_cache build_base build_car ## Setup the race_stack on a new computer, with the car stack
# LEAF TARGETS
export_env:
	@echo "Exporting environment variables to .env file..."\
	&& echo "HOST_UID=$(shell id -u)" > .env \
	&& echo "HOST_GID=$(shell id -g)" >> .env
setup_cache: ## Create cache folder structure
	@echo "Creating ros cache directories..."
	mkdir -p $(CACHE_DIR)/build \
		$(CACHE_DIR)/install \
		$(CACHE_DIR)/logs
	@echo "Cache directories ready at $(CACHE_DIR)"


build_base: ## Build the base workspace
	@echo "Detecting system architecture..."
	@if [ "$$(uname -m)" = "x86_64" ]; then \
		echo "Building for x86 architecture..."; \
		docker compose build base_x86; \
	elif [ "$$(uname -m)" = "aarch64" ]; then \
		echo "Building for Jetson ARM architecture..."; \
		docker compose build base_jet; \
	elif [ "$$(uname -m)" = "arm64" ]; then \
		echo "Building for Apple ARM architecture..."; \
		docker compose build base_arm; \
	else \
		echo "Unsupported architecture: $$(uname -m)"; \
		exit 1; \
	fi
	@echo "Base workspace built successfully."

build_full: ## Build the race_stack with the simulator
	@echo "Detecting system architecture..."
	@if [ "$$(uname -m)" = "x86_64" ]; then \
		echo "Building for x86 architecture..."; \
		export HOST_UID=$$(id -u) HOST_GID=$$(id -g); \
		docker compose build sim_x86; \
	elif [ "$$(uname -m)" = "aarch64" ]; then \
		echo "Building simulator for ARM architecture..."; \
		export HOST_UID=$$(id -u) HOST_GID=$$(id -g); \
		docker compose build sim_jet; \
	elif [ "$$(uname -m)" = "arm64" ]; then \
		echo "Building simulator for ARM architecture (Apple Silicon)..."; \
		export HOST_UID=$$(id -u) GID=$$(id -g); \
		docker compose build sim_arm; \
	else \
		echo "Unsupported architecture: $$(uname -m)"; \
		exit 1; \
	fi
	@echo "Simulator built successfully."

build_car: ## Build the car race stack
	@echo "Detecting system architecture..."
	@if [ "$$(uname -m)" = "x86_64" ]; then \
		echo "Building car race stack for x86 architecture..."; \
		export HOST_UID=$$(id -u) HOST_GID=$$(id -g); \
		docker compose build nuc; \
	elif [ "$$(uname -m)" = "arm64" ] || [ "$$(uname -m)" = "aarch64" ]; then \
		echo "Building car race stack for ARM architecture..."; \
		export HOST_UID=$$(id -u) HOST_GID=$$(id -g); \
		docker compose build jet; \
	else \
		echo "Unsupported architecture: $$(uname -m)"; \
		exit 1; \
	fi
	@echo "Car race stack built successfully."

launch_sim:
	@echo "Detecting system architecture..."
	@if [ "$$(uname -m)" = "x86_64" ]; then \
		export SERVICE_NAME="sim_x86"; \
	elif [ "$$(uname -m)" = "aarch64" ]; then \
		export SERVICE_NAME="sim_jet"; \
	elif [ "$$(uname -m)" = "arm64" ]; then \
		export SERVICE_NAME="sim_arm"; \
		export DISPLAY=:501; \
		echo "Setting DISPLAY to :501 for Apple Silicon..."; \
	else \
		echo "Unsupported architecture: $$(uname -m)"; \
		exit 1; \
	fi; \
	.devcontainer/launch_helper.sh $$SERVICE_NAME

launch_car: ## Launch the car
	@echo "Detecting system architecture..."
	@if [ "$$(uname -m)" = "x86_64" ]; then \
		export SERVICE_NAME="nuc"; \
	elif [ "$$(uname -m)" = "aarch64" ]; then \
		export SERVICE_NAME="jet"; \
	else \
		echo "Unsupported architecture: $$(uname -m)"; \
		exit 1; \
	fi; \
	.devcontainer/launch_helper.sh $$SERVICE_NAME

edit-json-arm:
	@echo "If on an ARM based device, please edit devcontainer.json as follows"
	@echo "Edit the service and runServices to end with _arm and not _x86"
	@echo "Change display from '\$${localEnv:DISPLAY}' to ':501'"
	@printf "Have you updated it if needed?  (y/N): " && read ans && [ "$$ans" = "y" -o "$$ans" = "Y" ] || (echo "Aborted."; exit 1)
	@echo "✅ Proceeding with build..."

edit-json-jetson:
	@echo "If on an jetson, please edit devcontainer.json as follows"
	@echo "Edit the image to end with ..jet and not ..x86"
	@printf "Have you updated it if needed?  (y/N): " && read ans && [ "$$ans" = "y" -o "$$ans" = "Y" ] || (echo "Aborted."; exit 1)
	@echo "✅ Proceeding with build..."

.DEFAULT: ## Handle unknown commands
	@echo "Unknown command: $@"
	@echo "Run 'make help' or 'make' to see available commands."
