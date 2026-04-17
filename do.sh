#!/bin/bash

URL1="https://github.com/xgp2012/MC-OC/raw/refs/heads/main/MC-OC-qz.sh"
URL2="https://github.com/xgp2012/MC-OC/raw/refs/heads/main/MC-OC.sh"
URL3="https://github.com/xgp2012/MC-OC/raw/refs/heads/main/start.sh"

FILE1="MC-OC-qz.sh"
FILE2="MC-OC.sh"
FILE3="start.sh"

echo "===== 开始下载配置脚本文件及启动脚本 ====="

if command -v wget &> /dev/null; then
    wget -O "$FILE1" "$URL1"
    wget -O "$FILE2" "$URL2"
    wget -O "$FILE3" "$URL3"
else
    curl -o "$FILE1" "$URL1"
    curl -o "$FILE2" "$URL2"
    curl -o "$FILE3" "$URL3"
fi

echo "===== 赋予文件可执行权限 ====="
chmod +x "$FILE1" "$FILE2" "$FILE3"

echo "===== 操作完成！ ====="
echo "已下载文件：$FILE1 和 $FILE2 $FILE3"
echo "已设置可执行权限，可直接运行：./$FILE1 或 ./$FILE2"
