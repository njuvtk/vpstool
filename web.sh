#!/bin/bash
set -e

echo "🚀 开始部署 Cloudflare Tunnel + Caddy 静态网站"

# 👉 1. 安装依赖
echo "📦 安装 Caddy..."
apt update
apt install -y curl wget

curl -fsSL https://get.caddyserver.com | bash

echo "📁 创建网站目录..."
mkdir -p /var/www/mysite
echo "<h1>Hello from NAT via Cloudflare Tunnel</h1>" > /var/www/mysite/index.html

echo "📝 配置 Caddy（本地监听 80）..."
cat <<EOF > /etc/caddy/Caddyfile
:80 {
    root * /var/www/mysite
    file_server
}
EOF

systemctl restart caddy

# 👉 2. 安装 cloudflared
echo "☁️ 安装 cloudflared..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb || true # 忽略重复安装的错误

# 👉 3. 登录 Cloudflare
echo "🌐 将打开浏览器登录 Cloudflare，请选择你的域名授权"
cloudflared login

# 👉 4. 输入你的域名和 tunnel 名称
read -p "请输入你要绑定的完整域名（如 blog.example.com）: " DOMAIN
read -p "请输入 tunnel 名称（比如 mytunnel）: " TUNNEL_NAME

echo "📡 创建 Tunnel：$TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME"

# 获取 tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
CRED_FILE="/root/.cloudflared/${TUNNEL_ID}.json"

echo "🛠️ 写入配置文件 ~/.cloudflared/config.yml"
mkdir -p ~/.cloudflared

cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

echo "🔗 绑定 DNS：$DOMAIN"
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

echo "📌 创建 systemd 启动服务..."
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

echo "✅ 部署完成！你的网站已上线：https://$DOMAIN"
