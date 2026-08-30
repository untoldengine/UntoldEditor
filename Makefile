# Makefile for UntoldEngineEditor

# Build the Swift package

build:
	swift build

# Clean build artifact

clean:
	swift package clean 

# Test target 
test:
	swift test

# Required SwiftFormat version
SWIFTFORMAT_VERSION := 0.60.1

# Verify installed SwiftFormat matches the required version
check-swiftformat-version:
	@INSTALLED=$$(swiftformat --version 2>&1 | awk '{print $$NF}'); \
	if [ "$$INSTALLED" != "$(SWIFTFORMAT_VERSION)" ]; then \
		echo "Error: swiftformat $(SWIFTFORMAT_VERSION) required, but found $$INSTALLED"; \
		echo "Install from: https://github.com/nicklockwood/SwiftFormat/releases/tag/$(SWIFTFORMAT_VERSION)"; \
		exit 1; \
	fi

# Lint Swift files using SwiftFormat
lint: check-swiftformat-version
	swiftformat --lint . --swiftversion 5.8 --reporter github-actions-log

# Auto-format Swift files (for convenience)
format: check-swiftformat-version
	swiftformat . --swiftversion 5.8 --quiet
