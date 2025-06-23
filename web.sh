#!/bin/bash
set -e

echo "🧱 安装 Caddy（使用 .deb 包）..."
wget -q https://github.com/caddyserver/caddy/releases/latest/download/caddy_2.7.6_linux_amd64.deb -O caddy.deb
dpkg -i caddy.deb

echo "📁 创建网站目录..."
mkdir -p /var/www/mysite
echo "<h1>Hello from NAT via Tunnel</h1>" > /var/www/mysite/index.html

echo "📝 写入 Caddy 配置..."
cat <<EOF > /etc/caddy/Caddyfile
:80 {
    root * /var/www/mysite
    file_server
}
EOF

systemctl restart caddy

echo "☁️ 安装 cloudflared..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O cloudflared.deb
dpkg -i cloudflared.deb || true

echo "🌐 登录 Cloudflare 并授权域名..."
cloudflared login

read -p "请输入你要绑定的完整域名（如 blog.example.com）: " DOMAIN
read -p "请输入 tunnel 名称（任意英文，如 mytunnel）: " TUNNEL_NAME

echo "🚧 创建 Tunnel..."
cloudflared tunnel create "$TUNNEL_NAME"
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
CRED_FILE="/root/.cloudflared/${TUNNEL_ID}.json"

echo "⚙️ 写入 cloudflared 配置文件..."
mkdir -p ~/.cloudflared
cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

echo "🔗 绑定域名到 Tunnel..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

echo "🛠️ 配置 systemd 后台服务..."
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

echo "🎉 部署完成！你的网站已上线：https://$DOMAIN"
