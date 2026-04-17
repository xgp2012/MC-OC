#!/bin/bash

# 定义下载地址
URL1="https://github.com/xgp2012/MC-OC/raw/refs/heads/main/MC-OC-qz.sh"
URL2="https://github.com/xgp2012/MC-OC/raw/refs/heads/main/MC-OC.sh"

# 定义保存的文件名
FILE1="MC-OC-qz.sh"
FILE2="MC-OC.sh"

echo "===== 开始下载脚本文件 ====="

# 下载文件（优先使用wget，没有则自动用curl）
if command -v wget &> /dev/null; then
    wget -O "$FILE1" "$URL1"
    wget -O "$FILE2" "$URL2"
else
    curl -o "$FILE1" "$URL1"
    curl -o "$FILE2" "$URL2"
fi

echo "===== 赋予文件可执行权限 ====="
# 给两个脚本添加运行权限
chmod +x "$FILE1" "$FILE2"

echo "===== 操作完成！ ====="
echo "已下载文件：$FILE1 和 $FILE2"
echo "已设置可执行权限，可直接运行：./$FILE1 或 ./$FILE2"
