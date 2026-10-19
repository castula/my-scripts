#!/bin/bash

sudo sed -i '/# BEGIN ADOBE BLOCK /,/# END ADOBE BLOCK/d' /etc/hosts && \
echo '# BEGIN ADOBE BLOCK' | sudo tee -a /etc/hosts >/dev/null && \
curl -fsSL https://a.dove.isdumb.one/list.txt | sudo tee -a /etc/hosts >/dev/null && \
echo '# END ADOBE BLOCK' | sudo tee -a /etc/hosts >/dev/null
