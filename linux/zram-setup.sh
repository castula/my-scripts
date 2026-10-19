#!/bin/bash
# ============================================
# zram 自动配置脚本
# 功能：删除硬盘 swap，按内存百分比启用 zram
# 适用：Alpine (OpenRC) / Debian (systemd)
# ============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== zram 自动配置脚本 ===${NC}"

# 检查是否 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请以 root 用户运行此脚本${NC}"
    exit 1
fi

# ============================================
#  检测系统类型
# ============================================
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
        SERVICE_MANAGER="openrc"
        echo -e "${GREEN}✓ 检测到 Alpine Linux${NC}"
    elif [ -f /etc/debian_version ] || command -v apt >/dev/null 2>&1; then
        OS="debian"
        SERVICE_MANAGER="systemd"
        echo -e "${GREEN}✓ 检测到 Debian/Ubuntu${NC}"
    else
        echo -e "${RED}✗ 不支持的系统类型${NC}"
        exit 1
    fi
}

detect_os

# ============================================
#  移除不可变属性（兼容 Debian 的 lsattr）
# ============================================
remove_immutable_flag() {
    local file="$1"
    if [ -f "$file" ]; then
        if command -v lsattr >/dev/null 2>&1; then
            if lsattr "$file" 2>/dev/null | grep -q 'i'; then
                chattr -i "$file" 2>/dev/null || true
            fi
        fi
    fi
}

# ============================================
#  1. 删除旧的 swapfile
# ============================================
echo -e "${YELLOW}检查并删除旧的 swapfile...${NC}"
if [ -f /swapfile ]; then
    swapoff /swapfile 2>/dev/null && echo "  ✓ 已关闭 swapfile"
    rm -f /swapfile && echo "  ✓ 已删除文件"
    sed -i '/swapfile/d' /etc/fstab && echo "  ✓ 已从 fstab 移除"
else
    echo -e "${GREEN}  ✓ 未发现旧的 swapfile${NC}"
fi

# ============================================
#  2. 关闭所有 zram 设备
# ============================================
echo -e "${YELLOW}关闭所有 zram 设备...${NC}"
found_zram=false
for zram_dev in /dev/zram[0-9]*; do
    if [ -e "$zram_dev" ]; then
        found_zram=true
        swapoff "$zram_dev" 2>/dev/null && echo "  已关闭 $zram_dev"
    fi
done
if [ "$found_zram" = false ]; then
    echo -e "${GREEN}  ✓ 未发现 zram 设备${NC}"
else
    echo -e "${GREEN}  ✓ 已关闭所有 zram 设备${NC}"
fi

# ============================================
#  3. 卸载 zram 模块（带重试机制）
# ============================================
if lsmod 2>/dev/null | grep -q zram; then
    echo -e "${YELLOW}卸载 zram 模块...${NC}"
    
    for i in 1 2 3 4 5; do
        if rmmod zram 2>/dev/null; then
            echo -e "${GREEN}  ✓ zram 模块已卸载${NC}"
            break
        else
            if [ $i -lt 5 ]; then
                echo -e "${YELLOW}  模块正忙，等待 1 秒后重试 (${i}/5)...${NC}"
                sleep 1
            else
                echo -e "${YELLOW}  ⚠ 无法卸载 zram 模块，将尝试强制重置${NC}"
                for zram_dev in /sys/block/zram*; do
                    if [ -f "$zram_dev/reset" ]; then
                        echo 1 > "$zram_dev/reset" 2>/dev/null || true
                    fi
                done
                rmmod zram 2>/dev/null || echo -e "${YELLOW}  ⚠ 模块仍在使用，继续执行${NC}"
            fi
        fi
    done
else
    echo -e "${GREEN}✓ zram 模块未加载${NC}"
fi

# ============================================
#  4. 检测内核支持的压缩算法
# ============================================
echo -e "${YELLOW}检测内核支持的压缩算法...${NC}"

modprobe zram 2>/dev/null || true

