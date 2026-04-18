#!/bin/bash
# =============================================================================
# Minecraft Java版服务端一键配置脚本（下载逻辑修复版）
# 修复：curl参数冲突 / 隐藏错误屏蔽 / CDN拦截 / 空文件校验
# 格式：Unix LF
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Minecraft 服务端配置脚本 (下载修复版)  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# 1. 权限检查
if [[ $EUID -ne 0 ]]; then
  log_error "请使用 sudo 运行: sudo bash $0"
  exit 1
fi

# 2. 包管理器检测
if command -v apt-get &> /dev/null; then
  PKG_MGR="apt"; INSTALL_CMD="apt-get install -y"; UPDATE_CMD="apt-get update -o Acquire::Retries=3"
elif command -v dnf &> /dev/null; then
  PKG_MGR="dnf"; INSTALL_CMD="dnf install -y"; UPDATE_CMD="dnf check-update -y || true"
elif command -v yum &> /dev/null; then
  PKG_MGR="yum"; INSTALL_CMD="yum install -y"; UPDATE_CMD="yum check-update -y || true"
else
  log_error "未检测到支持的包管理器 (apt/dnf/yum)"; exit 1
fi
log_info "包管理器: $PKG_MGR"

# 3. 安装下载工具
if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
  log_warn "安装下载工具中..."
  $UPDATE_CMD >/dev/null 2>&1
  $INSTALL_CMD wget curl >/dev/null 2>&1 || { log_error "无法安装 wget/curl"; exit 1; }
fi

# 4. 更新软件源（容错）
log_step "更新软件源..."
$UPDATE_CMD >/dev/null 2>&1 && log_info "更新完成" || log_warn "部分源更新失败（不影响Java安装）"

# 5. Java 选择
echo ""
log_step "选择 Java 版本:"
echo "   1) Java 8   ── 1.12.2-"
echo "   2) Java 11  ── 1.16.5"
echo "   3) Java 17  ── 1.18.2~1.20.4"
echo "   4) Java 21  ── 1.20.5+"
echo "   5) Java 25  ── 需手动安装"
read -p "▶ 输入数字 (1-5): " java_choice
case $java_choice in
  1) java_ver="8";  java_pkg="openjdk-8-jre-headless" ;;
  2) java_ver="11"; java_pkg="openjdk-11-jre-headless" ;;
  3) java_ver="17"; java_pkg="openjdk-17-jre-headless" ;;
  4) java_ver="21"; java_pkg="openjdk-21-jre-headless" ;;
  5) log_warn "Java 25 需手动安装后重运行"; exit 0 ;;
  *) log_error "无效输入"; exit 1 ;;
esac

log_step "安装 Java $java_ver ..."
if ! $INSTALL_CMD "$java_pkg" >/dev/null 2>&1; then
  alt_pkg=$([[ "$PKG_MGR" == "apt" ]] && echo "openjdk-${java_ver}-jdk-headless" || echo "java-${java_ver}-openjdk-headless")
  $INSTALL_CMD "$alt_pkg" >/dev/null 2>&1 || { log_error "Java 安装失败，请手动执行: sudo $INSTALL_CMD $java_pkg"; exit 1; }
fi
java -version 2>&1 | head -n1 | grep -q "$java_ver" && log_info "✓ Java $java_ver 就绪" || log_warn "Java 版本非预期，但可继续"

# 6. Minecraft 下载配置
echo ""
log_step "=== 选择 Minecraft 服务端版本 ==="
log_warn "能用就行。"

