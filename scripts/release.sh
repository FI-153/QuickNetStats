#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCHEME="QuickNetStats"
PROJECT="QuickNetStats.xcodeproj"
APP_NAME="QuickNetStats"
NOTARY_PROFILE="quicknetstats-notary"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"

# Temp directories (cleaned up at the end)
ARCHIVE_PATH="$PROJECT_DIR/build/Release.xcarchive"
EXPORT_DIR="$PROJECT_DIR/build/Export"
ZIP_NAME="$APP_NAME.app.zip"

# ─── Helpers ─────────────────────────────────────────────────────────────────
red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

cleanup() {
    info "Cleaning up build artifacts..."
    rm -rf "$PROJECT_DIR/build"
    rm -f "$PROJECT_DIR/$ZIP_NAME"
}

die() { red "Error: $*" >&2; exit 1; }

# ─── Validate ────────────────────────────────────────────────────────────────
TAG="${1:-}"
[ -z "$TAG" ] && die "Usage: $0 <tag>  (e.g., V.2.2.0-Beta-1)"

command -v gh       >/dev/null || die "GitHub CLI (gh) is not installed. Run: brew install gh"
command -v xcrun    >/dev/null || die "Xcode command line tools not found"

cd "$PROJECT_DIR"

# Check working tree is clean
if ! git diff --quiet HEAD 2>/dev/null; then
    die "Working tree has uncommitted changes. Commit or stash first."
fi

# Check tag doesn't already exist
if git rev-parse "$TAG" >/dev/null 2>&1; then
    die "Tag '$TAG' already exists"
fi

info "Releasing $APP_NAME as $TAG"

# ─── Step 1: Archive ────────────────────────────────────────────────────────
info "Building release archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM=7F47MKWBPJ \
    -quiet

[ -d "$ARCHIVE_PATH" ] || die "Archive failed — $ARCHIVE_PATH not found"
green "Archive created"

# ─── Step 2: Export ──────────────────────────────────────────────────────────
info "Exporting signed app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -quiet

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP_PATH" ] || die "Export failed — $APP_PATH not found"
green "App exported"

# ─── Step 3: Notarize ───────────────────────────────────────────────────────
info "Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$APP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

green "Notarization complete"

# ─── Step 4: Staple ─────────────────────────────────────────────────────────
info "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
green "Stapled"

# ─── Step 5: Zip ────────────────────────────────────────────────────────────
info "Creating zip..."
cd "$EXPORT_DIR"
zip -r -q "$PROJECT_DIR/$ZIP_NAME" "$APP_NAME.app"
cd "$PROJECT_DIR"
green "Created $ZIP_NAME"

# ─── Step 6: Tag & Push ─────────────────────────────────────────────────────
info "Tagging $TAG and pushing..."
git tag "$TAG"
git push origin "$TAG"
green "Tag pushed"

# ─── Step 7: GitHub Release ─────────────────────────────────────────────────
info "Creating GitHub release..."
PRERELEASE_FLAG=""
if [[ "$TAG" == *[Bb]eta* ]]; then
    PRERELEASE_FLAG="--prerelease"
    info "Detected beta release"
fi

# Extract version for the title (strip v/V prefix and leading dot)
VERSION="${TAG#[vV]}"
VERSION="${VERSION#.}"

gh release create "$TAG" "$ZIP_NAME" \
    --title "$VERSION" \
    $PRERELEASE_FLAG

green "Release created: $TAG"

# ─── Step 8: Cleanup ────────────────────────────────────────────────────────
cleanup
green "Done! Release $TAG is live."
