#!/bin/bash

containers=$(docker ps -q)

if [ -z "$containers" ]; then
  echo "当前没有运行中的容器。"
  exit 0
fi

for cid in $containers; do
  if docker exec "$cid" sh -c "command -v cat" >/dev/null 2>&1 && \
     docker exec "$cid" sh -c "[ -f /etc/os-release ]"; then

    os_id=$(docker exec "$cid" sh -c "grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '\"'")

    if [ "$os_id" != "alpine" ]; then
      cname=$(docker inspect --format '{{.Name}}' "$cid" | sed 's/^\/\(.*\)/\1/')
      echo "$cname"
    fi
  fi
done
