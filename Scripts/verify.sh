#!/bin/zsh
# 开发验证：编译并运行 Swift 单元断言 + Guardian 集成验证 + git 白空格检查。
# Guardian 集成验证使用隔离的临时 DSH_HOME，不会触碰本机真实服务。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p bin/bin-cache

echo "== 桌面端 / 保护组件版本一致性 =="
DESKTOP_VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
GUARDIAN_VERSION="$(sed -nE "s/^const GUARDIAN_VERSION = '([^']+)'/\\1/p" Guardian/guardian.mjs)"
if [ -z "$GUARDIAN_VERSION" ] || [ "$DESKTOP_VERSION" != "$GUARDIAN_VERSION" ]; then
  echo "版本不一致：desktop=$DESKTOP_VERSION guardian=$GUARDIAN_VERSION" >&2
  exit 1
fi
echo "PASS  desktop=$DESKTOP_VERSION guardian=$GUARDIAN_VERSION"

echo "== UpdateChecker / shellQuote 单测 =="
swiftc -module-cache-path "$ROOT/bin/bin-cache" -swift-version 5 \
  Sources/Models.swift Sources/UpdateChecker.swift Sources/GuardianService.swift \
  Sources/ServerManager.swift Sources/Utils.swift \
  Tests/UpdateCheckerTests.swift -o bin/updatechecker-tests
DSH_HOME="$ROOT/bin/verification-home" "$ROOT/bin/updatechecker-tests"

echo "== DeepSeek 凭据读取单测 =="
swiftc -module-cache-path "$ROOT/bin/bin-cache" -swift-version 5 \
  Sources/Models.swift Sources/Utils.swift Sources/BalanceService.swift \
  Tests/BalanceServiceTests.swift -o bin/balance-tests
BALANCE_TEST_HOME="$(mktemp -d)"
DSH_HOME="$BALANCE_TEST_HOME" "$ROOT/bin/balance-tests"
rmdir "$BALANCE_TEST_HOME"

echo "== Harness 桥接验证 =="
node HarnessBridge/verify.mjs
node --test HarnessBridge/test/client-navigation.test.mjs
node Scripts/verify-install-bridge.mjs

echo "== 原生事件桥验证 =="
swiftc -module-cache-path "$ROOT/bin/bin-cache" -swift-version 5 \
  Sources/EventBridge.swift Bridge/Verify.swift -framework Network -o bin/bridge-tests
DSH_DESKTOP_BRIDGE_PORT=13991 "$ROOT/bin/bridge-tests"

echo "== WKWebView 文档导航生命周期回归 =="
WEBVIEW_SMOKE_ROOT="$(mktemp -d "$ROOT/.test-home/webview-navigation.XXXXXX")"
WEBVIEW_SERVER_PID=""
cleanup_webview_smoke() {
  if [ -n "$WEBVIEW_SERVER_PID" ]; then kill "$WEBVIEW_SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$WEBVIEW_SMOKE_ROOT"
  rm -f "$ROOT/bin/webview-navigation-tests" "$ROOT/bin/webview-navigation-server.log"
}
trap cleanup_webview_smoke EXIT
cp "$ROOT/Tests/webview-smoke/navigation.html" "$WEBVIEW_SMOKE_ROOT/navigation.html"
cp "$ROOT/Tests/webview-smoke/navigation-target.html" "$WEBVIEW_SMOKE_ROOT/navigation-target.html"
swiftc -module-cache-path "$ROOT/bin/bin-cache" -swift-version 5 \
  Tests/WebViewNavigationTests.swift Sources/WebView.swift Sources/Models.swift \
  -framework SwiftUI -framework WebKit -framework AppKit -o bin/webview-navigation-tests
DSH_WEBVIEW_SMOKE_ROOT="$WEBVIEW_SMOKE_ROOT" DSH_WEBVIEW_SMOKE_PORT=13992 node Scripts/webview-smoke-server.mjs > "$ROOT/bin/webview-navigation-server.log" 2>&1 &
WEBVIEW_SERVER_PID=$!
WEBVIEW_SERVER_READY=false
for attempt in {1..40}; do
  if curl --silent --fail http://127.0.0.1:13992/navigation.html >/dev/null; then WEBVIEW_SERVER_READY=true; break; fi
  sleep 0.1
done
if [ "$WEBVIEW_SERVER_READY" != true ]; then
  echo "WKWebView smoke server did not start" >&2
  exit 1
fi
DSH_WEBVIEW_SMOKE_PORT=13992 bin/webview-navigation-tests
cleanup_webview_smoke
trap - EXIT

echo "== 快速提问会话状态单测 =="
swiftc -module-cache-path "$ROOT/bin/bin-cache" -swift-version 5 \
  Sources/QuickPromptPanel.swift Tests/QuickPromptPanelTests.swift -o bin/quick-prompt-tests
bin/quick-prompt-tests

echo "== 全局快捷键事务与键名验证 =="
swiftc -module-cache-path "$ROOT/bin/bin-cache" -swift-version 5 \
  Sources/GlobalHotKey.swift Tests/GlobalHotKeyTests.swift \
  -framework Carbon -framework AppKit -o bin/global-hotkey-tests
bin/global-hotkey-tests

echo "== Guardian 集成验证 =="
node Guardian/verify.mjs
if [ "${1:-}" = "--installed-engines" ]; then
  echo "== 已安装内核的真实跨版本兼容验收 =="
  node Scripts/verify-session-compatibility.mjs
fi

echo "== git 白空格检查 =="
git diff --check
