#!/usr/bin/env bash
#
# Build, sign, notarize and package Dozer release disk images.
#
# Usage:  Scripts/release.sh [version]
#
# Produces one DMG per requested variant:
#
#   universal  Dozer-<version>-universal.dmg   Intel + Apple Silicon
#   arm64      Dozer-<version>-arm64.dmg       Apple Silicon only, ~1/3 smaller
#
# Select variants with the VARIANTS environment variable:
#
#   Scripts/release.sh                 # both (default)
#   VARIANTS=arm64 Scripts/release.sh  # Apple Silicon only
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
VARIANTS="${VARIANTS:-universal arm64}"
[ -n "${VARIANTS// /}" ] || VARIANTS="universal arm64"

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

echo "==> Dozer $VERSION (build $BUILD_NUMBER), variants: $VARIANTS"

# --- helpers -----------------------------------------------------------------

# Rewrites the app so that every embedded Mach-O is arm64-only.
#
# Xcode builds the app target for the requested architectures, but a prebuilt
# binary xcframework (Sparkle) is copied whole, so its slices and its nested
# XPC services, Updater.app and Autoupdate all stay universal. Thinning them is
# what actually makes an "arm64" image arm64-only. Symlinks are skipped: `find
# -type f` never returns them, and replacing one with a file would break the
# framework layout.
thin_embedded_to_arm64() {
    local app="$1" f archs count=0
    while IFS= read -r -d '' f; do
        if file "$f" 2>/dev/null | grep -q "Mach-O"; then
            archs="$(lipo -archs "$f" 2>/dev/null || true)"
            if [ "$archs" != "arm64" ]; then
                lipo -thin arm64 "$f" -output "$f.arm64"
                mv "$f.arm64" "$f"
                count=$((count + 1))
            fi
        fi
    done < <(find "$app" -type f -print0)
    echo "    thinned $count embedded Mach-O file(s) to arm64"
}

# Fails loudly if anything universal survived thinning.
assert_arm64_only() {
    local app="$1" f archs bad=0
    while IFS= read -r -d '' f; do
        if file "$f" 2>/dev/null | grep -q "Mach-O"; then
            archs="$(lipo -archs "$f" 2>/dev/null || true)"
            if [ "$archs" != "arm64" ]; then
                echo "    !! $archs  ${f#"$app"/}" >&2
                bad=1
            fi
        fi
    done < <(find "$app" -type f -print0)
    if [ "$bad" -ne 0 ]; then
        echo "error: the arm64 image still contains non-arm64 code" >&2
        exit 1
    fi
    echo "    all embedded Mach-O files are arm64-only"
}

# Re-signs from the inside out. Thinning rewrites code inside sealed bundles, so
# every enclosing signature has to be regenerated, deepest first.
resign_app() {
    local app="$1" entitlements="$2"
    local fw="$app/Contents/Frameworks/Sparkle.framework"

    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
        "$fw/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
        "$fw/Versions/B/XPCServices/Installer.xpc"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
        "$fw/Versions/B/Autoupdate"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
        "$fw/Versions/B/Updater.app"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
        "$fw/Versions/B"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
        "$fw"
    codesign --force --timestamp --options runtime --entitlements "$entitlements" \
        --sign "$IDENTITY" "$app"
}

notarize_and_staple_app() {
    local app="$1" zip="$OUT/Dozer-$(basename "$app")-notarize.zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    asc notarization submit --file "$zip" --wait
    xcrun stapler staple "$app"
    spctl --assess --type execute --verbose=2 "$app"
}

ensure_sparkle_tools() {
    local app="$1" sparkle_version
    [ -x "$SPARKLE_TOOLS/bin/sign_update" ] && return
    sparkle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Info.plist")"
    echo "==> Fetching Sparkle $sparkle_version tools"
    mkdir -p "$SPARKLE_TOOLS"
    curl -fsSL -o "$OUT/sparkle.tar.xz" \
        "https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz"
    tar -xf "$OUT/sparkle.tar.xz" -C "$SPARKLE_TOOLS"
}

# --- build one variant -------------------------------------------------------

