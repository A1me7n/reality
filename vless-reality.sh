#!/bin/bash

# 确保脚本以root身份运行
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

# 严格模式
set -euo pipefail

# 捕获中断信号
trap 'echo "程序已中止"; exit 1' INT TERM

# 函数预加载
getPort() {
    local port
    port=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    while nc -z localhost "$port" >/dev/null; do
        port=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    done
    echo "$port"
}

getIP() {
    local serverIP
    serverIP=$(curl -fsSL http://ipinfo.io/ip)
    echo "${serverIP}"
}

generate_random_domain() {
    local domain_length
    domain_length=$(shuf -i 3-6 -n 1)
    local domain_name
    domain_name=$(shuf -zer -n $domain_length {a..z} | tr -d '\0')
    echo "${domain_name}.com"
}

install_xray() {
    install_pkgs="gawk curl"
    if command -v apt-get >/dev/null; then
        apt-get update -y
        apt-get install -y $install_pkgs
    else
        yum update -y
        yum install -y epel-release $install_pkgs
    fi
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

reconfig() {
    reX25519Key=$(/usr/local/bin/xray x25519)
    rePrivateKey=$(echo "${reX25519Key}" | head -1 | awk '{print $3}')
    rePublicKey=$(echo "${reX25519Key}" | tail -n 1 | awk '{print $3}')

    random_domain=$(generate_random_domain)

    cat >/usr/local/etc/xray/config.json <<EOF
{
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$v2uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "1.1.1.1:443",
                    "xver": 0,
                    "serverNames": [
                        "$random_domain"
                    ],
                    "privateKey": "$rePrivateKey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "88",
                        "123abc"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]    
}
EOF

    systemctl enable xray.service && systemctl restart xray.service
    IP_COUNTRY=$(curl -fsSL http://ipinfo.io/$(getIP)/country)

    log() { echo -e "$1"; }
    success() { log "\033[32m$1\033[0m"; }
    success "安装已经完成"
    success "vless://${v2uuid}@$(getIP):${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$random_domain&fp=chrome&pbk=${rePublicKey}&sid=88&type=tcp&headerType=none#$IP_COUNTRY"

    rm -f tcp-wss.sh install-release.sh reality.sh vless-reality.sh
}

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 生成uuid
v2uuid=$(cat /proc/sys/kernel/random/uuid)

# 获取随机端口
PORT=$(getPort)

# 安装xray
install_xray

# 重新配置
reconfig
