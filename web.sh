#!/bin/bash
set -e

echo "🚀 安装依赖..."
apt update
apt install -y git curl wget debian-keyring debian-archive-keyring gnupg apt-transport-https

# ========= 安装 Caddy =========
echo "📦 安装 Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | tee /etc/apt/trusted.gpg.d/caddy.gpg > /dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy -y

# ========= 拉取 Git 网页 =========
echo "🌐 克隆网页仓库..."
read -p "请输入你的 Git 仓库地址（如 https://github.com/xxx/xxx.git）: " GIT_REPO
WEB_ROOT="/var/www/mysite"
git clone --depth=1 "$GIT_REPO" "$WEB_ROOT" || echo "仓库已存在，跳过"

# ========= 安装 cloudflared =========
echo "☁️ 安装 cloudflared..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O cloudflared.deb
dpkg -i cloudflared.deb || true

# ========= 登录提示 =========
echo
echo "🌐 即将打开浏览器进行 Cloudflare 账户授权"
echo "👉 请在浏览器中选择你要绑定的主域名（如 example.com）"
echo "⚠️ 这一步只需执行一次，成功后将在本地生成 ~/.cloudflared/cert.pem"
echo "✅ 登录成功后，回到终端继续执行即可"
echo
cloudflared login

# ========= 获取子域名前缀 + Tunnel名 =========
read -p "请输入要绑定的子域名前缀（如 blog）: " SUBDOMAIN
read -p "请输入 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME

# ========= 创建 Tunnel =========
cloudflared tunnel create "$TUNNEL_NAME"
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
CRED_FILE="/root/.cloudflared/${TUNNEL_ID}.json"

# 获取主域名（从 cert.pem 提取）
BASE_DOMAIN=$(grep -oP '(?<=CN=)[^ ]+' ~/.cloudflared/cert.pem)
DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"

# ========= 写入 Caddy 配置 =========
echo "⚙️ 配置 Caddy（限速 + 日志）..."
cat <<EOF > /etc/caddy/Caddyfile
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

mkdir -p /var/log/caddy
systemctl restart caddy

# ========= 写入 cloudflared 配置文件 =========
echo "📝 写入 cloudflared 配置文件..."
mkdir -p ~/.cloudflared
cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

# ========= 正确方式绑定子域名（只填前缀） =========
cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"

# ========= 写入 systemd 后台服务 =========
echo "📌 配置 cloudflared 后台运行..."
cat <<EOF > /etc/systemd/system/cloudflared.service
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

# ========= 设置定时网页更新任务 =========
echo "⏱️ 设置网页每日自动更新（cron）..."
(crontab -l 2>/dev/null; echo "0 */12 * * * cd $WEB_ROOT && git pull --quiet") | crontab -

# ========= 完成提示 =========
echo
echo "🎉 部署完成！你的网站现在可以通过以下地址访问："
echo "🌐 https://${DOMAIN}"
echo "📁 网站目录：$WEB_ROOT"
echo "📜 访问日志：/var/log/caddy/access.log"
echo "🛡️ 每 IP 10 秒内限访问 5 次（Caddy rate_limit）"
echo
