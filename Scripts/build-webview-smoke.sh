#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.test-home/WebView Smoke.app"
mkdir -p "$APP/Contents/MacOS" "$ROOT/.test-home/webview-smoke"
cp "$ROOT/Tests/webview-smoke/index.html" "$ROOT/.test-home/webview-smoke/index.html"
cp "$ROOT/Tests/webview-smoke/target.html" "$ROOT/.test-home/webview-smoke/target.html"
swiftc -module-cache-path "$ROOT/.test-home/swift-module-cache" -swift-version 5 \
  "$ROOT/Tests/WebViewSmoke.swift" "$ROOT/Sources/WebView.swift" \
  -o "$APP/Contents/MacOS/WebViewSmoke" \
  -framework SwiftUI -framework WebKit -framework AppKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WebViewSmoke</string>
<key>CFBundleIdentifier</key><string>com.dsh.desktop.webview-smoke</string>
<key>CFBundleName</key><string>dsh WebView Smoke</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
