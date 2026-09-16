#!/usr/bin/env bash
#
# Build, sign, notarize and package a Dozer release.
#
# Prerequisites:
#   * Xcode with a "Developer ID Application" identity in the login keychain.
#   * `asc` authenticated (`asc auth login`) for notarization.
#   * A Sparkle Ed25519 private key. Export it once with:
#         build/sparkle-tools/bin/generate_keys -x sparkle-keys/ed25519.key
#     The public half goes into Dozer/Other/Info.plist as SUPublicEDKey.
#
# Usage: Scripts/release.sh [version]
#
set -euo pipefail

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Dozer/Other/Info.plist 2>/dev/null || echo 5.0.0)}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Ye Liu (QQ4D4HFJH4)}"
TEAM_ID="${DEVELOPER_TEAM_ID:-QQ4D4HFJH4}"
KEY_FILE="${SPARKLE_KEY_FILE:-$PWD/sparkle-keys/ed25519.key}"
REPO_SLUG="${REPO_SLUG:-lylehust/Dozer}"

OUT="build"
ARCHIVE="$OUT/Dozer.xcarchive"
EXPORT="$OUT/export"
DMG="$OUT/Dozer-${VERSION}-universal.dmg"

echo "==> Releasing Dozer $VERSION"

# 1. Generate the Xcode project and archive a Release build.
xcodegen generate
rm -rf "$ARCHIVE"
xcodebuild archive \
    -project Dozer.xcodeproj -scheme Dozer -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$PWD/$ARCHIVE" \
    -derivedDataPath "$PWD/$OUT/DerivedData" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

# 2. Export with Developer ID. This re-signs Sparkle's nested XPC services,
#    Updater.app and Autoupdate, which ship ad-hoc signed in the SPM
#    artifact and would otherwise fail notarization.
rm -rf "$EXPORT"
xcodebuild -exportArchive \
    -archivePath "$PWD/$ARCHIVE" \
    -exportPath "$PWD/$EXPORT" \
    -exportOptionsPlist "$PWD/ExportOptions.plist"

codesign --verify --deep --strict "$EXPORT/Dozer.app"

# 3. Notarize and staple the app so it validates offline.
ZIP="$OUT/Dozer.zip"
ditto -c -k --keepParent "$EXPORT/Dozer.app" "$ZIP"
asc notarization submit --file "$ZIP" --wait
xcrun stapler staple "$EXPORT/Dozer.app"
spctl --assess --type execute --verbose=2 "$EXPORT/Dozer.app"

# 4. Build the DMG from the stapled app, sign it, notarize and staple it.
rm -rf "$OUT/dmg" "$DMG"
mkdir -p "$OUT/dmg"
cp -R "$EXPORT/Dozer.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Dozer" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

asc notarization submit --file "$DMG" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# 5. Emit the appcast entry for the stapled DMG (sign after stapling!).
LENGTH=$(stat -f%z "$DMG")
SIGNATURE=$(build/sparkle-tools/bin/sign_update --ed-key-file "$KEY_FILE" -p "$DMG")

cat <<EOF

==> Done: $DMG ($LENGTH bytes)

appcast.xml enclosure:
  url="https://github.com/${REPO_SLUG}/releases/download/v${VERSION}/$(basename "$DMG")"
  sparkle:version="$LENGTH" (use CURRENT_PROJECT_VERSION)
  length="$LENGTH"
  sparkle:edSignature="$SIGNATURE"

Upload with:
  gh release create v${VERSION} "$DMG" appcast.xml --repo ${REPO_SLUG} --title "Dozer ${VERSION}" --notes-file ...
EOF
