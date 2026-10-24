.DEFAULT_GOAL := help

BAZEL ?= bazelisk
SIMULATOR_CONFIG ?= $(if $(filter arm64,$(shell uname -m)),simulator,simulator_intel)
SIMULATOR ?=
IOS_VERSION ?=
DEVICE ?=

# Pass values through the environment so spaces and shell characters stay literal.
export BAZEL SIMULATOR_CONFIG SIMULATOR IOS_VERSION DEVICE

.PHONY: help simulator device test build-simulator build-device clean clean-all list-simulators list-devices check-signing

help:
	@printf '%s\n' \
	  'make simulator         Build and run in an iPhone / iPad simulator' \
	  'make device            Build, sign, and run on an iPhone / iPad (iOS 17+)' \
	  'make test              Run plugin integration tests in Simulator' \
	  'make build-simulator   Build the simulator IPA' \
	  'make build-device      Build the signed device IPA' \
	  'make clean             Remove project build outputs' \
	  'make clean-all         Clear project Bazel state and stop its server' \
	  'make list-simulators   List available simulators' \
	  'make list-devices      List connected devices' \
	  '' \
	  'Optional: SIMULATOR="iPhone 17" IOS_VERSION=27.0 DEVICE="device UDID"' \
	  'Override: BAZEL=bazel SIMULATOR_CONFIG=simulator_intel'

simulator:
	@set -- "$$BAZEL" run //:Contact "--config=$$SIMULATOR_CONFIG"; \
	if [ -n "$$SIMULATOR" ]; then \
	  set -- "$$@" "--@rules_apple//apple/build_settings:ios_simulator_device=$$SIMULATOR"; \
	fi; \
	if [ -n "$$IOS_VERSION" ]; then \
	  set -- "$$@" "--@rules_apple//apple/build_settings:ios_simulator_version=$$IOS_VERSION"; \
	fi; \
	exec env BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 "$$@"

test:
	@set -- "$$BAZEL" test //:PluginIntegrationTests "--config=$$SIMULATOR_CONFIG" --test_output=errors; \
	if [ -n "$$SIMULATOR" ]; then \
	  set -- "$$@" "--@rules_apple//apple/build_settings:ios_simulator_device=$$SIMULATOR"; \
	fi; \
	if [ -n "$$IOS_VERSION" ]; then \
	  set -- "$$@" "--@rules_apple//apple/build_settings:ios_simulator_version=$$IOS_VERSION"; \
	fi; \
	exec "$$@"

device: check-signing
	@set -- "$$BAZEL" run //:Contact --config=device; \
	if [ -n "$$DEVICE" ]; then \
	  set -- "$$@" "--@rules_apple//apple/build_settings:ios_device=$$DEVICE"; \
	fi; \
	exec "$$@"

build-simulator:
	@"$$BAZEL" build //:Contact "--config=$$SIMULATOR_CONFIG"

build-device: check-signing
	@"$$BAZEL" build //:Contact --config=device

clean:
	@"$$BAZEL" clean

clean-all:
	@"$$BAZEL" clean --expunge

list-simulators:
	@xcrun simctl list devices available

list-devices:
	@xcrun devicectl list devices

check-signing:
	@if [ ! -f signing/development.mobileprovision ]; then \
	  printf '%s\n' \
	    'Missing signing/development.mobileprovision.' \
	    'Set your bundle_id in BUILD.bazel and add its development profile.' \
	    'See README.md for signing setup.' >&2; \
	  exit 1; \
	fi
