#!/bin/bash
#
# 脚本名称: MC-OC-qz
# 功能: 自动识别系统 + 安装依赖 + 源异常时下载换源脚本 + 交互确认执行
# 作者: xgp2012
# 日期: 2026-04-17
# 版本: v1.2
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_tip()     { echo -e "${BLUE}[TIP]${NC} $1"; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $1"; }

# 全局变量
MIRROR_SCRIPT="/tmp/linuxmirrors_main.sh"
MIRROR_URL="https://linuxmirrors.cn/main.sh"

# ============================================
# 1. 自动识别系统版本和包管理器
# ============================================
detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="${ID}"
        OS_VERSION="${VERSION_ID}"
        VERSION_CODENAME="${VERSION_CODENAME:-}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_NAME="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    else
        log_error "无法识别的操作系统"
        exit 1
    fi

    case "${OS_NAME}" in
        ubuntu|debian|kali)
            PM="apt"
            PM_UPDATE="apt-get update -y"
            PM_INSTALL="apt-get install -y"
            PM_CLEAN="apt-get autoremove -y"
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if command -v dnf &>/dev/null; then
                PM="dnf"
                PM_UPDATE="dnf makecache --refresh"
                PM_INSTALL="dnf install -y"
                PM_CLEAN="dnf autoremove -y"
            else
                PM="yum"
                PM_UPDATE="yum makecache fast -y"
                PM_INSTALL="yum install -y"
                PM_CLEAN="yum autoremove -y"
            fi
            ;;
        alpine)
            PM="apk"
            PM_UPDATE="apk update"
            PM_INSTALL="apk add --no-cache"
            PM_CLEAN="echo 'apk 无需清理'"
            ;;
        arch|manjaro)
            PM="pacman"
            PM_UPDATE="pacman -Sy --noconfirm"
            PM_INSTALL="pacman -S --noconfirm"
            PM_CLEAN="pacman -Rns $(pacman -Qtdq) --noconfirm 2>/dev/null || true"
            ;;
        opensuse|suse)
            PM="zypper"
            PM_UPDATE="zypper refresh"
            PM_INSTALL="zypper install -y"
            PM_CLEAN="zypper clean -a"
            ;;
        *)
            log_error "不支持的发行版: ${OS_NAME}"
            exit 1
            ;;
    esac
    log_info "系统: ${OS_NAME} ${OS_VERSION} | 包管理器: ${PM}"
}

# ============================================
# 2. 检查软件是否已安装
# ============================================
is_installed() {
    local pkg=$1
    case "${PM}" in
        apt)
            dpkg -l | grep -q "^ii  ${pkg} " &>/dev/null
            ;;
        yum|dnf|zypper)
            rpm -qa | grep -q "^${pkg}-" &>/dev/null
            ;;
        pacman)
            pacman -Qq "${pkg}" &>/dev/null
            ;;
        apk)
            apk info -e "${pkg}" &>/dev/null
            ;;
        *)
            command -v "${pkg}" &>/dev/null
            ;;
    esac
}

# ============================================
# 3. 检测软件源是否可用
# ============================================
check_repo_available() {
    log_step "检测软件源可用性..."
    local test_url=""
    
    case "${OS_NAME}" in
        ubuntu|debian)
            test_url="http://archive.ubuntu.com/ubuntu/dists/${VERSION_CODENAME:-jammy}/Release"
            ;;
        centos|rhel|fedora)
            test_url="http://mirror.centos.org/centos/7/os/x86_64/repodata/repomd.xml"
            ;;
        alpine)
            test_url="http://dl-cdn.alpinelinux.org/alpine/v3.19/main/x86_64/APKINDEX.tar.gz"
            ;;
        *)
            test_url="https://www.baidu.com"
            ;;
    esac
    
    # 尝试连接测试（超时5秒）
    if command -v curl &>/dev/null; then
        curl -sSL --connect-timeout 5 "${test_url}" &>/dev/null && return 0
    elif command -v wget &>/dev/null; then
        wget -q --timeout=5 --spider "${test_url}" &>/dev/null && return 0
    fi
    
    # 尝试执行包管理器更新
    ${PM_UPDATE} &>/dev/null && return 0
    
    return 1
}

# ============================================
# 4. 下载换源脚本 ⭐
# ============================================
download_mirror_script() {
    log_warn "⚠️  系统软件源不可用，需要更换镜像源"
    
    # 尝试下载
    if command -v curl &>/dev/null; then
        curl -sSL "${MIRROR_URL}" -o "${MIRROR_SCRIPT}" 2>/dev/null && chmod +x "${MIRROR_SCRIPT}" && return 0
    fi
    if command -v wget &>/dev/null; then
        wget -q "${MIRROR_URL}" -O "${MIRROR_SCRIPT}" 2>/dev/null && chmod +x "${MIRROR_SCRIPT}" && return 0
    fi
    
    log_error "❌ 无法下载换源脚本，请检查网络"
    return 1
}

