# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_APP_DEST := $(HOME)/Applications/roma just talk.app
LATENCY_HARNESS := $(LOCAL_DERIVED_DATA)/Tools/VisibleTextLatencyHarness
LATENCY_HARNESS_SOURCE := Tools/VisibleTextLatencyHarness/VisibleTextLatencyHarness.swift
LATENCY_HARNESS_INFO_PLIST := Tools/VisibleTextLatencyHarness/Info.plist
LATENCY_HARNESS_APP := $(LOCAL_DERIVED_DATA)/Tools/VisibleTextLatencyHarness.app
LATENCY_HARNESS_APP_EXECUTABLE := $(LATENCY_HARNESS_APP)/Contents/MacOS/VisibleTextLatencyHarness
LATENCY_HARNESS_BUNDLE_ID ?= com.happyf.roma-just-talk.VisibleTextLatencyHarness
LATENCY_HARNESS_REPORT ?= $(LOCAL_DERIVED_DATA)/Tools/visible-text-latency.json
LATENCY_HARNESS_STDOUT ?= $(LOCAL_DERIVED_DATA)/Tools/visible-text-latency.out.log
LATENCY_HARNESS_STDERR ?= $(LOCAL_DERIVED_DATA)/Tools/visible-text-latency.err.log
CONFIGURATION ?= Debug
LATENCY_EXPECTED ?=
LATENCY_SAMPLES ?= 5
LATENCY_TRIGGER ?= left-shift
LATENCY_THRESHOLD_MS ?= 440

.PHONY: all clean whisper setup build local check healthcheck help dev run latency-harness-build latency-harness-app latency-harness-check latency-harness-run latency-harness-app-run

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

latency-harness-build:
	@mkdir -p "$(dir $(LATENCY_HARNESS))"
	swiftc "$(LATENCY_HARNESS_SOURCE)" \
		-framework AppKit \
		-framework ApplicationServices \
		-o "$(LATENCY_HARNESS)"

latency-harness-app: latency-harness-build
	@rm -rf "$(LATENCY_HARNESS_APP)"
	@mkdir -p "$(LATENCY_HARNESS_APP)/Contents/MacOS"
	@cp "$(LATENCY_HARNESS)" "$(LATENCY_HARNESS_APP_EXECUTABLE)"
	@cp "$(LATENCY_HARNESS_INFO_PLIST)" "$(LATENCY_HARNESS_APP)/Contents/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(LATENCY_HARNESS_BUNDLE_ID)" "$(LATENCY_HARNESS_APP)/Contents/Info.plist"
	@codesign --force --sign - "$(LATENCY_HARNESS_APP)" >/dev/null
	@echo "Harness app: $(LATENCY_HARNESS_APP)"
	@codesign -dvvv "$(LATENCY_HARNESS_APP)" 2>&1 | sed -n '1,8p'

latency-harness-check:
	bash scripts/check-latency-harness-makefile.sh
	bash scripts/check-visible-text-latency-harness.sh

latency-harness-run: latency-harness-build
	@if [ -z "$(LATENCY_EXPECTED)" ]; then \
		echo "Set LATENCY_EXPECTED to a unique transcript marker."; \
		echo "Example: make latency-harness-run LATENCY_EXPECTED='roma latency marker'"; \
		exit 2; \
	fi
	"$(LATENCY_HARNESS)" \
		--expected "$(LATENCY_EXPECTED)" \
		--samples "$(LATENCY_SAMPLES)" \
		--trigger "$(LATENCY_TRIGGER)" \
		--threshold-ms "$(LATENCY_THRESHOLD_MS)"

latency-harness-app-run:
	@if [ -z "$(LATENCY_EXPECTED)" ]; then \
		echo "Set LATENCY_EXPECTED to a unique transcript marker."; \
		echo "Example: make latency-harness-app-run LATENCY_EXPECTED='roma latency marker'"; \
		exit 2; \
	fi
	@if [ ! -x "$(LATENCY_HARNESS_APP_EXECUTABLE)" ]; then \
		echo "Build the helper app first with: make latency-harness-app"; \
		exit 2; \
	fi
	@rm -f "$(LATENCY_HARNESS_REPORT)" "$(LATENCY_HARNESS_STDOUT)" "$(LATENCY_HARNESS_STDERR)"
	open -W -n \
		-o "$(LATENCY_HARNESS_STDOUT)" \
		--stderr "$(LATENCY_HARNESS_STDERR)" \
		"$(LATENCY_HARNESS_APP)" \
		--args \
		--expected "$(LATENCY_EXPECTED)" \
		--samples "$(LATENCY_SAMPLES)" \
		--trigger "$(LATENCY_TRIGGER)" \
		--threshold-ms "$(LATENCY_THRESHOLD_MS)" \
		--json-output "$(LATENCY_HARNESS_REPORT)"
	@if [ -s "$(LATENCY_HARNESS_STDOUT)" ]; then cat "$(LATENCY_HARNESS_STDOUT)"; fi
	@if [ -s "$(LATENCY_HARNESS_STDERR)" ]; then cat "$(LATENCY_HARNESS_STDERR)" >&2; fi
	@if [ ! -f "$(LATENCY_HARNESS_REPORT)" ]; then \
		echo "No latency JSON report written. Check $(LATENCY_HARNESS_STDOUT) and $(LATENCY_HARNESS_STDERR)."; \
		exit 1; \
	fi
	@PASSED=$$(plutil -extract passed raw -o - "$(LATENCY_HARNESS_REPORT)" 2>/dev/null || echo false); \
	if [ "$$PASSED" != "true" ]; then \
		echo "Latency harness failed. Report: $(LATENCY_HARNESS_REPORT)"; \
		exit 1; \
	fi

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building roma just talk ($(CONFIGURATION)) for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/$(CONFIGURATION)/roma just talk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying roma just talk.app to $(LOCAL_APP_DEST)..."; \
		mkdir -p "$$(dirname "$(LOCAL_APP_DEST)")"; \
		rm -rf "$(LOCAL_APP_DEST)"; \
		ditto "$$APP_PATH" "$(LOCAL_APP_DEST)"; \
		xattr -cr "$(LOCAL_APP_DEST)"; \
		/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -lint -v -R -f "$(LOCAL_APP_DEST)"; \
		echo ""; \
		echo "Build complete! App saved to: $(LOCAL_APP_DEST)"; \
		echo "Run with: open $(LOCAL_APP_DEST)"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built roma just talk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$(LOCAL_APP_DEST)" ]; then \
		echo "Opening $(LOCAL_APP_DEST)..."; \
		open "$(LOCAL_APP_DEST)"; \
	else \
		echo "Looking for roma just talk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "roma just talk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "roma just talk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (Debug default; use CONFIGURATION=Release for packaging)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  latency-harness-build  Compile real visible-text latency harness"
	@echo "  latency-harness-app    Build stable signed helper app for TCC grants"
	@echo "  latency-harness-check  Verify helper-app run target preserves TCC identity"
	@echo "  latency-harness-run    Run CLI latency samples; set LATENCY_EXPECTED"
	@echo "  latency-harness-app-run Run helper-app latency samples; set LATENCY_EXPECTED"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
