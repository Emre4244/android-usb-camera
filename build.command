#!/bin/zsh
set -eu
SOURCE_DIR="${0:A:h}"
RUNTIME_DIR="${1:-$SOURCE_DIR/.cache/scrcpy-macos-aarch64-v5.0}"
if [[ ! -f "$RUNTIME_DIR/scrcpy-server" || ! -x "$RUNTIME_DIR/adb" ]]; then
  mkdir -p "$SOURCE_DIR/.cache"
  ARCHIVE="$SOURCE_DIR/.cache/scrcpy-macos-aarch64-v5.0.tar.gz"
  curl -fL https://github.com/Genymobile/scrcpy/releases/download/v5.0/scrcpy-macos-aarch64-v5.0.tar.gz -o "$ARCHIVE"
  ACTUAL=$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)
  [[ "$ACTUAL" == "7cb4e41c859b05b36e89dc9be6c353cc5980c00d7f7f6a763b5b355551b82e9c" ]] || { print 'Runtime checksum mismatch'; exit 1; }
  tar -xzf "$ARCHIVE" -C "$SOURCE_DIR/.cache"
fi
BUILD_DIR=$(mktemp -d /tmp/android-camera-build.XXXXXX)
APP_DIR="$BUILD_DIR/Android USB Camera.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
swiftc -O -target arm64-apple-macos13.0 -parse-as-library "$SOURCE_DIR/ScreenReceiver.swift" \
  "$SOURCE_DIR/CameraSink.swift" "$SOURCE_DIR/BridgeMain.swift" \
  -o "$APP_DIR/Contents/MacOS/AndroidBridge"
for asset in adb scrcpy-server LICENSE; do
  ditto --norsrc --noextattr "$RUNTIME_DIR/$asset" "$APP_DIR/Contents/Resources/$asset"
done
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.androidusbcamera.bridge</string>
<key>CFBundleName</key><string>Android USB Camera</string>
<key>CFBundleExecutable</key><string>AndroidBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR/Contents/Resources/adb"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --keepParent --norsrc "$APP_DIR" "$SOURCE_DIR/../Android-USB-Camera-0.2.0-preview-arm64.zip"
print "Built: $APP_DIR"
print "Archive: $SOURCE_DIR/../Android-USB-Camera-0.2.0-preview-arm64.zip"
