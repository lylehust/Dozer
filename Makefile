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

# Build, Developer ID sign, notarize, staple and package Release DMGs.
# `release` delegates to Scripts/release.sh so there is one signing path; an
# archive built any other way is ad-hoc signed and will not notarize.
#
# Both variants are produced by default. An arm64-only run leaves the existing
# universal image on disk and on GitHub untouched.
release:
	@Scripts/release.sh "$(VERSION)"

arm:
	@VARIANTS=arm64 Scripts/release.sh "$(VERSION)"

universal:
	@VARIANTS=universal Scripts/release.sh "$(VERSION)"

.PHONY: setup project build run release arm universal