if [ -f /sys/block/zram0/comp_algorithm ]; then
    ALGO_LIST=$(cat /sys/block/zram0/comp_algorithm)
    echo "  支持的算法: $ALGO_LIST"
    
    if echo "$ALGO_LIST" | grep -q "zstd"; then
        ZSTD_SUPPORT=true
        echo -e "${GREEN}  ✓ 内核支持 zstd${NC}"
    else
        ZSTD_SUPPORT=false
        echo -e "${YELLOW}  ⚠ 内核不支持 zstd，将使用 lzo-rle${NC}"
    fi
    
    for i in 1 2 3; do
        if rmmod zram 2>/dev/null; then
            break
        fi
        sleep 1
    done
else
    echo -e "${RED}  ✗ 无法检测 zram 支持${NC}"
    exit 1
fi

# ============================================
#  5. 选择算法
# ============================================
if [ "$ZSTD_SUPPORT" = true ]; then
    ALGORITHM="zstd"
    echo -e "${GREEN}  ✓ 使用 zstd 压缩算法${NC}"
else
    ALGORITHM="lzo-rle"
    echo -e "${GREEN}  ✓ 使用 lzo-rle 压缩算法（回退方案）${NC}"
fi

# ============================================
#  6. 配置 zram 模块默认算法
# ============================================
echo -e "${YELLOW}配置 zram 模块使用 $ALGORITHM 算法...${NC}"
echo "options zram comp_algorithm=$ALGORITHM" > /etc/modprobe.d/zram.conf
echo -e "${GREEN}  ✓ 已创建 /etc/modprobe.d/zram.conf${NC}"

# ============================================
#  7. 创建启动脚本（根据系统类型）
# ============================================
echo -e "${YELLOW}创建 zram 启动脚本...${NC}"

if [ "$OS" = "alpine" ]; then
    # Alpine: 使用 OpenRC local 服务
    cat > /etc/local.d/zram.start << 'EOF'
#!/bin/sh

log() {
    echo "[zram] $1"
}

# 检测内核支持的算法
modprobe zram 2>/dev/null || true
if [ -f /sys/block/zram0/comp_algorithm ]; then
    ALGO_LIST=$(cat /sys/block/zram0/comp_algorithm)
    if echo "$ALGO_LIST" | grep -q "zstd"; then
        ALGO="zstd"
    else
        if echo "$ALGO_LIST" | grep -q "lzo-rle"; then
            ALGO="lzo-rle"
        else
            ALGO="lzo"
        fi
    fi
    for i in 1 2 3; do
        if rmmod zram 2>/dev/null; then
            break
        fi
        sleep 1
    done
else
    ALGO="lzo-rle"
fi

# 修复：更健壮的内存获取方式
TOTAL_MEM=$(free -m | grep "^Mem:" | tr -s ' ' | cut -d ' ' -f 2)
# 如果还是获取不到，使用备用方法
if [ -z "$TOTAL_MEM" ] || [ "$TOTAL_MEM" -eq 0 ]; then
    TOTAL_MEM=$(free -m | awk 'NR==2{print $2}')
fi
# 最后的保底值
if [ -z "$TOTAL_MEM" ] || [ "$TOTAL_MEM" -eq 0 ]; then
    TOTAL_MEM=512
fi

CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)

# 智能策略 v2
if [ "$TOTAL_MEM" -le 256 ]; then
    PERCENT=75
elif [ "$TOTAL_MEM" -le 1024 ]; then
    PERCENT=100
elif [ "$TOTAL_MEM" -le 2048 ]; then
    # 2GB 以下：CPU 多核可以 100%，单核 75%
    if [ "$CPU_CORES" -ge 2 ]; then
        PERCENT=100
    else
        PERCENT=75
    fi
elif [ "$TOTAL_MEM" -le 4096 ]; then
    # 4GB 以下：多核 75%，单核 50%
    if [ "$CPU_CORES" -ge 4 ]; then
        PERCENT=75
    elif [ "$CPU_CORES" -ge 2 ]; then
        PERCENT=65
    else
        PERCENT=50
    fi
else
    # 4GB 以上：不超 50%，避免元数据浪费
    if [ "$CPU_CORES" -ge 4 ]; then
        PERCENT=50
    else
        PERCENT=35
    fi
fi

SIZE_MB=$((TOTAL_MEM * PERCENT / 100))
# 保底最小 64MB，最大不超过内存的 150%（防止过度分配导致崩溃）
MAX_SIZE=$((TOTAL_MEM * 150 / 100))
[ $SIZE_MB -lt 64 ] && SIZE_MB=64
[ $SIZE_MB -gt $MAX_SIZE ] && SIZE_MB=$MAX_SIZE

