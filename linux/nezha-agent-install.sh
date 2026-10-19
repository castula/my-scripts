#!/bin/bash

# 美化输出函数
print_info() {
    echo -e "\033[1;34m[信息]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[成功]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[错误]\033[0m $1"
}

print_step() {
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;36m  $1\033[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# 生成随机UUID函数（多方案兼容）
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import uuid; print(uuid.uuid4())'
    else
        # 兜底方案：使用 openssl 或 /dev/urandom 生成符合 UUID v4 格式的字符串
        od -x /dev/urandom | head -1 | awk '{OFS="-"; srand($6); sub(/./,"4",$5); sub(/./,substr("89ab",int(rand()*4)+1,1),$6); print $2$3,$4,$5,$6,$7$8$9}'
    fi
}

# 获取或生成UUID的交互函数
prompt_or_generate_uuid() {
    print_info "请输入新的 UUID (直接回车将自动生成):"
    echo -e "\033[1;33m────────────────────────────────────────\033[0m"
    read -p "➜ " USER_UUID
    if [ -z "$USER_UUID" ]; then
        USER_UUID=$(generate_uuid)
        print_success "已自动生成 UUID: $USER_UUID"
    else
        print_success "使用输入的 UUID: $USER_UUID"
    fi
    echo -e "\033[1;33m────────────────────────────────────────\033[0m"
    echo ""
}

# 从旧容器提取UUID
extract_uuid_from_container() {
    local container_id="$1"
    # 尝试从环境变量获取
    local uuid=$(docker inspect "$container_id" --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^UUID=' | cut -d'=' -f2)
    if [ -n "$uuid" ]; then
        echo "$uuid"
        return 0
    fi
    return 1
}

# 清理函数（静默执行）
cleanup_containers() {
    CONTAINER_IDS=$(docker ps -a --filter "name=nezha-agent" -q 2>/dev/null)
    if [ -n "$CONTAINER_IDS" ]; then
        echo "$CONTAINER_IDS" | xargs -r docker stop >/dev/null 2>&1
        echo "$CONTAINER_IDS" | xargs -r docker rm >/dev/null 2>&1
        return 0
    fi
    return 1
}

# 解析命令行参数
while getopts "s:r:" opt; do
    case $opt in
        s) CLIENT_SECRET="$OPTARG" ;;
        r) SERVER="$OPTARG" ;;
    esac
done

# 检查必需参数
if [ -z "$CLIENT_SECRET" ] || [ -z "$SERVER" ]; then
    print_error "必须提供 CLIENT_SECRET (-s) 和 SERVER (-r) 参数"
    echo "示例: $0 -s HAU4y3es0AwdlGRuvEHXpTtaLuuWLFCy -r rep.anhsy.org:443"
    exit 1
fi

# 开始安装流程
print_step "开始安装 Nezha Agent"

# 检测旧容器并提取UUID
print_info "检测旧容器..."
OLD_CONTAINER_ID=$(docker ps -a --filter "name=nezha-agent" -q 2>/dev/null | head -n 1)
EXTRACTED_UUID=""

if [ -n "$OLD_CONTAINER_ID" ]; then
    print_success "发现旧容器: $OLD_CONTAINER_ID"
    print_info "正在提取UUID..."
    EXTRACTED_UUID=$(extract_uuid_from_container "$OLD_CONTAINER_ID")
    if [ -n "$EXTRACTED_UUID" ]; then
        print_success "成功提取UUID: $EXTRACTED_UUID"
        echo ""
    else
        print_error "无法从旧容器提取UUID"
        echo ""
    fi
else
    print_info "未发现旧容器"
    echo ""
fi

# 清理旧容器（静默）
print_info "正在清理旧容器..."
if cleanup_containers; then
    print_success "旧容器已清除"
else
    print_info "未发现需要清理的容器"
fi

# 清理镜像（静默）
print_info "正在清理旧镜像..."
docker image prune -af >/dev/null 2>&1
print_success "镜像清理完成"

echo ""

# 确定UUID
if [ -n "$EXTRACTED_UUID" ]; then
    print_info "检测到旧UUID，是否使用? (直接回车默认使用):"
    echo -e "\033[1;33m────────────────────────────────────────\033[0m"
    read -p "➜ [Y/n] " USE_EXISTING
    # 如果直接回车（空输入）或输入 y/Y，则使用旧UUID
    if [ -z "$USE_EXISTING" ] || [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
        USER_UUID="$EXTRACTED_UUID"
        print_success "使用提取的UUID: $USER_UUID"
        echo -e "\033[1;33m────────────────────────────────────────\033[0m"
        echo ""
    else
        # 输入了 n/N 或其他内容，进入手动输入或自动生成
        echo -e "\033[1;33m────────────────────────────────────────\033[0m"
        echo ""
        prompt_or_generate_uuid
    fi
else
    # 未检测到旧UUID，提示输入或自动生成
    prompt_or_generate_uuid
fi

# 安装新容器
print_info "正在安装 Nezha Agent..."
echo ""

# 运行容器
docker run -d \
  --name nezha-agent \
  --network host \
  --restart always \
  -e CLIENT_SECRET="$CLIENT_SECRET" \
  -e UUID="$USER_UUID" \
  -e SERVER="$SERVER" \
  -e TLS=true \
  -e HOST_PROC=/info/proc \
  -e HOST_SYS=/info/sys \
  -e HOST_ETC=/info/etc \
  -v /sys:/info/sys:ro \
  -v /proc:/info/proc:ro \
  -v /etc/os-release:/info/etc/os-release:ro \
  spousal4806/nezha-agent:latest

# 检查安装结果
if [ $? -eq 0 ]; then
    CONTAINER_ID=$(docker ps --filter "name=nezha-agent" -q)
    echo ""
    print_success "安装成功！🎉"
    echo ""
    echo -e "\033[1;32m  容器:  \033[0m$CONTAINER_ID"
    echo -e "\033[1;32m  域名:  \033[0m$SERVER"
    echo -e "\033[1;32m  UUID:  \033[0m$USER_UUID"
    echo ""
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
else
    echo ""
    print_error "安装失败，请检查错误信息 ❌"
    exit 1
fi
