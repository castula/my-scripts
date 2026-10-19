#!/bin/bash

# 获取调制解调器的索引
MODEM_INDEX=0

# 列出所有短信ID
SMS_IDS=$(mmcli -m $MODEM_INDEX --messaging-list-sms | grep -o "/org/freedesktop/ModemManager1/SMS/[0-9]*")

# 删除每条短信
for SMS_ID in $SMS_IDS; do
    echo "Deleting SMS: $SMS_ID"
    mmcli -m $MODEM_INDEX --messaging-delete-sms=$SMS_ID
done

echo "All SMS messages have been deleted."