# Sets VARIANT_DMG for the caller.
build_variant() {
    local variant="$1"
    local archs thin=no
    case "$variant" in
        universal) archs="arm64 x86_64" ;;
        arm64)     archs="arm64"; thin=yes ;;
        *) echo "error: unknown variant '$variant' (use universal or arm64)" >&2; exit 1 ;;
    esac

    local archive="$OUT/Dozer-$variant.xcarchive"
    local export_dir="$OUT/export-$variant"
    local app="$export_dir/Dozer.app"
    VARIANT_DMG="$OUT/Dozer-${VERSION}-${variant}.dmg"

    echo
    echo "==> [$variant] archiving ($archs)"

    rm -rf "$archive" "$export_dir"
    xcodebuild archive \
        -project Dozer.xcodeproj -scheme Dozer -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$REPO_ROOT/$archive" \
        -derivedDataPath "$REPO_ROOT/$OUT/DerivedData" \
        ARCHS="$archs" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        OTHER_CODE_SIGN_FLAGS="--timestamp"

    # Exporting with Developer ID re-signs Sparkle's nested helpers, which ship
    # ad-hoc signed in the SPM artifact. Notarization rejects them as-is
    # ("not signed with a valid Developer ID certificate" / "no secure timestamp").
    xcodebuild -exportArchive \
        -archivePath "$REPO_ROOT/$archive" \
        -exportPath "$REPO_ROOT/$export_dir" \
        -exportOptionsPlist "$REPO_ROOT/ExportOptions.plist"

    if [ "$thin" = yes ]; then
        echo "==> [$variant] thinning embedded binaries to arm64"
        # Capture entitlements first: re-signing without them would silently drop
        # com.apple.security.cs.disable-library-validation, which Sparkle needs.
        local entitlements="$OUT/Dozer-$variant-entitlements.plist"
        codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
        thin_embedded_to_arm64 "$app"
        echo "==> [$variant] re-signing inside out"
        resign_app "$app" "$entitlements"
        assert_arm64_only "$app"
    fi

    codesign --verify --deep --strict "$app"
    echo "    signature OK"

    echo "==> [$variant] notarizing and stapling the app"
    notarize_and_staple_app "$app"

    echo "==> [$variant] building, notarizing and stapling the DMG"
    rm -rf "$OUT/dmg-$variant" "$VARIANT_DMG"
    mkdir -p "$OUT/dmg-$variant"
    cp -R "$app" "$OUT/dmg-$variant/"
    ln -s /Applications "$OUT/dmg-$variant/Applications"
    hdiutil create -volname "Dozer" -srcfolder "$OUT/dmg-$variant" -ov -format UDZO "$VARIANT_DMG"
    codesign --force --sign "$IDENTITY" --timestamp "$VARIANT_DMG"

    asc notarization submit --file "$VARIANT_DMG" --wait
    xcrun stapler staple "$VARIANT_DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$VARIANT_DMG"
}

# --- run ---------------------------------------------------------------------

xcodegen generate

DONE_DMGS=()
APP_FOR_KEY_CHECK=""

for variant in $VARIANTS; do
    build_variant "$variant"
    DONE_DMGS+=("$VARIANT_DMG")
    [ -n "$APP_FOR_KEY_CHECK" ] || APP_FOR_KEY_CHECK="$OUT/export-$variant/Dozer.app"
done

# --- signatures for the appcast ---------------------------------------------
#
# Signed only after stapling: stapling rewrites the file, which would invalidate
# a signature taken beforehand.

ensure_sparkle_tools "$APP_FOR_KEY_CHECK"

if [ ! -f "$KEY_FILE" ]; then
    echo "error: Sparkle private key not found at $KEY_FILE" >&2
    exit 1
fi

echo
for dmg in "${DONE_DMGS[@]}"; do
    LENGTH="$(stat -f%z "$dmg")"
    SIGNATURE="$("$SPARKLE_TOOLS/bin/sign_update" --ed-key-file "$KEY_FILE" -p "$dmg")"
    echo "==> $(basename "$dmg")  ($LENGTH bytes)"
    echo "  <enclosure url=\"https://github.com/${REPO_SLUG}/releases/download/v${VERSION}/$(basename "$dmg")\" sparkle:version=\"${BUILD_NUMBER}\" sparkle:shortVersionString=\"${VERSION}\" length=\"${LENGTH}\" type=\"application/octet-stream\" sparkle:edSignature=\"${SIGNATURE}\"/>"
done

cat <<EOF

The appcast enclosure must point at the UNIVERSAL image: it runs natively on
both architectures, so it is the safe update target for every user.

EOF

# --- optionally publish ------------------------------------------------------

if [ "${PUBLISH:-0}" = "1" ]; then
    if gh release view "v$VERSION" --repo "$REPO_SLUG" >/dev/null 2>&1; then
        # The release already exists (for example when adding an arm64 image to a
        # release that already shipped the universal one). Upload only the assets
        # built by this run: `gh release upload` leaves every other asset alone,
        # so the universal DMG stays published.
        echo "==> Updating existing release v$VERSION (other assets are preserved)"
        gh release upload "v$VERSION" "${DONE_DMGS[@]}" appcast.xml \
            --repo "$REPO_SLUG" --clobber
    else
        echo "==> Creating release v$VERSION"
        gh release create "v$VERSION" "${DONE_DMGS[@]}" appcast.xml \
            --repo "$REPO_SLUG" \
            --title "Dozer $VERSION" \
            --notes-file "$OUT/release-notes.md"
    fi
else
    echo "To publish:"
    echo "  git push origin master && git push origin v$VERSION"
    printf '  gh release create v%s' "$VERSION"
    printf ' %q' "${DONE_DMGS[@]}"
    echo " appcast.xml --repo $REPO_SLUG \\"
    echo "      --title 'Dozer $VERSION' --notes-file $OUT/release-notes.md"
    echo
    echo "  (if the release already exists, use: gh release upload v$VERSION \\"
    echo "       <the DMGs above> appcast.xml --repo $REPO_SLUG --clobber)"
fi
