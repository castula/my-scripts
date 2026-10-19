#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 权限运行"
    exit 1
fi

check_bbr_enabled() {
    modprobe tcp_bbr 2>/dev/null || true
    if grep -qw "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        [ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" = "bbr" ] && return 0
    fi
    return 1
}

select_qdisc() {
    if modprobe sch_fq_pie 2>/dev/null && sysctl -w net.core.default_qdisc=fq_pie >/dev/null 2>&1; then
        QDISC="fq_pie"
        QDISC_MOD="sch_fq_pie"
    else
        modprobe sch_fq 2>/dev/null || true
        QDISC="fq"
        QDISC_MOD="sch_fq"
    fi
}

configure_bbr() {
    modprobe tcp_bbr 2>/dev/null || true
    select_qdisc

    if [ -f /etc/sysctl.conf ]; then
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    fi

    mkdir -p /etc/sysctl.d
    cat > /etc/sysctl.d/99-bbr.conf << EOF
net.core.default_qdisc=$QDISC
net.ipv4.tcp_congestion_control=bbr
EOF

    if [ -f /etc/alpine-release ]; then
        touch /etc/modules
        grep -qxF "tcp_bbr" /etc/modules || echo "tcp_bbr" >> /etc/modules
        grep -qxF "$QDISC_MOD" /etc/modules || echo "$QDISC_MOD" >> /etc/modules
        if command -v rc-update >/dev/null 2>&1; then
            rc-update add modules boot >/dev/null 2>&1 || true
            rc-update add sysctl boot >/dev/null 2>&1 || true
        fi
    else
        mkdir -p /etc/modules-load.d
        cat > /etc/modules-load.d/bbr.conf << EOF
tcp_bbr
$QDISC_MOD
EOF
    fi

    sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true

    if check_bbr_enabled; then
        current_qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)
        log_info "BBR 已启用 (bbr + ${current_qdisc})"
    else
        log_warn "BBR 启用失败（内核不支持或处于受限容器环境）"
        exit 1
    fi
}

configure_bbr
