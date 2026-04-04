.PHONY: build install run restart clean test check help dev

APP_NAME = PowerBarPro
INSTALL_PATH = /Applications/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)
SCRIPTS = Scripts

help:
	@echo "PowerBarPro Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build    - Build in release mode"
	@echo "  install  - Build and install to /Applications"
	@echo "  run      - Build and run the binary directly"
	@echo "  restart  - Full rebuild, reinstall and restart"
	@echo "  clean    - Remove build artifacts"
	@echo "  test     - Run unit tests"
	@echo "  check    - Verify macmon is available"
	@echo "  dev      - Clean build and run (development cycle)"
	@echo "  help     - Show this help"

build:
	@$(SCRIPTS)/build.sh

install: build
	@$(SCRIPTS)/install.sh

run: build
	@echo "Starting $(APP_NAME)..."
	@$(BINARY)

restart:
	@$(SCRIPTS)/rebuild_and_run.sh

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .build
	@echo "Done."

test:
	@echo "Running tests..."
	@swift test

check:
	@echo "Checking macmon..."
	@if command -v macmon >/dev/null 2>&1; then \
		echo "macmon is available"; \
		macmon --version; \
	else \
		echo "macmon is not installed"; \
		echo "  Install: brew install macmon"; \
	fi

dev: clean build run
