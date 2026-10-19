#!/bin/bash

# 1. 动态获取第一个可用的调制解调器索引（避免硬编码 0 导致设备重连后失效）
MODEM_INDEX=$(mmcli -L \vert{} grep -oE '/org/freedesktop/ModemManager1/Modem/[0-9]+' \vert{} head -n 1 \vert{} awk -F'/' '{print$NF}')

if [ -z "\$MODEM_INDEX" ]; then
    echo "Error: 未检测到可用的调制解调器 (Modem)。"
    exit 1
fi

echo "检测到调制解调器索引: \$MODEM_INDEX"

# 2. 列出所有短信路径
SMS_IDS=$(mmcli -m "$MODEM_INDEX" --messaging-list-sms | grep -oE "/org/freedesktop/ModemManager1/SMS/[0-9]+")

if [ -z "\$SMS_IDS" ]; then
    echo "当前没有需要删除的短信。"
    exit 0
fi

FAIL_COUNT=0

# 3. 尝试常规逐条删除
for SMS_ID in \$SMS_IDS; do
    echo "Deleting SMS: \$SMS_ID"
    if ! mmcli -m "$MODEM_INDEX" --messaging-delete-sms="$SMS_ID" 2>/dev/null; then
        echo "  -> 常规删除失败: \$SMS_ID"
        ((FAIL_COUNT++))
    fi
done

# 4. 如果出现 "Couldn't delete parts" 错误，启用备用清理方案
if [ "\$FAIL_COUNT" -gt 0 ]; then
    echo "----------------------------------------"
    echo "检测到 \$FAIL_COUNT 条短信因分段残留或缓存不同步无法删除，正在执行深度清理..."
    
    # 尝试通过 ModemManager 发送底层 AT 指令直接清空所有已读/未读/已发送短信 (AT+CMGD