# ============================================
# 5. 交互式确认执行换源 ⭐核心功能
# ============================================
interactive_change_repo() {
    echo ""
    echo -e "${YELLOW}┌─────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  ⚠️  软件源异常，建议更换镜像源  │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────┘${NC}"
    echo ""
    log_tip "换源脚本已下载: ${MIRROR_SCRIPT}"
    log_tip "该脚本将自动为您选择最优镜像源"
    echo ""
    
    # 显示操作选项
    echo -e "  ${GREEN}[1]${NC} 立即执行换源（推荐）"
    echo -e "  ${GREEN}[2]${NC} 跳过换源，手动处理"
    echo -e "  ${GREEN}[3]${NC} 查看换源脚本内容"
    echo ""
    
    # 带超时的读取（30秒无输入默认跳过）
    local choice=""
    if command -v timeout &>/dev/null; then
        choice=$(timeout 30 read -p "请输入选项 [1/2/3] (30秒超时默认跳过): " ans && echo "$ans")
    else
        read -p "请输入选项 [1/2/3]: " choice
    fi
    
    echo ""
    
    case "${choice}" in
        1)
            log_step "正在执行换源脚本..."
            echo ""
            if bash "${MIRROR_SCRIPT}"; then
                log_info "✅ 换源成功！正在刷新软件源缓存..."
                ${PM_UPDATE}
                log_info "✅ 源缓存刷新完成"
                return 0
            else
                log_error "❌ 换源执行失败"
                return 1
            fi
            ;;
        3)
            if command -v less &>/dev/null; then
                less "${MIRROR_SCRIPT}"
            else
                cat "${MIRROR_SCRIPT}"
            fi
            # 递归调用，让用户再次选择
            interactive_change_repo
            ;;
        2|*)
            log_warn "⏭️  已跳过自动换源"
            log_tip "您可以稍后手动执行: ${BLUE}bash ${MIRROR_SCRIPT}${NC}"
            return 1
            ;;
    esac
}

# ============================================
# 6. 安装指定软件包
# ============================================
install_package() {
    local pkg=$1
    
    if is_installed "${pkg}"; then
        log_info "✅ ${pkg} 已安装"
        return 0
    fi
    
    log_step "正在安装 ${pkg}..."
    if ${PM_INSTALL} "${pkg}" &>/dev/null; then
        log_info "✅ ${pkg} 安装成功"
        return 0
    else
        log_warn "⚠️  ${pkg} 安装失败"
        return 1
    fi
}

# ============================================
# 7. 重试安装（换源后调用）
# ============================================
retry_install() {
    local pkg=$1
    log_step "换源完成，重试安装 ${pkg}..."
    if install_package "${pkg}"; then
        return 0
    else
        log_error "❌ ${pkg} 重试安装仍失败"
        return 1
    fi
}

# ============================================
# 主函数
# ============================================
main() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   🚀 Linux 自动环境配置脚本 v1.2      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # 1. 检测系统
    detect_system
    echo ""
    
    # 2. 检测源 + 交互换源
    REPO_FIXED=false
    if ! check_repo_available; then
        log_warn "软件源检测失败"
        if download_mirror_script; then
            if interactive_change_repo; then
                REPO_FIXED=true
            fi
        fi
    else
        log_info "✅ 软件源检测通过"
        REPO_FIXED=true
    fi
    echo ""
    
    # 3. 安装依赖
    log_step "开始检查并安装依赖: wget, unzip"
    echo ""
    
    local fail_list=()
    
    # 安装 wget
    if ! install_package "wget"; then
        if ${REPO_FIXED}; then
            retry_install "wget" || fail_list+=("wget")
        else
            fail_list+=("wget")
        fi
    fi
    
    # 安装 unzip
    if ! install_package "unzip"; then
        if ${REPO_FIXED}; then
            retry_install "unzip" || fail_list+=("unzip")
        else
            fail_list+=("unzip")
        fi
    fi
    echo ""
    
    # 4. 结果汇总
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    log_info "📋 执行结果汇总"
    echo -e "${GREEN}────────────────────────────────────────${NC}"
    
    local all_pass=true
    
    # 验证 wget
    if command -v wget &>/dev/null; then
        log_info "✅ wget 验证通过: $(wget --version | head -1)"
    else
        log_error "❌ wget 未安装成功"
        all_pass=false
    fi
    
    # 验证 unzip
    if command -v unzip &>/dev/null; then
        log_info "✅ unzip 验证通过: $(unzip -v 2>&1 | head -1)"
    else
        log_error "❌ unzip 未安装成功"
        all_pass=false
    fi
    
    echo -e "${GREEN}────────────────────────────────────────${NC}"
    
    if ${all_pass}; then
        log_info "🎉 恭喜！所有依赖安装成功！"
        echo ""
        log_tip "您可以开始使用您的应用程序了 ~"
    else
        log_warn "⚠️  部分依赖安装失败"
        if [[ ${#fail_list[@]} -gt 0 ]]; then
            log_tip "失败的软件: ${fail_list[*]}"
        fi
        if ! ${REPO_FIXED}; then
            echo ""
            log_tip "💡 建议先执行换源，然后手动安装:"
            echo ""
            echo -e "  ${BLUE}bash ${MIRROR_SCRIPT}${NC}  # 换源"
            echo -e "  ${BLUE}${PM_UPDATE}${NC}           # 刷新缓存"
            echo -e "  ${BLUE}${PM_INSTALL} wget unzip${NC}  # 安装依赖"
        fi
    fi
    
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    log_info "✨ 脚本执行完成"
    echo ""
    
    # 返回状态码
    ${all_pass} && exit 0 || exit 1
}

# 捕获中断信号
trap 'echo ""; log_warn "⚠️  脚本被用户中断"; exit 130' INT TERM

# 执行主函数
main "$@"
