#!/bin/zsh
# 开发验证：编译并运行 Swift 单元断言 + Guardian 集成验证 + git 白空格检查。
# Guardian 集成验证使用隔离的临时 DSH_HOME，不会触碰本机真实服务。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p bin/bin-cache

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
