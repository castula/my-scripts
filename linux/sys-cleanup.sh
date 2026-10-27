#!/bin/bash
# ============================================
#  系统清理脚本
# ============================================

set -e

# ============================================
#  颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================
#  检测系统类型
# ============================================
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
    elif [ -f /etc/debian_version ] || command -v apt >/dev/null 2>&1; then
        OS="debian"
    else
        log_error "不支持的系统类型"
        exit 1
    fi
}

# ============================================
#  检查 root 权限
# ============================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请以 root 用户运行此脚本"
        exit 1
    fi
}

# ============================================
#  清理 Alpine 系统
# ============================================
clean_alpine() {
    log_info "清理 Alpine 系统..."
    
    # 清理包缓存
    apk cache clean 2>/dev/null || true
    
    # 删除未使用的包
    apk del $(apk info --installed | grep -v "^apk-tools" | grep -v "^busybox" | grep -v "^alpine-baselayout") 2>/dev/null || true
    
    # 清理日志文件
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    find /var/log -type f -name "*.old" -delete 2>/dev/null || true
    find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
    
    # 清理临时文件
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    # 清理缓存目录
    rm -rf /root/.cache/* 2>/dev/null || true
    rm -rf /home/*/.cache/* 2>/dev/null || true
    
    # 清理旧的日志轮转文件
    find /var/log -type f -name "*.log.[0-9]*" -delete 2>/dev/null || true
}

# ============================================
#  清理 Debian 系统
# ============================================
clean_debian() {
    log_info "清理 Debian 系统..."
    
    # 清理 apt 缓存
    apt autoremove --purge -y 2>/dev/null || true
    apt clean -y 2>/dev/null || true
    apt autoclean -y 2>/dev/null || true
    
    # 移除未使用的配置文件包
    apt remove --purge $(dpkg -l | awk '/^rc/ {print $2}') -y 2>/dev/null || true
    
    # 旋转和压缩日志
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --rotate 2>/dev/null || true
        journalctl --vacuum-time=1s 2>/dev/null || true
        journalctl --vacuum-size=50M 2>/dev/null || true
    fi
    
    # 清理旧内核（保留当前内核）
    if command -v dpkg >/dev/null 2>&1; then
        current_kernel=$(uname -r)
        old_kernels=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$current_kernel" | grep -v "generic" || true)
        if [ -n "$old_kernels" ]; then
            apt remove --purge $old_kernels -y 2>/dev/null || true
        fi
    fi
    
    # 清理临时文件
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    # 清理缓存目录
    rm -rf /root/.cache/* 2>/dev/null || true
    rm -rf /home/*/.cache/* 2>/dev/null || true
    
    # 清理旧的日志文件
    find /var/log -type f -name "*.log.[0-9]*" -delete 2>/dev/null || true
    find /var/log -type f -name "*.old" -delete 2>/dev/null || true
}

# ============================================
#  通用清理（静默清空各类历史与痕迹文件）
# ============================================
clean_common() {
    log_info "执行通用清理..."
    
    # 清理 Docker（如果存在）
    if command -v docker >/dev/null 2>&1; then
        docker system prune -af --volumes 2>/dev/null || true
    fi
    
    # 清理内存中的历史
    history -c 2>/dev/null || true
    export HISTSIZE=0 2>/dev/null || true

    # 静默清空各类历史文件与 wget hsts 记录
    local target_files=(".bash_history" ".ash_history" ".zsh_history" ".ksh_history" ".sh_history" ".mysql_history" ".python_history" ".wget-hsts")
    
    for tfile in "${target_files[@]}"; do
        [ -f "/root/$tfile" ] && > "/root/$tfile" 2>/dev/null || true
        for user_home in /home/*; do
            [ -f "$user_home/$tfile" ] && > "$user_home/$tfile" 2>/dev/null || true
        done
    done
    
    # 清理空文件和目录
    find /var/log -type f -empty -delete 2>/dev/null || true
    find /var/log -type d -empty -delete 2>/dev/null || true
}

# ============================================
#  显示磁盘使用情况
# ============================================
show_disk_usage() {
    df -h / | tail -1
}

# ============================================
#  主程序
# ============================================
main() {
    # 检查权限
    check_root
    
    # 检测系统
    detect_os
    
    # 显示清理前磁盘使用
    before=$(show_disk_usage)
    
    # 执行清理
    case "$OS" in
        alpine)
            clean_alpine
            ;;
        debian)
            clean_debian
            ;;
    esac
    
    # 通用清理
    clean_common
    
    # 显示清理后磁盘使用
    after=$(show_disk_usage)
    
    echo ""
    log_info "清理完成"
    echo "清理前: $before"
    echo "清理后: $after"
}

# ============================================
#  执行
# ============================================
main "$@"
