#!/bin/bash
# =============================================================================
# Minecraft Java版服务端一键配置脚本（增强容错版）
# 功能：选择安装 Java 8~21 + 自定义下载 Minecraft 服务端
# 格式：Unix LF 换行（避免 ^M 错误）
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }

# 标题
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Minecraft 服务端环境配置脚本 (增强版)  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# 1. 权限检查
# =============================================================================
if [[ $EUID -ne 0 ]]; then
  log_error "请使用 sudo 运行: sudo bash $0"
  exit 1
fi

# =============================================================================
# 2. 检测包管理器
# =============================================================================
if command -v apt-get &> /dev/null; then
  PKG_MGR="apt"
  INSTALL_CMD="apt-get install -y"
  UPDATE_CMD="apt-get update -o Acquire::Retries=3"
elif command -v dnf &> /dev/null; then
  PKG_MGR="dnf"
  INSTALL_CMD="dnf install -y"
  UPDATE_CMD="dnf check-update -y || true"
elif command -v yum &> /dev/null; then
  PKG_MGR="yum"
  INSTALL_CMD="yum install -y"
  UPDATE_CMD="yum check-update -y || true"
else
  log_error "未检测到支持的包管理器 (apt/dnf/yum)"
  exit 1
fi
log_info "检测到包管理器: $PKG_MGR"

# =============================================================================
# 3. 安装下载工具（容错：允许失败）
# =============================================================================
if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
  log_warn "未找到 wget/curl，尝试安装..."
  $UPDATE_CMD 2>/dev/null || log_warn "更新软件源失败，尝试继续..."
  $INSTALL_CMD wget 2>/dev/null || $INSTALL_CMD curl 2>/dev/null || {
    log_error "无法安装下载工具，请手动安装 wget 或 curl"
    exit 1
  }
fi
DOWNLOAD_CMD="wget -q --show-progress"
command -v curl &> /dev/null && DOWNLOAD_CMD="curl -fSL -O"

# =============================================================================
# 4. 更新软件源（增强容错：非致命错误不退出）
# =============================================================================
log_step "更新软件包索引..."
if ! $UPDATE_CMD 2>&1 | tee /tmp/apt_update.log | grep -q "Err\|Failed"; then
  log_info "软件源更新完成"
else
  log_warn "部分软件源更新失败（通常是第三方源），但不影响核心功能"
  log_warn "如后续安装 Java 失败，请手动运行: sudo $UPDATE_CMD"
fi

# =============================================================================
# 5. Java 版本选择菜单
# =============================================================================
echo ""
log_step "请选择要安装的 Java 版本:"
echo "   1) Java 8   ── Minecraft 1.12.2 及更早"
echo "   2) Java 11  ── Minecraft 1.16.5"
echo "   3) Java 17  ── Minecraft 1.18.2 ~ 1.20.4"
echo "   4) Java 21  ── Minecraft 1.20.5+"
echo "   5) Java 25  ── 手动安装（尚未进入官方仓库）"
echo ""
read -p "▶ 输入数字 (1-5): " java_choice

case $java_choice in
  1) java_ver="8";  java_pkg="openjdk-8-jre-headless" ;;
  2) java_ver="11"; java_pkg="openjdk-11-jre-headless" ;;
  3) java_ver="17"; java_pkg="openjdk-17-jre-headless" ;;
  4) java_ver="21"; java_pkg="openjdk-21-jre-headless" ;;
  5)
    log_warn "Java 25 尚未进入 $PKG_MGR 仓库"
    echo "请手动下载并安装 JDK 25，然后设置 JAVA_HOME 环境变量"
    echo "完成后重新运行此脚本，选择『跳过 Java 安装』流程（待实现）"
    exit 0
    ;;
  *) log_error "无效输入"; exit 1 ;;
esac

# =============================================================================
# 6. 安装 Java（带重试和回退）
# =============================================================================
log_step "安装 Java $java_ver ..."

# 尝试安装，失败时提供手动指导
if ! $INSTALL_CMD "$java_pkg" 2>/dev/null; then
  log_warn "自动安装失败，尝试备用方案..."
  
  # 尝试安装完整 JDK（部分系统仓库命名不同）
  if [[ "$PKG_MGR" == "apt" ]]; then
    alt_pkg="openjdk-${java_ver}-jdk-headless"
  else
    alt_pkg="java-${java_ver}-openjdk-headless"
  fi
  
  if $INSTALL_CMD "$alt_pkg" 2>/dev/null; then
    log_info "通过备用包名安装成功"
  else
    log_error "Java 安装失败"
    echo ""
    echo "🔧 手动安装指引:"
    if [[ "$PKG_MGR" == "apt" ]]; then
      echo "   sudo apt install $java_pkg"
    else
      echo "   sudo $PKG_MGR install $alt_pkg"
    fi
    echo "   或访问: https://adoptium.net 下载 tar.gz 手动安装"
    exit 1
  fi
fi

# 验证 Java
if command -v java &> /dev/null; then
  java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
  log_info "✓ Java 安装成功: $java_version"
else
  log_error "Java 安装后未找到 java 命令，请检查 PATH"
  exit 1
