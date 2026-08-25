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
  Sources/UpdateChecker.swift Sources/GuardianService.swift \
  Sources/ServerManager.swift Sources/Utils.swift \
  Tests/UpdateCheckerTests.swift -o bin/updatechecker-tests
"$ROOT/bin/updatechecker-tests"

echo "== Guardian 集成验证 =="
node Guardian/verify.mjs

echo "== git 白空格检查 =="
git diff --check
