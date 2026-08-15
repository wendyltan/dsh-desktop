#!/bin/zsh
# Tailscale 远程访问脚本（方案 A）
# 作用：
#   1. 确保 Tailscale 已运行并登录
#   2. 以 --trusted-host <ts.net 域名> 重启 harness 服务（放行 /api 浏览器信任围栏）
#   3. tailscale serve 把本机 :3080 以 HTTPS 暴露给 tailnet（仅你的设备可访问）
#   4. 打印并打开 https://<mac机器名>.<tailnet>.ts.net
# 用法：双击运行，或在终端执行；Tailscale 需先打开并登录。

set -u
HOME_DIR="$HOME/.dsh/dsh-desktop"
PORT="${DSH_WEB_PORT:-3080}"

TS="$(command -v tailscale)" || { echo "未找到 tailscale 命令"; exit 1; }
"$TS" status >/dev/null 2>&1 || {
  echo "Tailscale 未运行或未登录。请先打开 Tailscale 应用并登录，再运行本脚本。"
  exit 1
}

DNS=$("$TS" status --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d["Self"]["DNSName"].rstrip("."))
except Exception:
    pass' 2>/dev/null)
if [ -z "$DNS" ]; then
  echo "无法获取 tailnet 域名（tailscale status --json 解析失败）"
  exit 1
fi

echo "== 1. 重启 harness 服务（放行 $DNS） =="
export DSH_WEB_TRUSTED_HOSTS="$DNS"
"$HOME_DIR/stop.sh" >/dev/null 2>&1 || true
"$HOME_DIR/launch.sh" || exit 1

echo "== 2. tailscale serve 暴露 :$PORT（HTTPS） =="
OUT_FILE=/tmp/dsh-ts-serve.out
rm -f "$OUT_FILE"
"$TS" serve --bg "$PORT" > "$OUT_FILE" 2>&1 &
SP=$!
NOT_ENABLED=""
for _ in {1..15}; do
  if grep -q "Serve is not enabled" "$OUT_FILE" 2>/dev/null; then
    NOT_ENABLED=1
    break
  fi
  if ! kill -0 "$SP" 2>/dev/null; then break; fi
  sleep 1
done
kill "$SP" 2>/dev/null

if [ -n "$NOT_ENABLED" ]; then
  LINK=$(grep -oE "https://login\.tailscale\.com/f/serve\?node=[A-Za-z0-9]+" "$OUT_FILE" | head -1)
  echo "Tailscale 后台未启用 Serve（HTTPS）。"
  echo "请打开下面链接，在 Tailscale 控制台点「启用」（需登录你的 Tailscale 账号），然后重新运行本脚本："
  echo "$LINK"
  open "$LINK" 2>/dev/null || true
  exit 1
fi

URL="https://$DNS/"
echo ""
echo "已开启远程访问：$URL"
echo "手机浏览器打开即可（需手机 Tailscale 在线）；Safari 可「添加到主屏幕」当作 App。"
open "$URL" 2>/dev/null || true
