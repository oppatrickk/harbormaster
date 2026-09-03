#!/usr/bin/env bash
#
# Builds a distributable Harbormaster.app and zips it into dist/.
#
#     ./Scripts/build-release.sh
#
# The zip is what gets attached to a GitHub release. It is ad-hoc signed (CODE_SIGN_IDENTITY
# is "-" in the project), which is enough to run locally but is NOT notarized — see the
# "Gatekeeper" note in the README for what that means for anyone downloading it.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Harbormaster"
PROJECT="Harbormaster.xcodeproj"
BUILD_DIR="build/release"
DIST_DIR="dist"

# Single source of truth for the version: the project, not a constant duplicated here.
VERSION=$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -showBuildSettings 2>/dev/null |
        awk '/ MARKETING_VERSION = /{print $3; exit}'
)
: "${VERSION:?could not read MARKETING_VERSION from $PROJECT}"

echo "==> Building $SCHEME $VERSION (Release)"
rm -rf "$BUILD_DIR"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    build |
    grep -E '^\*\*|error:' || true

APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

# Fail loudly rather than shipping an icon-less bundle if the asset catalog ever falls out
# of the target again.
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || {
    echo "app has no AppIcon.icns — is Assets.xcassets still in the Resources phase?" >&2
    exit 1
}

mkdir -p "$DIST_DIR"
ZIP="$DIST_DIR/$SCHEME-$VERSION.zip"
rm -f "$ZIP"

# ditto, not zip: it preserves the bundle's symlinks and extended attributes, so the
# unarchived .app still launches. A plain `zip -r` can corrupt the code signature.
echo "==> Packaging $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SIZE=$(du -h "$ZIP" | cut -f1)
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

echo
echo "  $ZIP ($SIZE)"
echo "  sha256: $SHA"
echo
echo "Attach it to a release with:"
echo "  gh release create v$VERSION $ZIP --title \"Harbormaster $VERSION\" --generate-notes"