# ==================== 🔧 用户配置区 🔧 ====================
MC_VERSIONS=("1.21.11Paper" "1.20.4" "1.21" "1.21.1" "1.21.3")
# ⚠️ 请替换为你的真实直链（保持顺序一致）
MC_URLS=(
  "https://fill-data.papermc.io/v1/objects/25eb85bd8415195ce4bc188e1939e0c7cef77fb51d26d4e766407ee922561097/paper-1.21.11-130.jar"
  "https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar"
  "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"
  "https://piston-data.mojang.com/v1/objects/59353fb40c36d304f2035d51e7d6e6baa98dc05c/server.jar"
  "https://piston-data.mojang.com/v1/objects/PLACEHOLDER/server.jar"
)
# =========================================================

for i in "${!MC_VERSIONS[@]}"; do printf "   %d) Minecraft %s\n" "$((i+1))" "${MC_VERSIONS[$i]}"; done
read -p "▶ 输入版本编号 (1-${#MC_VERSIONS[@]}): " mc_choice
if ! [[ "$mc_choice" =~ ^[0-9]+$ ]] || [ "$mc_choice" -lt 1 ] || [ "$mc_choice" -gt "${#MC_VERSIONS[@]}" ]; then
  log_error "无效选择"; exit 1
fi

idx=$((mc_choice - 1))
mc_ver="${MC_VERSIONS[$idx]}"
mc_url="${MC_URLS[$idx]}"

if [[ "$mc_url" == *"PLACEHOLDER"* ]]; then
  log_error "检测到未替换的占位链接！请在脚本『用户配置区』填写 $mc_ver 的真实直链"
  exit 1
fi

if [ -f "server.jar" ]; then
  read -p "⚠️ 已存在 server.jar，是否覆盖? (y/N): " ov
  [[ "$ov" =~ ^[yY]([eE][sS])?$ ]] || { log_info "已取消"; exit 0; }
  rm -f server.jar
fi

# 7. 核心下载逻辑（已修复）
log_step "下载 Minecraft $mc_ver ..."
max_retries=2
retry=0
while [ $retry -le $max_retries ]; do
  # 统一使用带 UA 头的下载命令，修复 curl -O/-o 冲突
  if command -v wget &> /dev/null; then
    wget --no-verbose --show-progress --no-check-certificate \
         --timeout=30 --tries=1 --user-agent="MC-Server-Setup/1.0" \
         -O "server.jar" "$mc_url" 2>&1
    exit_code=$?
  elif command -v curl &> /dev/null; then
    curl --fail --location --connect-timeout 30 --max-time 120 \
         --user-agent "MC-Server-Setup/1.0" -o "server.jar" "$mc_url" 2>&1
    exit_code=$?
  else
    log_error "未找到 wget 或 curl"; exit 1
  fi

  if [ $exit_code -eq 0 ] && [ -s "server.jar" ]; then
    break
  fi

  retry=$((retry + 1))
  log_warn "第 $retry 次下载失败。错误信息已打印，请检查链接或网络..."
  sleep 2
done

# 最终校验
if [ -f "server.jar" ] && [ -s "server.jar" ]; then
  # 简单验证是否为 Java 文件（非 HTML 错误页）
  file_type=$(file server.jar | grep -i "java archive\|zip\|data")
  if [ -z "$file_type" ]; then
    log_error "下载的文件不是有效的 JAR 包（可能是 HTML 错误页）"
    echo "🔍 请手动测试链接: curl -I \"$mc_url\""
    rm -f server.jar
    exit 1
  fi
  log_info "✅ 下载成功! $(du -h server.jar | cut -f1)"
  echo ""
  echo -e "${GREEN}📌 下一步:${NC}"
  echo "   1️⃣  java -Xmx2G -jar server.jar nogui  (首次运行)"
  echo "   2️⃣  编辑 eula.txt → eula=true"
  echo "   3️⃣  java -Xmx4G -Xms2G -XX:+UseG1GC -jar server.jar nogui"
else
  log_error "下载彻底失败。请复制上方红色错误信息排查。"
  echo "💡 常见原因: 链接失效 / 403拦截 / 磁盘已满 / 网络不通"
  rm -f server.jar
  exit 1
fi
log_info "🎉 配置完成"
