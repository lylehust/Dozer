DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
PROJECT = Dozer.xcodeproj
SCHEME = Dozer
CONFIGURATION = Debug

setup:
	@xcodegen

project: setup
	@xed "."

build: setup
	@DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination "platform=macOS" build

run: build
	@APP_PATH="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -showBuildSettings | awk -F ' = ' '/ TARGET_BUILD_DIR / { dir=$$2 } / WRAPPER_NAME / { name=$$2 } END { print dir "/" name }')"; \
	open "$$APP_PATH"

# Build a signed, universal (arm64 + x86_64) Release archive.
release: setup
	@DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild archive \
		-project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release \
		-destination "generic/platform=macOS" \
		-archivePath build/Dozer.xcarchive

.PHONY: setup project build run release
