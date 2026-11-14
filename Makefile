SHELL := /usr/bin/env bash
include config.env.example
-include config.env

BUILD_TOOLS_APT_PKG ?= google-android-build-tools-35.0.1-installer

.PHONY: all deps build install audit check clean

all: build install

deps:
	sudo apt update && sudo apt install -y adb default-jdk-headless $(BUILD_TOOLS_APT_PKG)

build:
	@chmod +x scripts/*.sh
	./scripts/build.sh

install:
	@chmod +x scripts/*.sh
	./scripts/deploy.sh

audit:
	@chmod +x scripts/*.sh
	./scripts/deploy.sh --audit-only

check:
	@chmod +x scripts/*.sh
	./scripts/deploy.sh --check-only

clean:
	rm -rf build dist
