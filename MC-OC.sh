#!/bin/bash
# 严格模式：遇到错误立即退出，未定义变量报错
set -e

# 终端颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Minecraft Java版服务端环境配置脚本 ===${NC}"

# 1. 权限检查
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本 (例如: sudo bash $0)${NC}"
   exit 1
fi

# 2. 检测并安装下载工具
if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
  echo -e "${YELLOW}未找到 wget 或 curl，正在安装...${NC}"
  apt-get update -y && apt-get install -y wget
fi

# 3. 包管理器检测 (当前默认支持 Debian/Ubuntu)
if command -v apt-get &> /dev/null; then
  INSTALL_CMD="apt-get install -y"
  UPDATE_CMD="apt-get update -y"
else
  echo -e "${RED}当前仅自动支持 Debian/Ubuntu 系系统。${NC}"
  echo "请手动安装对应 OpenJDK 版本后，再运行此脚本跳过 Java 安装步骤。"
  exit 1
fi

echo -e "${YELLOW}正在更新软件包列表...${NC}"
$UPDATE_CMD

# 4. Java 版本选择菜单
echo ""
echo -e "${GREEN}请选择要安装的 Java 版本:${NC}"
echo "1) Java 8  (1.12.2 及更低版本推荐)"
echo "2) Java 11 (1.16.5 推荐)"
echo "3) Java 17 (1.18.2 ~ 1.20.4 推荐)"
echo "4) Java 21 (1.20.5 及更高版本推荐)"
echo "5) Java 25 (注: 尚未进入官方仓库，需手动安装)"
read -p "请输入数字 (1-5): " java_choice

case $java_choice in
  1) java_ver="8" ;;
  2) java_ver="11" ;;
  3) java_ver="17" ;;
  4) java_ver="21" ;;
  5) 
    echo -e "${YELLOW}Java 25 尚未在 APT 仓库发布。${NC}"
    echo "请手动下载 JDK 25 并配置 JAVA_HOME 环境变量后，直接运行此脚本下载服务端。"
    exit 0
    ;;
  *) echo -e "${RED}无效选择${NC}"; exit 1 ;;
esac

JAVA_PKG="openjdk-${java_ver}-jre-headless"
echo -e "${GREEN}正在安装 Java ${java_ver}...${NC}"
$INSTALL_CMD "$JAVA_PKG"
echo -e "${GREEN}Java ${java_ver} 安装完成。${NC}"

# 验证 Java
if command -v java &> /dev/null; then
  echo "当前 Java 版本:"
  java -version 2>&1 | head -n 1
else
  echo -e "${RED}Java 安装可能未成功，请检查上方日志。${NC}"
  exit 1
fi

# 5. Minecraft 服务端下载
echo ""
echo -e "${GREEN}=== 选择 Minecraft 服务端版本 ===${NC}"
echo -e "${YELLOW}⚠️ 默认为Leaves服务端！${NC}"

# ================= 🔧 用户配置区 🔧 =================
# 版本号列表 (按顺序对应下方的URL)
MC_VERSIONS=("1.21.8" "1.21.5" "1.21.1" "1.21.3")

# 对应的直链下载URL (请替换为实际有效的链接，保持顺序一致)
MC_URLS=(
  "https://api.leavesmc.org/v2/projects/leaves/versions/1.21.8/builds/138/downloads/application"
  "https://api.leavesmc.org/v2/projects/leaves/versions/1.21.5/builds/57/downloads/application"
  "https://example.com/minecraft/1.21.1/server.jar"
  "https://example.com/minecraft/1.21.3/server.jar"
)
# ====================================================

# 动态生成菜单
for i in "${!MC_VERSIONS[@]}"; do
  echo "$((i+1))) Minecraft ${MC_VERSIONS[$i]}"
done

read -p "请输入要下载的版本编号 (1-${#MC_VERSIONS[@]}): " mc_choice

# 输入校验
if ! [[ "$mc_choice" =~ ^[0-9]+$ ]] || [ "$mc_choice" -lt 1 ] || [ "$mc_choice" -gt "${#MC_VERSIONS[@]}" ]; then
  echo -e "${RED}无效选择${NC}"
  exit 1
fi

idx=$((mc_choice-1))
mc_ver="${MC_VERSIONS[$idx]}"
mc_url="${MC_URLS[$idx]}"

# 防止忘记替换占位符链接
if [[ "$mc_url" == *"example.com"* ]]; then
  echo -e "${RED}错误: 请修改脚本中的 MC_URLS 数组，替换为真实的下载链接！${NC}"
  exit 1
fi

# 检查是否已存在 server.jar
if [ -f "server.jar" ]; then
  read -p "当前目录已存在 server.jar，是否覆盖? (y/N): " overwrite
  if [[ "$overwrite" != [yY] && "$overwrite" != [yY][eE][sS] ]]; then
    echo "已取消下载。"
    exit 0
  fi
fi

echo -e "${GREEN}正在下载 Minecraft ${mc_ver} 服务端...${NC}"
wget -O "server.jar" "$mc_url"

if [ -f "server.jar" ] && [ -s "server.jar" ]; then
  echo -e "${GREEN}✅ 下载完成！文件已保存为 ./server.jar${NC}"
  echo -e "${YELLOW}📌 提示:${NC}"
  echo "   1. 首次运行请执行: java -jar server.jar"
  echo "   2. 服务器生成 eula.txt 后，请编辑该文件将 eula=false 改为 eula=true"
  echo "   3. 再次执行 java -jar server.jar 即可正常启动。"
else
  echo -e "${RED}❌ 下载失败或文件为空，请检查链接或网络。${NC}"
  rm -f server.jar
  exit 1
fi