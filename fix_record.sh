#!/bin/bash
# 强行修改 record 插件的底层代码，补上 compileSdkVersion
FIND_PATH=$(find ~/.pub-cache -path "*record_android*/android/build.gradle" | head -n 1)
if [ -n "$FIND_PATH" ]; then
    echo "找到文件: $FIND_PATH，正在修复..."
    sed -i 's/ext.flutter.compileSdkVersion/ext.flutter.compileSdkVersion ?: 35/g' "$FIND_PATH"
    sed -i 's/flutter.compileSdkVersion/flutter.compileSdkVersion ?: 35/g' "$FIND_PATH"
    echo "修复完成！"
else
    echo "没找到 record 插件文件！"
fi
