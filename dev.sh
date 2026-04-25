#!/bin/bash
# dev.sh - 鸿蒙开发一键脚本
# 用法:
#   bash dev.sh             # 完整流程（构建+签名+安装）
#   bash dev.sh --no-build  # 跳过构建，直接签名安装
#   bash dev.sh --attach    # 连接 flutter 调试器
#   bash dev.sh --log       # 实时查看 Dart 日志
#   bash dev.sh --refresh   # 强制刷新证书和 Profile

set -e
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDC=/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc
BUNDLE=com.erosteam.erosn
LOG_FILE=/data/storage/el2/base/haps/entry/files/debug.log
LOG_HOST=/data/app/el2/100/base/$BUNDLE/haps/entry/files/debug.log

case "$1" in
  --attach)
    echo "==> Attaching Flutter debugger..."
    cd "$PROJ"
    fvm flutter attach
    ;;
  --log)
    echo "==> Streaming app logs (Ctrl+C to stop)..."
    echo "    log file: $LOG_HOST"
    LAST=0
    while true; do
      OUT=$("$HDC" shell "wc -c < $LOG_HOST 2>/dev/null || echo 0" | tr -d '[:space:]')
      if [ -n "$OUT" ] && [ "$OUT" -gt "$LAST" ]; then
        "$HDC" shell "dd if=$LOG_HOST bs=1 skip=$LAST 2>/dev/null"
        LAST=$OUT
      fi
      sleep 0.5
    done
    ;;
  --refresh)
    echo "==> Force-refreshing certificate and profile..."
    rm -f "$PROJ/ohos/sign/xiaobai-debug.cer" "$PROJ/ohos/sign/xiaobai-debug.p7b"
    python3 "$PROJ/scripts/huawei_sign.py" --no-build --force-profile
    ;;
  *)
    python3 "$PROJ/scripts/huawei_sign.py" "$@"
    ;;
esac
