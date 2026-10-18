#!/bin/zsh
# Builds Best Planner.app (with its desktop widget) using only the Command Line Tools.
#   ./build.sh           build for this Mac and install to /Applications
#   ./build.sh release   build a universal (Apple silicon + Intel) app and zip it
#                        into dist/ for sharing (not installed), plus a .sha256
#                        checksum; upload both to the GitHub release
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.5.3"
MODE="${1:-install}"
APP_ID="com.bestplanner.app"
WIDGET_ID="$APP_ID.widget"
BUILD="build"
APP_NAME="Best Planner"
APP="$BUILD/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/PlannerWidget.appex"

# "owner/repo" of the GitHub repository, used by 检查更新 (empty if there's no remote).
UPDATE_REPO="$(git remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##' || true)"

if [ "$MODE" = "release" ]; then ARCHS=(arm64 x86_64); else ARCHS=("$(uname -m)"); fi

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

# Compiles once per architecture and merges the results into one binary.
compile() {
  local out="$1"; shift
  local parts=()
  for arch in "${ARCHS[@]}"; do
    swiftc -O -parse-as-library -target "$arch-apple-macos14.0" "$@" -o "$out.$arch"
    parts+=("$out.$arch")
  done
  lipo -create "${parts[@]}" -output "$out"
  rm -f "${parts[@]}"
}

echo "▸ Compiling app (${ARCHS[*]})"
compile "$APP/Contents/MacOS/Planner" Shared/*.swift Core/*.swift App/*.swift

echo "▸ Compiling widget (${ARCHS[*]})"
# Extensions must enter through Foundation's NSExtensionMain (as Xcode links them),
# otherwise ExtensionKit can't identify the extension type and the process exits.
compile "$APPEX/Contents/MacOS/PlannerWidget" \
  -application-extension -module-name PlannerWidget \
  Shared/*.swift Widget/*.swift \
  -framework Foundation -framework AppIntents \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -Xlinker -application_extension

echo "▸ App Intents metadata (lets the widget's checkboxes work)"
python3 Resources/make_intents_metadata.py "$APPEX"

# Empty language folders tell macOS the app speaks Chinese and English, so its own menus
# (Edit, Window…) follow the language chosen in the app. App text comes from L().
for lang in zh-Hans en; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
  printf '/* App text is translated in Shared/English.swift */\n' > "$APP/Contents/Resources/$lang.lproj/Localizable.strings"
done

echo "▸ Icon"
swift Resources/make_icon.swift "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>Planner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>BPUpdateRepo</key><string>$UPDATE_REPO</string>
</dict></plist>
EOF

cat > "$APPEX/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$WIDGET_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleName</key><string>PlannerWidget</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>PlannerWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict></plist>
EOF

# Widgets must be sandboxed; grant access to the data folders (read-write, so ticking
# tasks on the widget can save): the local one and the iCloud Drive one used by sync.
cat > "$BUILD/widget.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
  <array>
    <string>/Library/Application Support/Planner/</string>
    <string>/Library/Mobile Documents/com~apple~CloudDocs/Best Planner/</string>
  </array>
</dict></plist>
EOF

echo "▸ Signing (ad-hoc)"
codesign --force --sign - --entitlements "$BUILD/widget.entitlements" "$APPEX"
codesign --force --sign - "$APP"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "$MODE" = "release" ]; then
  mkdir -p dist
  ZIP="dist/BestPlanner-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
  # Checksum for the in-app one-click update (it refuses a zip that doesn't match).
  shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"
  $LSREGISTER -u "$APP" 2>/dev/null || true
  rm -rf "$BUILD"
  echo "✓ Release: $ZIP ($(lipo -archs "$APP/Contents/MacOS/Planner" 2>/dev/null || echo "${ARCHS[*]}"))"
  exit 0
fi

echo "▸ Installing to /Applications"
# Quit normally first so the app saves any last edit, then make sure it's gone.
osascript -e 'tell application id "'$APP_ID'" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x Planner 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP" /Applications/
$LSREGISTER -f "/Applications/$APP_NAME.app"
pluginkit -a "/Applications/$APP_NAME.app/Contents/PlugIns/PlannerWidget.appex" 2>/dev/null || true
# A widget process still running the previous build would keep the old layout.
pkill -x PlannerWidget 2>/dev/null || true

# Clean up the intermediate copy so only the installed app stays registered.
$LSREGISTER -u "$APP" 2>/dev/null || true
rm -rf "$BUILD"

echo "✓ Done: /Applications/$APP_NAME.app ($VERSION)"
