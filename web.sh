#!/bin/bash
set -e

echo "🚀 开始部署流程..."

# 1. 基础依赖安装
apt update
apt install -y git curl wget jq gnupg apt-transport-https debian-keyring debian-archive-keyring

# 2. 安装 Caddy（官方源方式）
echo "📦 安装 Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | tee /etc/apt/trusted.gpg.d/caddy.gpg > /dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy
echo "✅ Caddy 安装完成，版本：$(caddy version)"

# 3. 克隆网页仓库
read -p "📁 请输入 Git 仓库地址（如 https://github.com/xxx/xxx.git）: " GIT_REPO
WEB_ROOT="/var/www/mysite"
[ -d "$WEB_ROOT" ] || git clone --depth=1 "$GIT_REPO" "$WEB_ROOT"

# 4. 安装 cloudflared
echo "☁️ 安装 cloudflared..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O cloudflared.deb
dpkg -i cloudflared.deb || true

# 5. Cloudflare 登录
echo
echo "🌐 请在浏览器中登录 Cloudflare 并选择你的主域名"
cloudflared login

# 6. 创建 tunnel 并提取 ID（修复戛然而止问题）
read -p "🌐 请输入子域名前缀（如 blog）: " SUBDOMAIN
read -p "🚇 请输入 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME
cloudflared tunnel create "$TUNNEL_NAME"

TUNNEL_ID=$(cloudflared tunnel list --output json | jq -r ".[] | select(.Name==\"$TUNNEL_NAME\") | .ID")
CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
BASE_DOMAIN=$(grep -oP '(?<=CN=)[^ ]+' ~/.cloudflared/cert.pem)
DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"

# 7. 写入 Caddy 配置
mkdir -p /var/log/caddy
cat >/etc/caddy/Caddyfile <<EOF
:80 {
    root * $WEB_ROOT
    encode gzip
    file_server

    rate_limit {
        zone addr
        key {remote_host}
        events 5
        window 10s
    }

    log {
        output file /var/log/caddy/access.log
        format console
    }
}
EOF
systemctl restart caddy

# 8. 写入 cloudflared 配置
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

# 9. 绑定 DNS 子域名
cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"

# 10. 写入 cloudflared systemd 启动服务
cat >/etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel run $TUNNEL_NAME
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now cloudflared

# 11. 设置 Git 自动更新
(crontab -l 2>/dev/null; echo "0 */12 * * * cd $WEB_ROOT && git pull --quiet") | crontab -

# 12. 结束提示
echo
echo "🎉 部署完成！"
echo "🔗 访问地址：https://${DOMAIN}"
echo "📁 网站目录：$WEB_ROOT"
echo "📜 日志路径：/var/log/caddy/access.log"
echo "🛡️ 限流策略：10秒内最多访问5次"
