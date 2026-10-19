#!/bin/bash

# 检查并自动安装 chattr (e2fsprogs)
if ! command -v chattr &> /dev/null; then
    echo "检测到系统缺少 chattr 命令，正在尝试自动安装..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y e2fsprogs
    elif command -v apk &> /dev/null; then
        sudo apk update && sudo apk add e2fsprogs
    elif command -v opkg &> /dev/null; then
        sudo opkg update && sudo opkg install e2fsprogs
    else
        echo "⚠️ 警告: 未找到支持的包管理器 (apt/apk/opkg)，无法自动安装 chattr，跳过锁定功能。"
    fi
fi

# 写入国内公共 DNS (阿里 DNS) 到 /tmp/resolv.conf
echo -e "nameserver 223.5.5.5\nnameserver 2400:3200::1" | sudo tee /tmp/resolv.conf

# 检查写入是否成功
if [ $? -eq 0 ]; then
    # 写入成功，执行后续步骤

    # 如果 chattr 存在，解除文件锁定
    if command -v chattr &> /dev/null; then
        sudo chattr -i /etc/resolv.conf 2>/dev/null
    fi

    # 删除所有resolv
    sudo rm -rf /etc/resolv*

    # 移动新的resolv.conf到/etc/
    sudo mv /tmp/resolv.conf /etc/

    # 如果 chattr 存在，添加文件锁定
    if command -v chattr &> /dev/null; then
        sudo chattr +i /etc/resolv.conf
    fi

    echo "DNS 已成功切换为国内 DNS (阿里)！"
else
    # 写入失败，输出错误信息
    echo "写入失败，请重试。"
fi