log "检测到 $TOTAL_MEM MB 内存，$CPU_CORES 核 CPU，分配 ${SIZE_MB} MB (${PERCENT}%) 给 zram"

for dev in /dev/zram[0-9]*; do
    [ -e "$dev" ] && swapoff "$dev" 2>/dev/null
done

for dev in /sys/block/zram*; do
    [ -f "$dev/reset" ] && echo 1 > "$dev/reset" 2>/dev/null || true
done

for i in 1 2 3 4 5; do
    if rmmod zram 2>/dev/null; then
        break
    fi
    sleep 1
done

log "加载 zram 模块"
modprobe zram 2>/dev/null

if [ "$ALGO" = "zstd" ] && [ -f /sys/block/zram0/comp_algorithm ]; then
    log "尝试切换算法为 zstd"
    if echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null; then
        log "✓ 切换成功"
    else
        log "⚠ 切换失败，使用默认算法"
    fi
fi

if [ -f /sys/block/zram0/comp_algorithm ]; then
    CURRENT=$(cat /sys/block/zram0/comp_algorithm | sed 's/.*\[\(.*\)\].*/\1/')
    log "当前压缩算法: $CURRENT"
else
    CURRENT="unknown"
fi

log "配置 zram 设备"
echo "${SIZE_MB}M" > /sys/block/zram0/disksize 2>/dev/null || {
    log "错误：无法设置 zram 大小"
    exit 1
}

mkswap /dev/zram0 >/dev/null 2>&1
swapon /dev/zram0 -p 100

log "zram 已启用: ${TOTAL_MEM}MB RAM → ${SIZE_MB}MB zram (${PERCENT}%) [$CURRENT]"
EOF

    chmod +x /etc/local.d/zram.start
    echo -e "${GREEN}  ✓ 已创建 /etc/local.d/zram.start${NC}"

    # 配置开机自启
    echo -e "${YELLOW}配置开机自启...${NC}"
    rc-update add local 2>/dev/null >/dev/null || true
    rc-service local start 2>/dev/null >/dev/null || true
    echo -e "${GREEN}  ✓ 已添加 local 服务${NC}"

else
    # Debian: 使用 systemd service
    cat > /usr/local/bin/zram-setup << 'EOF'
#!/bin/bash

log() {
    echo "[zram] $1"
}

modprobe zram 2>/dev/null || true
if [ -f /sys/block/zram0/comp_algorithm ]; then
    ALGO_LIST=$(cat /sys/block/zram0/comp_algorithm)
    if echo "$ALGO_LIST" | grep -q "zstd"; then
        ALGO="zstd"
    else
        if echo "$ALGO_LIST" | grep -q "lzo-rle"; then
            ALGO="lzo-rle"
        else
            ALGO="lzo"
        fi
    fi
    for i in 1 2 3; do
        if rmmod zram 2>/dev/null; then
            break
        fi
        sleep 1
    done
else
    ALGO="lzo-rle"
fi

# 从 /proc/meminfo 直接读取内存大小（最可靠）
TOTAL_MEM=$(grep "^MemTotal:" /proc/meminfo | awk '{print int($2/1024)}')

# 验证内存大小是否有效
if [ -z "$TOTAL_MEM" ] || [ "$TOTAL_MEM" -le 0 ]; then
    echo "[ERROR] 无法获取系统内存大小"
    exit 1
fi

# 极低内存警告
if [ "$TOTAL_MEM" -lt 64 ]; then
    echo "[WARN] 系统内存仅有 ${TOTAL_MEM}MB，zram 可能无法正常工作"
fi

CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)

# 智能百分比策略（优化版）
# 1GB 以下：100% (对极度小内存最有帮助)
# 1GB-4GB：50%
# 4GB 以上：25%
if [ "$TOTAL_MEM" -le 1024 ]; then
    PERCENT=100
elif [ "$TOTAL_MEM" -le 4096 ]; then
    PERCENT=50
else
    PERCENT=25
fi

