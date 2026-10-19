#!/bin/sh

# 内置密钥定义
KEY_NORMAL="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfMzz2TPGFY5wYWHb8Sy7qslWK0nVUClsDKC5p58RtJ"
KEY_IMPORTANT="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjuzJMosVMmoYFPsOdP9i7mdoH3xgibDNE1IeIcqs/G"

# 修改 /etc/ssh/sshd_config 的通用函数 (如果配置项存在则替换，不存在则追加到末尾)
set_sshd_config() {
    param="$1"
    value="$2"
    config_file="/etc/ssh/sshd_config"
    if grep -q -E "^#?[[:space:]]*${param}[[:space:]]+" "$config_file"; then
        sed -i "s/^#\?[[:space:]]*${param}[[:space:]].*/${param} ${value}/" "$config_file"
    else
        echo "${param} ${value}" >> "$config_file"
    fi
}

# 修改 SSH 端口的独立函数
change_ssh_port() {
    echo ""
    printf "请输入新的 SSH 端口号 [1-65535，默认回车保持不变]: "
    read NEW_PORT
    if [ -z "$NEW_PORT" ]; then
        echo "-> 跳过端口修改，保持原端口不变。"
        return
    fi

    # 校验是否为纯数字且在合法范围内
    case "$NEW_PORT" in
        ''|*[!0-9]*)
            echo "错误：端口号必须是纯数字！脚本退出。"
            exit 1
            ;;
        *)
            if [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
                echo "错误：端口号必须在 1 到 65535 之间！脚本退出。"
                exit 1
            fi
            ;;
    esac

    # 清理 sshd_config.d 下可能存在的 Port 覆盖配置
    if [ -d /etc/ssh/sshd_config.d ]; then
        sed -i 's/^Port/#Port/g' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
    fi

    # 修改主配置文件中的 Port
    set_sshd_config "Port" "$NEW_PORT"
    echo "-> SSH 端口已配置为: $NEW_PORT"

    # 若系统开启了 UFW 防火墙，自动放行新端口
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw allow "$NEW_PORT"/tcp >/dev/null 2>&1
            echo "-> 检测到 UFW 防火墙已启用，已自动放行 TCP 端口 $NEW_PORT"
        fi
    fi
}

# 修改系统用户密码的函数
change_user_password() {
    echo ""
    echo "----------------------------------------"
    echo "安全提醒：已切回密码登录，建议更新当前用户的登录密码。"
    printf "是否需要立即修改当前用户的密码？[Y/n]: "
    read MODIFY_PWD_CONFIRM
    case "$MODIFY_PWD_CONFIRM" in
        [nN]|[nN][oO])
            echo "-> 跳过密码修改。"
            ;;
        *)
            echo "-> 正在调用 passwd 修改当前用户密码："
            passwd
            ;;
    esac
}

echo "========================================"
echo "          SSH 综合配置与管理工具"
echo "========================================"
echo "请选择要执行的操作："
echo "  1) 密钥 + 密码双认证登录"
echo "  2) 仅密钥登录 (禁用密码)"
echo "  3) 仅密码登录 (禁用密钥)"
echo "  4) 删除所有密钥并还原为纯密码登录"
echo "  5) 仅修改 SSH 端口号"
echo "========================================"
printf "请输入选项 [1-5]: "
read AUTH_MODE

# 校验模式输入
case "$AUTH_MODE" in
    1|2|3|4|5) ;;
    *) echo "错误：无效的选项，脚本退出。"; exit 1 ;;
esac

