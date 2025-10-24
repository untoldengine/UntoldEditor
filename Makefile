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

# Lint Swift files using SwiftFormat
lint:
	swiftformat --lint . --swiftversion 5.8 --reporter github-actions-log

# Auto-format Swift files (for convenience)
format:
	swiftformat . --swiftversion 5.8 --quiet