SIZE_MB=$((TOTAL_MEM * PERCENT / 100))
# 保底最小 64MB，最大不超过内存的 150%（防止过度分配导致崩溃）
MAX_SIZE=$((TOTAL_MEM * 150 / 100))
[ $SIZE_MB -lt 64 ] && SIZE_MB=64
[ $SIZE_MB -gt $MAX_SIZE ] && SIZE_MB=$MAX_SIZE

log "检测到 $TOTAL_MEM MB 内存，$CPU_CORES 核 CPU，分配 ${SIZE_MB} MB (${PERCENT}%) 给 zram"

for dev in /dev/zram[0-9]*; do
    [ -e "$dev" ] && swapoff "$dev" 2>/dev/null
done

for dev in /sys/block/zram*; do
    [ -f "$dev/reset" ] && echo 1 > "$dev/reset" 2>/dev/null || true
done

for i in 1 2 3 4 5; do
    if rmmod zram 2>/dev/null; then
        break
    fi
    sleep 1
done

log "加载 zram 模块"
modprobe zram 2>/dev/null

if [ "$ALGO" = "zstd" ] && [ -f /sys/block/zram0/comp_algorithm ]; then
    log "尝试切换算法为 zstd"
    if echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null; then
        log "✓ 切换成功"
    else
        log "⚠ 切换失败，使用默认算法"
    fi
fi

if [ -f /sys/block/zram0/comp_algorithm ]; then
    CURRENT=$(cat /sys/block/zram0/comp_algorithm | sed 's/.*\[\(.*\)\].*/\1/')
    log "当前压缩算法: $CURRENT"
else
    CURRENT="unknown"
fi

log "配置 zram 设备"
echo "${SIZE_MB}M" > /sys/block/zram0/disksize 2>/dev/null || {
    log "错误：无法设置 zram 大小"
    exit 1
}

mkswap /dev/zram0 >/dev/null 2>&1
swapon /dev/zram0 -p 100

log "zram 已启用: ${TOTAL_MEM}MB RAM → ${SIZE_MB}MB zram (${PERCENT}%) [$CURRENT]"
EOF

    chmod +x /usr/local/bin/zram-setup
    echo -e "${GREEN}  ✓ 已创建 /usr/local/bin/zram-setup${NC}"

    # 创建 systemd service
    cat > /etc/systemd/system/zram-setup.service << 'EOF'
[Unit]
Description=ZRAM Swap Setup
After=local-fs.target
Before=swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zram-setup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}  ✓ 已创建 /etc/systemd/system/zram-setup.service${NC}"

    # 配置开机自启
    echo -e "${YELLOW}配置开机自启...${NC}"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zram-setup.service >/dev/null 2>&1
    echo -e "${GREEN}  ✓ 已启用 systemd 服务${NC}"
fi

# ============================================
#  8. 立即执行
# ============================================
echo -e "${YELLOW}正在启用 zram...${NC}"

if [ "$OS" = "alpine" ]; then
    /etc/local.d/zram.start
else
    /usr/local/bin/zram-setup
fi

echo -e "${GREEN}  ✓ zram 已启用${NC}"

# ============================================
#  9. 显示结果
# ============================================
echo ""
echo -e "${GREEN}=== 配置完成 ===${NC}"
echo ""
echo -e "${YELLOW}当前交换状态：${NC}"
cat /proc/swaps
echo ""
echo -e "${YELLOW}内存状态：${NC}"
free -mh
echo ""
echo -e "${YELLOW}zram 压缩信息：${NC}"
if [ -f /sys/block/zram0/mm_stat ]; then
    echo "  压缩后实际占用内存: $(awk '{printf "%.2f MB", $3/1024/1024}' /sys/block/zram0/mm_stat 2>/dev/null)"
fi
if [ -f /sys/block/zram0/comp_algorithm ]; then
    CURRENT_ALGO=$(cat /sys/block/zram0/comp_algorithm | sed 's/.*\[\(.*\)\].*/\1/')
    echo "  当前压缩算法: $CURRENT_ALGO"
fi

echo ""
echo -e "${GREEN}✓ 已完成！重启后 zram 仍会自动启用。${NC}"
echo -e "${GREEN}  系统类型: $OS (使用 $SERVICE_MANAGER)${NC}"
