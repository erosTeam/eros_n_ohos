#!/bin/bash
# dev.sh - 鸿蒙开发一键脚本
#
# 用法:
#   bash dev.sh                   # debug 构建 + 签名 + 安装到缓存/选择的设备
#   bash dev.sh -d all            # 安装到所有已连接设备（并刷新缓存时效）
#   bash dev.sh -d <device>       # 安装到指定设备（不影响缓存）
#   bash dev.sh --release         # release 构建 + 签名 + 安装
#   bash dev.sh --profile         # profile 构建 + 签名 + 安装
#   bash dev.sh --no-build        # 跳过构建，直接签名安装（沿用上次产物）
#   bash dev.sh --force-profile   # 强制重建证书和 Profile
#   bash dev.sh --attach          # 连接 flutter 调试器（debug/profile 模式）
#   bash dev.sh --log             # 实时查看设备上的 Dart 日志
#   bash dev.sh --refresh         # 强制刷新证书和 Profile（同 --force-profile）
#   bash dev.sh -h | --help       # 显示此帮助
#
# 设备缓存:
#   首次运行若检测到多设备会交互提示选择，结果缓存 7 天。
#   缓存期内不带 -d 参数时自动使用上次选择的设备并刷新缓存时效。
#   -d all 时安装到全部设备，缓存设备在线则同步刷新其缓存时效。

set -e
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDC=/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc
BUNDLE=com.erosteam.erosn
LOG_HOST=/data/app/el2/100/base/$BUNDLE/haps/entry/files/debug.log

case "$1" in
  -h|--help)
    cat <<'EOF'
dev.sh - 鸿蒙开发一键脚本

用法:
  bash dev.sh                   debug 构建 + 签名 + 安装到缓存/选择的设备
  bash dev.sh -d all            安装到所有已连接设备（并刷新缓存时效）
  bash dev.sh -d <device>       安装到指定设备（不影响缓存）
  bash dev.sh --release         release 构建 + 签名 + 安装
  bash dev.sh --profile         profile 构建 + 签名 + 安装
  bash dev.sh --no-build        跳过构建，直接签名安装（沿用上次产物）
  bash dev.sh --force-profile   强制重建证书和 Profile
  bash dev.sh --attach          连接 Flutter 调试器（debug/profile 模式）
  bash dev.sh --log             实时查看设备上的 Dart 日志
  bash dev.sh --refresh         强制刷新证书和 Profile（同 --force-profile）
  bash dev.sh -h | --help       显示此帮助

设备缓存:
  首次运行若检测到多设备会交互提示选择，结果缓存 7 天。
  缓存期内不带 -d 参数时自动使用上次选择的设备并刷新缓存时效。
  -d all 时安装到全部设备，缓存设备在线则同步刷新其缓存时效。
EOF
    ;;
  --attach)
    echo "==> Attaching Flutter debugger (debug/profile only)..."
    cd "$PROJ"
    fvm flutter attach
    ;;
  --log)
    # 通过 hdc shell 读取 debug.log 增量输出，每 0.5s 轮询一次
    echo "==> Streaming app logs (Ctrl+C to stop)..."
    echo "    log file: $LOG_HOST"
    LAST=0
    while true; do
      OUT=$("$HDC" shell "stat -c %s $LOG_HOST 2>/dev/null || echo 0" | tr -d '[:space:]\r')
      if [[ "$OUT" =~ ^[0-9]+$ ]] && [ "$OUT" -gt "$LAST" ]; then
        "$HDC" shell "dd if=$LOG_HOST bs=1 skip=$LAST count=$((OUT - LAST)) 2>/dev/null"
        LAST=$OUT
      fi
      sleep 0.5
    done
    ;;
  --refresh)
    # 同 --force-profile：删除本地证书文件，强制从 AGC 重新申请
    echo "==> Force-refreshing certificate and profile..."
    rm -f "$PROJ/ohos/sign/xiaobai-debug.cer" "$PROJ/ohos/sign/xiaobai-debug.p7b"
    python3 "$PROJ/scripts/huawei_sign.py" --no-build --force-profile
    ;;
  *)
    # 唤醒屏幕并延长息屏时间；由 Python 脚本在确定目标设备后执行
    python3 "$PROJ/scripts/huawei_sign.py" "$@"
    ;;
esac
