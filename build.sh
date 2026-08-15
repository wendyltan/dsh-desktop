#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "== 编译 dshctl =="
swiftc -swift-version 5 \
  Sources/dshctl.swift Sources/Models.swift Sources/Utils.swift \
  Sources/ServerManager.swift Sources/BalanceService.swift Sources/MarketplaceService.swift \
  Sources/PluginService.swift Sources/RemoteService.swift Sources/UpdateChecker.swift \
  -o bin/dshctl

echo "== 编译 GUI =="
swiftc -swift-version 5 \
  Sources/App.swift Sources/AppStore.swift Sources/WebView.swift Sources/TopBar.swift Sources/PluginSheets.swift \
  Sources/Models.swift Sources/Utils.swift Sources/ServerManager.swift \
  Sources/BalanceService.swift Sources/MarketplaceService.swift Sources/LocalizeService.swift \
  Sources/PluginService.swift Sources/RemoteService.swift Sources/AppSettings.swift \
  Sources/UpdateChecker.swift \
  -o bin/DeepSeekHarness -framework WebKit -framework SwiftUI -framework AppKit

echo "== 组装 .app =="
APP="$ROOT/DeepSeek Harness.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp bin/DeepSeekHarness "$APP/Contents/MacOS/DeepSeekHarness"
cp Info.plist "$APP/Contents/Info.plist"

echo "== 生成图标 =="
if swift -swift-version 5 Scripts/gen-icon.swift "$ROOT/bin/icon.png" 2>/dev/null; then
  ICONSET="$ROOT/bin/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s bin/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
    d=$((s * 2))
    sips -z $d $d bin/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null && echo "  图标 OK"
else
  echo "  (图标生成跳过，使用默认图标)"
fi

echo "== 签名 =="
codesign --force --deep --sign - "$APP"

# 安装到内置 /Applications（真实 App，不是符号链接）。
# 关键：macOS 的 Launchpad / Finder「应用程序」搜索不会索引外接磁盘上的 App，
# 所以放在 SSD 只能靠「聚焦」搜到。本 App 仅 ~1MB，放内置盘几乎不占空间，
# 却能同时被 Spotlight、Launchpad、Finder「应用程序」搜到并运行。
APPS="/Applications/DeepSeek Harness.app"

rm -rf "$APPS" 2>/dev/null || true
ditto "$APP" "$APPS"
codesign --force --deep --sign - "$APPS"
xattr -dr com.apple.quarantine "$APPS" 2>/dev/null || true

# 清理旧的 SSD 副本 / 符号链接 / 桌面副本
rm -rf "/Volumes/ExtSSD/Application/DeepSeek Harness.app" 2>/dev/null || true
rm -rf "$HOME/Desktop/DeepSeek Harness.app" 2>/dev/null || true

mdimport "$APPS" 2>/dev/null || true

echo ""
echo "完成：$APPS"
echo "Spotlight / Launchpad / Finder「应用程序」均可搜到并运行"
echo "可把 dshctl 加入 PATH：ln -sf \"$ROOT/bin/dshctl\" /usr/local/bin/dshctl"