fi

# =============================================================================
# 7. Minecraft 服务端下载（🔧 用户自定义区域）
# =============================================================================
echo ""
log_step "=== 选择 Minecraft 服务端版本 ==="
log_warn "⚠️ 请确保下方数组中的下载链接为【直链】(非网页)"

# ==================== 🔧 用户配置区 🔧 ====================
# 版本号列表（按顺序）
MC_VERSIONS=(
  "1.20.1"
  "1.20.4"
  "1.21"
  "1.21.1"
  "1.21.3"
)

# 对应下载链接（请替换为你的真实直链，保持顺序一致）
# ✅ 示例：使用 BMCLAPI 加速（官方镜像）
# MC_URLS=(
#   "https://bmclapi2.bangbang93.com/version/1.20.1/server.jar"
#   "https://bmclapi2.bangbang93.com/version/1.20.4/server.jar"
#   "https://bmclapi2.bangbang93.com/version/1.21/server.jar"
#   "https://bmclapi2.bangbang93.com/version/1.21.1/server.jar"
#   "https://bmclapi2.bangbang93.com/version/1.21.3/server.jar"
# )

# 📌 或使用 Mojang 官方源（可能较慢）：
MC_URLS=(
  "https://piston-data.mojang.com/v1/objects/84194a2f286ef7c14ed7ce0090dba59902951555/server.jar"
  "https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar"
  "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"
  "https://piston-data.mojang.com/v1/objects/59353fb40c36d304f2035d51e7d6e6baa98dc05c/server.jar"
  "https://piston-data.mojang.com/v1/objects/5b9c3c0e3e6e5e5e5e5e5e5e5e5e5e5e5e5e5e5e/server.jar"
)
# =========================================================

# 动态显示菜单
for i in "${!MC_VERSIONS[@]}"; do
  printf "   %d) Minecraft %s\n" "$((i+1))" "${MC_VERSIONS[$i]}"
done
echo ""

read -p "▶ 输入版本编号 (1-${#MC_VERSIONS[@]}): " mc_choice

# 输入校验
if ! [[ "$mc_choice" =~ ^[0-9]+$ ]] || [ "$mc_choice" -lt 1 ] || [ "$mc_choice" -gt "${#MC_VERSIONS[@]}" ]; then
  log_error "无效选择"
  exit 1
fi

idx=$((mc_choice - 1))
mc_ver="${MC_VERSIONS[$idx]}"
mc_url="${MC_URLS[$idx]}"

# 检查占位符链接
if [[ "$mc_url" == *"example.com"* ]] || [[ "$mc_url" == *"5b9c3c0e"* && "$mc_ver" == "1.21.3" ]]; then
  log_error "检测到未替换的示例链接！"
  echo "请编辑脚本，在『用户配置区』填写真实的下载直链"
  exit 1
fi

# 检查 server.jar 是否已存在
if [ -f "server.jar" ]; then
  read -p "⚠️ 当前目录已存在 server.jar，是否覆盖? (y/N): " overwrite
  if [[ ! "$overwrite" =~ ^[yY]([eE][sS])?$ ]]; then
    log_info "已取消下载"
    exit 0
  fi
  rm -f server.jar
fi

# 下载文件（带重试）
log_step "下载 Minecraft $mc_ver 服务端..."
max_retries=3
retry=0
while [ $retry -lt $max_retries ]; do
  if $DOWNLOAD_CMD -O "server.jar" "$mc_url" 2>/dev/null; then
    break
  fi
  retry=$((retry + 1))
  log_warn "下载失败，重试 $retry/$max_retries ..."
  sleep 2
done

# 验证下载结果
if [ -f "server.jar" ] && [ -s "server.jar" ]; then
  file_size=$(du -h server.jar | cut -f1)
  log_info "✅ 下载成功! server.jar ($file_size)"
  echo ""
  echo -e "${GREEN}📌 下一步操作指引:${NC}"
  echo "   1️⃣  首次启动生成配置:  java -Xmx2G -jar server.jar nogui"
  echo "   2️⃣  同意用户协议:      编辑 eula.txt，将 eula=false 改为 true"
  echo "   3️⃣  正式启动服务器:    java -Xmx4G -Xms2G -jar server.jar nogui"
  echo ""
  echo -e "${YELLOW}💡 推荐启动参数:${NC}"
  echo "   -Xmx4G          # 最大内存 4GB（根据服务器配置调整）"
  echo "   -Xms2G          # 初始内存 2GB"
  echo "   -XX:+UseG1GC    # 使用 G1 垃圾回收器（推荐）"
  echo "   -nogui          # 无图形界面，节省资源"
  echo ""
  echo "🔗 官方文档: https://www.minecraft.net/server"
else
  log_error "下载失败：文件不存在或为空"
  echo "请检查:"
  echo "  • 下载链接是否为【直链】（浏览器打开应直接下载 jar 文件）"
  echo "  • 服务器网络是否正常（可尝试 ping piston-data.mojang.com）"
  echo "  • 磁盘空间是否充足"
  rm -f server.jar
  exit 1
fi

log_info "🎉 配置完成！祝游戏愉快 ⛏️"
