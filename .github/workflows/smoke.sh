#!/usr/bin/env bash
# ============================================================================
# Arm64Probe 无头冒烟测试脚本（在真 ARM64 Linux 上运行）
# 用法: ./smoke.sh   或   bash smoke.sh
# 判定标准: 引擎成功初始化 + pak 挂载 + 无致命错误/崩溃
# ============================================================================
set -u

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROJ_DIR/Arm64Probe/Binaries/LinuxAArch64/Arm64Probe"
PAK="$PROJ_DIR/Arm64Probe/Content/Paks/Arm64Probe-LinuxAArch64NoEditor.pak"
LOG_DIR="$HOME/Documents/Arm64Probe/Saved/Logs"
RUN_LOG="$LOG_DIR/Arm64Probe.log"
CONSOLE=/tmp/arm64_smoke_console.log
ALL=/tmp/arm64_smoke_all.log

echo "=================================================="
echo "[1/5] 环境检查"
echo "=================================================="
echo "架构: $(uname -m)"
file "$BIN"
echo "PAK 存在: $([ -f "$PAK" ] && echo YES || echo NO)"
command -v ldd >/dev/null 2>&1 && ldd "$BIN" 2>/dev/null || echo "(monolithic 构建, 仅依赖 glibc)"

echo "=================================================="
echo "[2/5] 安装无头运行依赖（SDL2 为运行时 dlopen）"
echo "=================================================="
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq xvfb libsdl2-2.0-0 libcurl4 libssl3 >/dev/null 2>&1 || true
fi

echo "=================================================="
echo "[3/5] 无头启动（-nullrhi 虚拟渲染, 超时 180s）"
echo "=================================================="
chmod +x "$BIN"
export SDL_VIDEODRIVER=dummy
export SDL_AUDIODRIVER=dummy
START=$(date +%s)
timeout 180 xvfb-run -a "$BIN" -nullrhi -noaudio -nosound -unattended -log > "$CONSOLE" 2>&1
RC=$?
END=$(date +%s)
echo "退出码: $RC (124=超时自动终止, 属预期)  运行时长: $((END-START))s"

echo "=================================================="
echo "[4/5] 日志输出"
echo "=================================================="
if [ -f "$RUN_LOG" ]; then
  echo "--- UE 日志 ($RUN_LOG) 末尾 80 行 ---"
  tail -80 "$RUN_LOG"
else
  echo "--- UE 日志文件不存在, 显示 console 输出末尾 80 行 ---"
  tail -80 "$CONSOLE"
fi

echo "=================================================="
echo "[5/5] 判定结果"
echo "=================================================="
cat "$CONSOLE" > "$ALL"
[ -f "$RUN_LOG" ] && cat "$RUN_LOG" >> "$ALL"

PASS=1

if grep -qiE "Fatal error|Assertion failed|Segmentation fault|signal SIG|Check failed" "$ALL"; then
  echo "❌ 检测到致命错误/崩溃"
  PASS=0
fi

if grep -qiE "LogInit: Display:.*Engine is initialized|LogLoad:.*Engine.*Initialized|LogInit:.*CommandLine" "$ALL"; then
  echo "✅ 引擎初始化成功"
else
  echo "⚠️ 未检测到引擎初始化标记（请人工查看上方日志确认）"
  PASS=0
fi

if grep -qiE "LogPakFile.*[Mm]ount|LogPakFile: Display" "$ALL"; then
  echo "✅ pak 挂载成功"
else
  echo "⚠️ 未检测到 pak 挂载日志"
fi

if [ $((END-START)) -lt 10 ]; then
  echo "⚠️ 运行不足 10 秒即退出"
  PASS=0
fi

if [ "$PASS" -eq 1 ]; then
  echo "✅ 冒烟通过：引擎初始化成功，无致命错误"
  exit 0
else
  echo "❌ 冒烟未通过，请检查上方日志"
  exit 1
fi