# 如果选择了需要配置密钥的模式 (1 或 2)
if [ "$AUTH_MODE" = "1" ] || [ "$AUTH_MODE" = "2" ]; then
    echo ""
    echo "----------------------------------------"
    echo "请选择要写入的公钥："
    echo "  1) 第一个：普通密钥 (...p58RtJ)"
    echo "  2) 第二个：重要密钥 (...Icqs/G)"
    echo "  3) 同时写入以上两个密钥"
    echo "  4) 手动输入自定义公钥"
    echo "----------------------------------------"
    printf "请输入选项 [1-4]: "
    read KEY_CHOICE

    case "$KEY_CHOICE" in
        1) SELECTED_KEY="$KEY_NORMAL" ;;
        2) SELECTED_KEY="$KEY_IMPORTANT" ;;
        3) SELECTED_KEY="$(printf "%s\n%s" "$KEY_NORMAL" "$KEY_IMPORTANT")" ;;
        4) 
            printf "请粘贴你的自定义公钥: "
            read SELECTED_KEY
            if [ -z "$SELECTED_KEY" ]; then
                echo "错误：公钥内容不能为空！"; exit 1
            fi
            ;;
        *) echo "错误：无效的选项，脚本退出。"; exit 1 ;;
    esac

    # 写入公钥
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$SELECTED_KEY" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "-> 公钥已成功写入 ~/.ssh/authorized_keys"
fi

# 如果选择了模式 4 (删除密钥并还原)
if [ "$AUTH_MODE" = "4" ]; then
    rm -f ~/.ssh/authorized_keys
    echo "-> 已删除 ~/.ssh/authorized_keys 密钥文件"
fi

# 处理选项 1-4 的认证配置修改
if [ "$AUTH_MODE" != "5" ]; then
    # 清理云厂商在 sshd_config.d 下可能冲突的覆盖配置
    if [ -d /etc/ssh/sshd_config.d ]; then
        sed -i 's/^PasswordAuthentication/#PasswordAuthentication/g' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
        sed -i 's/^PubkeyAuthentication/#PubkeyAuthentication/g' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
        sed -i 's/^PermitRootLogin/#PermitRootLogin/g' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
    fi

    case "$AUTH_MODE" in
        1)
            set_sshd_config "PubkeyAuthentication" "yes"
            set_sshd_config "PasswordAuthentication" "yes"
            set_sshd_config "PermitRootLogin" "yes"
            echo "-> SSH 配置已修改为：密钥 + 密码双认证"
            ;;
        2)
            set_sshd_config "PubkeyAuthentication" "yes"
            set_sshd_config "PasswordAuthentication" "no"
            set_sshd_config "PermitRootLogin" "prohibit-password"
            echo "-> SSH 配置已修改为：仅密钥登录 (已禁用密码)"
            ;;
        3|4)
            set_sshd_config "PubkeyAuthentication" "no"
            set_sshd_config "PasswordAuthentication" "yes"
            set_sshd_config "PermitRootLogin" "yes"
            echo "-> SSH 配置已修改为：仅密码登录 (已禁用密钥)"
            # 触发修改密码提示
            change_user_password
            ;;
    esac

    set_sshd_config "ChallengeResponseAuthentication" "no"
    set_sshd_config "KbdInteractiveAuthentication" "no"

    # Alpine 兼容：仅在存在 /etc/pam.d 时更新 UsePAM
    if grep -q -E "^#?[[:space:]]*UsePAM[[:space:]]+" /etc/ssh/sshd_config && [ -d /etc/pam.d ]; then
        sed -i "s/^#\?[[:space:]]*UsePAM .*/UsePAM yes/" /etc/ssh/sshd_config
    fi

    # 询问是否顺便修改端口
    echo ""
    printf "是否需要同时修改 SSH 端口？[y/N]: "
    read CHANGE_PORT_CONFIRM
    case "$CHANGE_PORT_CONFIRM" in
        [yY]|[yY][eE][sS])
            change_ssh_port
            ;;
    esac
else
    # 如果主菜单直接选了 5 (仅修改端口)
    change_ssh_port
fi

# 重启 SSH 服务（兼容 Alpine OpenRC、Debian/Ubuntu Systemd 及 ssh.socket）
echo "-> 正在重启 SSH 服务..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then
        systemctl stop ssh.socket 2>/dev/null
        systemctl disable ssh.socket 2>/dev/null
        systemctl enable ssh.service 2>/dev/null
    fi
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
elif command -v service >/dev/null 2>&1; then
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null
elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd restart 2>/dev/null
else
    /etc/init.d/ssh restart 2>/dev/null || /etc/init.d/sshd restart 2>/dev/null
fi

echo "========================================"
echo "              操作全部完成！"
if [ -n "$NEW_PORT" ]; then
    echo "  请确保防火墙已放行端口: $NEW_PORT"
fi
echo "========================================"
