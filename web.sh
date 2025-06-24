#!/bin/bash

set -euo pipefail
LOG_FILE="/var/log/deploy-web.log"
exec > >(tee -a "$LOG_FILE") 2>&1

SITE_DIR="/var/www/mysite"
CADDYFILE="/etc/caddy/Caddyfile"
TUNNEL_NAME=""
CRON_FILE="/etc/cron.d/github-site-pull"
FULL_DOMAIN=""

function set_tunnel_name() {
    echo "🌐 正在检测是否已有 cloudflared Tunnel..."
    if ls ~/.cloudflared/*.json >/dev/null 2>&1; then
        echo "✅ 检测到已有 Tunnel："
        ls ~/.cloudflared/*.json | xargs -n1 basename | cut -d'.' -f1
        read -p "是否使用已有 Tunnel 名称？(y/n): " USE_EXISTING
        if [[ "$USE_EXISTING" == "y" ]]; then
            TUNNEL_NAME=$(ls ~/.cloudflared/*.json | head -n1 | xargs -n1 basename | cut -d'.' -f1)
            echo "✅ 使用已有 Tunnel：$TUNNEL_NAME"
            return
        fi
    fi
    read -p "🔧 请输入要创建的 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME
}

function install_dependencies() {
    echo "🛠️ 检查并安装必要依赖..."
    for cmd in curl gnupg git wget cron; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "➡️ 安装 $cmd..."
            apt update
            apt install -y $cmd
            echo "等待3秒，避免资源占用过高..."
            sleep 3
        else
            echo "✔️ 已安装 $cmd，跳过"
        fi
    done
    systemctl enable cron --now
}

function install_caddy() {
    echo "📦 安装 Caddy..."
    mkdir -p /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg ]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor | tee /etc/apt/keyrings/caddy-stable-archive-keyring.gpg > /dev/null
    fi
    echo "deb [signed-by=/etc/apt/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
}

function setup_caddyfile() {
    echo "✅ 配置 Caddyfile..."
    mkdir -p /etc/caddy /var/log/caddy
    cat > "$CADDYFILE" <<EOF
:80 {
    root * $SITE_DIR
    file_server
    encode gzip

    log {
        output file /var/log/caddy/access.log
        format json
    }
}
EOF
}

function clone_site_repo() {
    read -p "✨ 请输入 GitHub 页面仓库地址（https://github.com/xxx/xxx.git）: " GIT_REPO
    echo "🌐 克隆 GitHub 网页..."
    mkdir -p "$SITE_DIR"
    if [ -d "$SITE_DIR/.git" ]; then
        echo "📁 已存在 Git 仓库，跳过 clone"
    else
        git clone "$GIT_REPO" "$SITE_DIR"
    fi

    echo "⏰ 配置定时更新任务..."
    echo "*/10 * * * * root cd $SITE_DIR && git pull --quiet" > "$CRON_FILE"
    chmod 644 "$CRON_FILE"
}

function install_cloudflared() {
    echo "☁️ 安装 cloudflared..."
    wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x /usr/local/bin/cloudflared
}

function configure_cloudflare_tunnel() {
    read -p "🌐 请输入主域名（如 example.com）: " DOMAIN
    read -p "🔹 请输入要绑定的子域前缀（如 blog）: " SUBDOMAIN
    FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"
    export FULL_DOMAIN

    cloudflared login
    cloudflared tunnel create "$TUNNEL_NAME"

    echo "✨ 生成 cloudflared config.yml..."
    mkdir -p ~/.cloudflared
    TUNNEL_ID=$(cat ~/.cloudflared/*.json | grep -o '"TunnelID":"[^"]\+"' | cut -d '"' -f4)
    cat > ~/.cloudflared/config.yml <<EOF
  tunnel: $TUNNEL_ID
  credentials-file: /root/.cloudflared/$TUNNEL_ID.json

  ingress:
    - hostname: $FULL_DOMAIN
      service: http://localhost:80
    - service: http_status:404
EOF

    cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"
}

function start_services() {
    echo "🚀 启动服务..."
    systemctl restart caddy || nohup caddy run --config /etc/caddy/Caddyfile --adapter caddyfile > /var/log/caddy/caddy.log 2>&1 &
    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel run $TUNNEL_NAME
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable cloudflared --now
    sleep 2
    systemctl is-active --quiet cloudflared || {
        echo "⚠️ cloudflared 启动失败，尝试手动启动..."
        nohup cloudflared tunnel run $TUNNEL_NAME > /var/log/cloudflared.log 2>&1 &
        sleep 1
    }
    echo "✅ 所有服务已启动并设置为开机自启"
    if [[ -n "$FULL_DOMAIN" ]]; then
      echo "🌐 你现在可以通过以下地址访问你的网站："
      echo "👉 https://$FULL_DOMAIN"
    fi
}

function uninstall_all() {
    echo "🗑️ 开始卸载部署环境..."
    pkill cloudflared || true
    systemctl stop caddy || pkill caddy || true
    systemctl disable cloudflared || true
    rm -f /etc/systemd/system/cloudflared.service
    apt purge -y caddy git
    rm -rf /usr/local/bin/cloudflared /etc/caddy /var/www/mysite ~/.cloudflared /var/log/caddy /var/log/cloudflared.log "$CRON_FILE" /var/log/deploy-web.log
    rm -f /etc/apt/sources.list.d/caddy-stable.list /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
    apt autoremove -y
    apt clean
    echo "✅ 卸载完成"
}

function show_menu() {
    echo "=============================="
    echo "🌐 静态站部署脚本菜单"
    echo "1. 安装依赖"
    echo "2. 安装 Caddy"
    echo "3. 配置 Caddy"
    echo "4. 克隆网页仓库 + 定时更新"
    echo "5. 安装 cloudflared 并配置 Tunnel"
    echo "6. 启动服务并设置开机自启"
    echo "7. 一键全自动部署"
    echo "8. 一键删除部署环境"
    echo "0. 退出"
    echo "=============================="
}

while true; do
    show_menu
    read -p "请输入选项 [0-8]: " CHOICE
    case $CHOICE in
        1) install_dependencies;;
        2) install_caddy;;
        3) setup_caddyfile;;
        4) clone_site_repo;;
        5) install_cloudflared; set_tunnel_name; configure_cloudflare_tunnel;;
        6) start_services;;
        7)
            install_dependencies
            install_caddy
            setup_caddyfile
            clone_site_repo
            install_cloudflared
            set_tunnel_name
            configure_cloudflare_tunnel
            start_services
            echo "🎉 自动部署完成，网站已上线。"
            ;;
        8) uninstall_all;;
        0) echo "👋 已退出"; exit 0;;
        *) echo "❌ 无效选项，请重新输入。";;
    esac
done
