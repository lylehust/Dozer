#!/usr/bin/env bash
#
# Build, sign, notarize and package a Dozer release.
#
# Usage:  Scripts/release.sh [version]
#
# The version defaults to MARKETING_VERSION in project.yml. (It is deliberately
# not read from Info.plist: that file holds $(MARKETING_VERSION) build-setting
# references, so reading it would yield the literal string "$(MARKETING_VERSION)".)
#
# Prerequisites:
#   * Xcode with a "Developer ID Application" identity in the login keychain.
#   * `asc` authenticated (`asc auth login`) for notarization.
#   * A Sparkle Ed25519 key pair. Create it once and export BOTH halves:
#         build/sparkle-tools/bin/generate_keys
#         build/sparkle-tools/bin/generate_keys -x sparkle-keys/ed25519.key
#         build/sparkle-tools/bin/generate_keys -p > sparkle-keys/ed25519.pub
#     Put the public half in Dozer/Other/Info.plist as SUPublicEDKey. The script
#     asserts the two match, because a mismatch makes every update fail to
#     verify silently, with no error surfaced anywhere.
#
# Set PUBLISH=1 to also create the GitHub release.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUT="build"
IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Ye Liu (QQ4D4HFJH4)}"
TEAM_ID="${DEVELOPER_TEAM_ID:-QQ4D4HFJH4}"
KEY_FILE="${SPARKLE_KEY_FILE:-$REPO_ROOT/sparkle-keys/ed25519.key}"
PUB_FILE="${SPARKLE_PUB_FILE:-$REPO_ROOT/sparkle-keys/ed25519.pub}"
REPO_SLUG="${REPO_SLUG:-lylehust/Dozer}"
SPARKLE_TOOLS="$REPO_ROOT/$OUT/sparkle-tools"

ARCHIVE="$OUT/Dozer.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Dozer.app"

# --- version -----------------------------------------------------------------

read_project_setting() {
    sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" \
        "$REPO_ROOT/project.yml" | head -1
}

MARKETING_VERSION="$(read_project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_project_setting CURRENT_PROJECT_VERSION)"
VERSION="${1:-$MARKETING_VERSION}"

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    echo "error: could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml" >&2
    exit 1
fi

DMG="$OUT/Dozer-${VERSION}-universal.dmg"

echo "==> Releasing Dozer $VERSION (build $BUILD_NUMBER)"

# --- 1. archive --------------------------------------------------------------

xcodegen generate
rm -rf "$ARCHIVE"
xcodebuild archive \
    -project Dozer.xcodeproj -scheme Dozer -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$REPO_ROOT/$ARCHIVE" \
    -derivedDataPath "$REPO_ROOT/$OUT/DerivedData" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

# --- 2. export with Developer ID --------------------------------------------
#
# This re-signs Sparkle's nested XPC services, Updater.app and Autoupdate. They
# ship ad-hoc signed inside the SPM artifact, and notarization rejects them
# as-is ("not signed with a valid Developer ID certificate" / "no secure
# timestamp").

rm -rf "$EXPORT"
xcodebuild -exportArchive \
    -archivePath "$REPO_ROOT/$ARCHIVE" \
    -exportPath "$REPO_ROOT/$EXPORT" \
    -exportOptionsPlist "$REPO_ROOT/ExportOptions.plist"

codesign --verify --deep --strict "$APP"

# --- 3. verify the update signing key matches the app ------------------------

if [ -f "$PUB_FILE" ]; then
    IN_APP="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
    EXPECTED="$(tr -d '\n' < "$PUB_FILE")"
    if [ "$IN_APP" != "$EXPECTED" ]; then
        echo "error: SUPublicEDKey in the app does not match $PUB_FILE" >&2
        echo "  app:      $IN_APP" >&2
        echo "  expected: $EXPECTED" >&2
        echo "  Updates would fail to verify silently. Refusing to release." >&2
        exit 1
    fi
    echo "==> SUPublicEDKey matches the signing key"
else
    echo "warning: $PUB_FILE not found - skipping the public-key check" >&2
fi

# --- 4. notarize and staple the app -----------------------------------------

ZIP="$OUT/Dozer.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
asc notarization submit --file "$ZIP" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# --- 5. build, sign, notarize and staple the DMG -----------------------------

rm -rf "$OUT/dmg" "$DMG"
mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Dozer" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

asc notarization submit --file "$DMG" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# --- 6. fetch the Sparkle tools (if needed) and sign the DMG ----------------

if [ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]; then
    SPARKLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Info.plist")"
    echo "==> Fetching Sparkle $SPARKLE_VERSION tools"
    mkdir -p "$SPARKLE_TOOLS"
    curl -fsSL -o "$OUT/sparkle.tar.xz" \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    tar -xf "$OUT/sparkle.tar.xz" -C "$SPARKLE_TOOLS"
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "error: Sparkle private key not found at $KEY_FILE" >&2
    exit 1
fi

# Sign only after stapling: stapling rewrites the file, which would invalidate
# a signature taken beforehand.
LENGTH="$(stat -f%z "$DMG")"
SIGNATURE="$("$SPARKLE_TOOLS/bin/sign_update" --ed-key-file "$KEY_FILE" -p "$DMG")"

ENCLOSURE="<enclosure url=\"https://github.com/${REPO_SLUG}/releases/download/v${VERSION}/$(basename "$DMG")\" sparkle:version=\"${BUILD_NUMBER}\" sparkle:shortVersionString=\"${VERSION}\" length=\"${LENGTH}\" type=\"application/octet-stream\" sparkle:edSignature=\"${SIGNATURE}\"/>"

echo
echo "==> Built $DMG ($LENGTH bytes)"
echo
echo "appcast.xml enclosure (paste into the <item> for $VERSION):"
echo "  $ENCLOSURE"

# --- 7. optionally publish ---------------------------------------------------

if [ "${PUBLISH:-0}" = "1" ]; then
    echo
    echo "==> Publishing v$VERSION to $REPO_SLUG"
    gh release create "v$VERSION" "$DMG" appcast.xml \
        --repo "$REPO_SLUG" \
        --title "Dozer $VERSION" \
        --notes-file "$OUT/release-notes.md"
else
    echo
    echo "To publish:"
    echo "  git push origin master && git push origin v$VERSION"
    echo "  gh release create v$VERSION '$DMG' appcast.xml --repo $REPO_SLUG \\"
    echo "      --title 'Dozer $VERSION' --notes-file $OUT/release-notes.md"
fi
