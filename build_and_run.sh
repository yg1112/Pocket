#!/bin/bash

# Pocket 构建和运行脚本
# macOS 版本用于测试

set -e

cd "$(dirname "$0")"

echo "🚀 Pocket 构建脚本"
echo "================================"
echo ""

# 1. 使用 XcodeGen 生成项目
echo "1️⃣  生成 Xcode 项目..."
xcodegen generate
echo "   ✅ 完成"
echo ""

# 2. 清理旧构建
echo "2️⃣  清理旧构建..."
xcodebuild clean -project Pocket.xcodeproj -scheme Pocket -configuration Debug > /dev/null 2>&1 || true
echo "   ✅ 完成"
echo ""

# 3. 构建项目
echo "3️⃣  构建项目..."
BUILD_LOG="/tmp/pocket_build.log"
xcodebuild -project Pocket.xcodeproj -scheme Pocket -configuration Debug build 2>&1 | tee "$BUILD_LOG"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "   ✅ 构建成功"
else
    echo ""
    echo "   ❌ 构建失败，查看日志："
    tail -50 "$BUILD_LOG"
    exit 1
fi
echo ""

# 4. 找到构建的 App
echo "4️⃣  查找构建产物..."
POCKET_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Pocket.app" -type d 2>/dev/null | head -1)

if [ -z "$POCKET_APP" ]; then
    echo "   ❌ 找不到 Pocket.app"
    exit 1
fi
echo "   📍 $POCKET_APP"
echo ""

# 5. 验证 Bundle
echo "5️⃣  验证 App Bundle..."
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$POCKET_APP/Contents/Info.plist" 2>/dev/null)

if [ -n "$BUNDLE_ID" ]; then
    echo "   ✅ Bundle ID: $BUNDLE_ID"
else
    echo "   ⚠️  Bundle ID 可能缺失"
fi
echo ""

# 6. 启动 App
echo "6️⃣  启动 Pocket..."
pkill -9 Pocket 2>/dev/null || true
sleep 1
open "$POCKET_APP"
echo "   ✅ App 已启动"
echo ""

echo "================================"
echo "✅ 完成！"
echo ""
echo "📍 App 位置:"
echo "   $POCKET_APP"
echo ""
