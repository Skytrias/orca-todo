# Define variables
BUILD_TARGET = src
BUILD_OUTPUT = module.wasm
BUNDLE_NAME = output
RESOURCE_DIR = data
APP_PATH = $(BUNDLE_NAME).app

# Define commands
ODIN_BUILD = odin build $(BUILD_TARGET) -debug -target:orca_wasm32 -out:$(BUILD_OUTPUT)
ORCA_BUNDLE = orca bundle --name $(BUNDLE_NAME) --resource-dir $(RESOURCE_DIR) $(BUILD_OUTPUT)
OPEN_APP = $(APP_PATH)/Contents/MacOS/orca_runtime

.PHONY: all build run clean

# Default target: build and run
all: build run

# Build target
build:
	@echo "Building project..."
	@$(ODIN_BUILD) || { echo "Build failed."; exit 1; }
	@$(ORCA_BUNDLE) || { echo "Bundling failed."; exit 1; }

# Run target
run:
	@echo "Running application..."
	@$(OPEN_APP) || { echo "Failed to open application."; exit 1; }

# Clean target
clean:
	@echo "Cleaning up build artifacts..."
	@rm -f $(BUILD_OUTPUT)
	@echo "Cleanup complete."