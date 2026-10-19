#!/bin/bash

# 检查参数
if [ "$#" -ne 1 ]; then
    echo "用法: $0 <DOWNLOAD_URL>"
    exit 1
fi

DOWNLOAD_URL="$1"

# 询问用户要下载的流量 (GB)
read -p "请输入要下载的流量 (GB)，默认无限循环: " GB

# 计算目标下载量 (GB -> MB)
if [[ -z "$GB" ]]; then
    TARGET_SIZE=-1  # -1 代表无限循环
else
    TARGET_SIZE=$((GB * 1024))  # 1GB = 1024MB
fi

# 询问用户是否限制下载速率 (Mbps)
read -p "请输入下载速率限制 (Mbps)，默认不限制: " SPEED_LIMIT

# 计算速率限制 (Mbps -> B/s)
if [[ -z "$SPEED_LIMIT" ]]; then
    LIMIT_OPTION=""
else
    LIMIT_OPTION="--limit-rate=$((SPEED_LIMIT * 125000))"  # Mbps 转换为 B/s
fi

# 启动后台任务
nohup bash -c '
DOWNLOADED_SIZE=0
while true; do
    wget -q --no-check-certificate '"$LIMIT_OPTION"' -O /dev/null '"$DOWNLOAD_URL"'
    DOWNLOADED_SIZE=$((DOWNLOADED_SIZE + 100))  # 100MB
    if [[ '"$TARGET_SIZE"' -gt 0 && $DOWNLOADED_SIZE -ge '"$TARGET_SIZE"' ]]; then
        break  # 达到目标后安静退出
    fi
done
' >/dev/null 2>&1 &
