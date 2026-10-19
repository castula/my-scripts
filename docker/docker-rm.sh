#!/bin/bash

# 获取所有容器的ID、名称和状态
mapfile -t containers < <(docker ps -a --format "{{.ID}} | {{.Names}} | {{.Status}}")

if [ ${#containers[@]} -eq 0 ]; then
    echo "当前没有发现任何 Docker 容器。"
    exit 0
fi

echo "==================== Docker 容器列表 ===================="
i=1
for c in "${containers[@]}"; do
    cid=$(echo "$c" | awk -F' \\| ' '{print $1}')
    cname=$(echo "$c" | awk -F' \\| ' '{print $2}')
    cstatus=$(echo "$c" | awk -F' \\| ' '{print $3}')
    
    # 打印对齐的竖向列表
    printf " [%-2d] %-20s : %s\n" "$i" "$cname" "$cstatus"
    ((i++))
done
echo "========================================================="

# 提示用户输入
read -p "请输入要删除的容器编号（支持空格或逗号分隔，如 1, 4, 14）： " input

if [ -z "$input" ]; then
    echo "未输入任何编号，退出。"
    exit 0
fi

# 将中文逗号替换为英文逗号，然后用正则将所有逗号或空格替换为空格，最后拆分成数组
formatted_input=$(echo "$input" | tr '，' ',' | tr ',' ' ')
read -ra selected <<< "$formatted_input"

# 记录成功删除的容器数量
success_count=0

# 遍历并处理选中的容器
for num in "${selected[@]}"; do
    # 确保是有效数字
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "⚠️ 忽略无效输入: [$num]"
        continue
    fi
    
    index=$((num - 1))
    if [ $index -ge 0 ] && [ $index -lt ${#containers[@]} ]; then
        full_info="${containers[$index]}"
        cid=$(echo "$full_info" | awk -F' \\| ' '{print $1}')
        cname=$(echo "$full_info" | awk -F' \\| ' '{print $2}')
        
        echo "-------------------------------------------------------"
        echo "正在强制删除容器: $cname ($cid)..."
        docker rm -f "$cid" >/dev/null 2>&1
        echo "✅ 容器 $cname 已成功删除。"
        ((success_count++))
    else
        echo "⚠️ 编号 [$num] 超出范围，已跳过。"
    fi
done

echo "-------------------------------------------------------"
if [ $success_count -gt 0 ]; then
    echo "全部处理完成！"
else
    echo "❌ 没有成功删除任何容器。"
fi
