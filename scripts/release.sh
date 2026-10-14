#!/bin/bash
# Builds an ad-hoc signed release, publishes it on GitHub and updates the Homebrew cask.
#
#   scripts/release.sh            # build, zip, tag, GitHub release, update the tap
#   scripts/release.sh --dry-run  # build and zip only, publish nothing
#
# The version is MARKETING_VERSION from the project; bump it in Xcode first.
# Requires: Xcode, gh (signed in), a clean git tree for a real release.

set -euo pipefail

REPO="speakfo/AI-Quota-Studio"
TAP_REPO="speakfo/homebrew-tap"
CASK="ai-quota-studio"
APP_NAME="AI Quota Studio"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"

settings() {
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        -showBuildSettings 2>/dev/null
}
setting() { settings | awk -v k="$1" '$1 == k { print $3; exit }'; }

VERSION="$(setting MARKETING_VERSION)"
BUNDLE_ID="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
TAG="v$VERSION"
ZIP="AI-Quota-Studio-$VERSION.zip"

echo "==> $APP_NAME $VERSION ($BUNDLE_ID)"

if [[ "$BUNDLE_ID" == com.example.* ]]; then
    echo "error: set BUNDLE_ID_PREFIX in Config/Local.xcconfig" >&2
    exit 1
fi

if (( ! DRY_RUN )); then
    [[ -z "$(git status --porcelain)" ]] || { echo "error: working tree is not clean" >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "error: run 'gh auth login'" >&2; exit 1; }
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        echo "error: tag $TAG already exists; bump MARKETING_VERSION" >&2
        exit 1
    fi
fi

echo "==> Building"
rm -rf "$BUILD"
# Ad-hoc signature whatever Local.xcconfig says; no get-task-allow in a release.
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath "$BUILD/DerivedData" -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build -quiet

APP="$BUILD/DerivedData/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - "$APP" "$APP/Contents/PlugIns/"*.appex 2>/dev/null | grep -q get-task-allow; then
    echo "error: get-task-allow in the release build" >&2
    exit 1
fi

echo "==> Packing $ZIP"
ditto -c -k --keepParent "$APP" "$BUILD/$ZIP"
SHA256="$(shasum -a 256 "$BUILD/$ZIP" | awk '{ print $1 }')"
echo "    sha256 $SHA256"

# The build is not registered anywhere, so Spotlight does not show a second copy.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$APP" 2>/dev/null || true

CASK_FILE="$BUILD/$CASK.rb"
cat > "$CASK_FILE" <<EOF
cask "$CASK" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/AI-Quota-Studio-#{version}.zip"
  name "$APP_NAME"
  desc "Menu bar app and widgets for Claude Code, Antigravity and Codex quota usage"
  homepage "https://github.com/$REPO"

  depends_on macos: :tahoe

  app "$APP_NAME.app"

  # The app is signed ad-hoc and not notarized: without this Gatekeeper refuses to open it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "$APP_NAME.app"], chdir: "{{appdir}}"
  end

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Application Support/AIQuota",
    "~/Library/Containers/$BUNDLE_ID.AIQuotaWidget",
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]
end
EOF

if (( DRY_RUN )); then
    echo "==> Dry run: $BUILD/$ZIP and $CASK_FILE are ready, nothing published"
    exit 0
fi

echo "==> Publishing $TAG"
git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$BUILD/$ZIP" --repo "$REPO" --title "$APP_NAME $VERSION" \
    --notes "Install: \`brew install --cask ${TAP_REPO%%/*}/${TAP_REPO#*/homebrew-}/$CASK\`"

echo "==> Updating $TAP_REPO"
TAP="$BUILD/tap"
gh repo clone "$TAP_REPO" "$TAP" -- --quiet
mkdir -p "$TAP/Casks"
cp "$CASK_FILE" "$TAP/Casks/$CASK.rb"
# Same author as this repository (its local config), HTTPS auth through gh.
TAP_GIT=(git -C "$TAP" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)"
         -c credential.helper= -c credential.helper='!gh auth git-credential')
"${TAP_GIT[@]}" add "Casks/$CASK.rb"
"${TAP_GIT[@]}" commit --quiet -m "$CASK $VERSION"
"${TAP_GIT[@]}" push --quiet

echo "==> Done: brew install --cask ${TAP_REPO%%/*}/${TAP_REPO#*/homebrew-}/$CASK"
