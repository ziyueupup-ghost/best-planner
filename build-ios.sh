#!/bin/zsh
# Builds the iPhone app (with its home-screen widget) without an Xcode project.
# Needs Xcode installed (for the iOS SDK and simulator).
#   ./build-ios.sh sim   build for the iOS Simulator, install and launch it there
#   ./build-ios.sh ipa   build for iPhone and package dist/BestPlanner-iOS-<version>.ipa
#                        (unsigned for distribution; SideStore/AltStore sign it with
#                        your Apple ID when installing)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' build.sh)"
MODE="${1:-sim}"
APP_ID="com.bestplanner.app"
WIDGET_ID="$APP_ID.widget"
APP_GROUP="group.com.bestplanner.app"
IOS_MIN="17.0"
BUILD="build-ios"
APP="$BUILD/Best Planner.app"
APPEX="$APP/PlugIns/PlannerWidget.appex"

case "$MODE" in
  sim) SDK=iphonesimulator; TARGET="arm64-apple-ios$IOS_MIN-simulator"; PLATFORM=iPhoneSimulator ;;
  ipa) SDK=iphoneos; TARGET="arm64-apple-ios$IOS_MIN"; PLATFORM=iPhoneOS ;;
  *) echo "usage: $0 sim|ipa"; exit 1 ;;
esac
SDK_PATH="$(xcrun --sdk $SDK --show-sdk-path)"
SWIFTC=(xcrun --sdk $SDK swiftc -O -target "$TARGET" -sdk "$SDK_PATH")

rm -rf "$BUILD"
mkdir -p "$APPEX"

# The app and the widget share their data through the app group container.
cat > "$BUILD/group.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>$APP_GROUP</string></array>
</dict></plist>
EOF
# The simulator reads entitlements from a section inside the binary, not the signature.
if [ "$MODE" = "sim" ]; then
  SWIFTC+=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$BUILD/group.entitlements")
fi

echo "▸ Compiling app ($SDK)"
"${SWIFTC[@]}" -parse-as-library -module-name BestPlanner \
  Shared/*.swift Core/*.swift iOS/*.swift -o "$APP/BestPlanner"

echo "▸ Compiling widget ($SDK)"
"${SWIFTC[@]}" -parse-as-library -application-extension -module-name PlannerWidget \
  Shared/*.swift Widget/*.swift \
  -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -application_extension \
  -o "$APPEX/PlannerWidget"

echo "▸ App Intents metadata (lets the widget's checkboxes work)"
python3 Resources/make_intents_metadata.py "$APPEX"

echo "▸ Icon"
swift Resources/make_icon.swift "$APP" ios

for lang in zh-Hans en; do
  mkdir -p "$APP/$lang.lproj"
  printf '/* App text is translated in Shared/English.swift */\n' > "$APP/$lang.lproj/Localizable.strings"
done

common_keys() {
  cat <<EOF
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
  <key>CFBundleSupportedPlatforms</key><array><string>$PLATFORM</string></array>
  <key>MinimumOSVersion</key><string>$IOS_MIN</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>DTPlatformName</key><string>$SDK</string>
  <key>ALTAppGroups</key><array><string>$APP_GROUP</string></array>
EOF
}

cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleName</key><string>Best Planner</string>
  <key>CFBundleDisplayName</key><string>Best Planner</string>
  <key>CFBundleExecutable</key><string>BestPlanner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
$(common_keys)
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key><dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
  </dict>
  <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
  <key>CFBundleIcons</key><dict>
    <key>CFBundlePrimaryIcon</key><dict>
      <key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array>
    </dict>
  </dict>
</dict></plist>
EOF

cat > "$APPEX/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$WIDGET_ID</string>
  <key>CFBundleName</key><string>PlannerWidget</string>
  <key>CFBundleDisplayName</key><string>Best Planner</string>
  <key>CFBundleExecutable</key><string>PlannerWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
$(common_keys)
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict></plist>
EOF

echo "▸ Signing (ad-hoc)"
codesign --force --sign - --entitlements "$BUILD/group.entitlements" "$APPEX"
codesign --force --sign - --entitlements "$BUILD/group.entitlements" "$APP"

if [ "$MODE" = "sim" ]; then
  DEVICE="$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)"
  if [ -z "$DEVICE" ]; then
    DEVICE="$(xcrun simctl list devices available | grep -E 'iPhone [0-9]+ Pro Max \(' | head -1 | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p')"
    if [ -z "$DEVICE" ]; then
      # None yet: make one on the newest iOS runtime that has a Pro Max.
      TYPE="$(xcrun simctl list devicetypes | grep -E 'iPhone [0-9]+ Pro Max' | tail -1 | sed -n 's/.*(\(com\.apple[^)]*\)).*/\1/p')"
      for RUNTIME in $(xcrun simctl list runtimes available | sed -n 's/.* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS[^ ]*\).*/\1/p' | sort -r); do
        DEVICE="$(xcrun simctl create "iPhone Pro Max" "$TYPE" "$RUNTIME" 2>/dev/null)" && break
      done
    fi
    xcrun simctl boot "$DEVICE"
  fi
  xcrun simctl terminate "$DEVICE" "$APP_ID" 2>/dev/null || true
  xcrun simctl install "$DEVICE" "$APP"
  xcrun simctl launch "$DEVICE" "$APP_ID"
  echo "✓ Running in the simulator ($DEVICE)"
else
  mkdir -p dist "$BUILD/Payload"
  cp -R "$APP" "$BUILD/Payload/"
  IPA="dist/BestPlanner-iOS-$VERSION.ipa"
  rm -f "$IPA"
  (cd "$BUILD" && zip -qry "../$IPA" Payload)
  echo "✓ $IPA"
fi
