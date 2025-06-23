#!/bin/bash
set -e

function install_deploy() {
  echo "开始安装部署流程..."
  bash <<'DEPLOY_EOF'
#!/bin/bash
set -e

echo "🚀 更新软件包列表..."
apt update

echo "📦 安装必要工具..."
apt install -y git curl wget jq gnupg2

echo "📦 导入 Caddy 公钥并添加软件源..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor | tee /usr/share/keyrings/caddy-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/caddy-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy-stable.list

apt update
apt install -y caddy

echo "🌐 克隆网页仓库..."
read -p "请输入你的 Git 仓库地址（如 https://github.com/xxx/xxx.git）: " GIT_REPO
WEB_ROOT="/var/www/mysite"
git clone --depth=1 "$GIT_REPO" "$WEB_ROOT" || echo "仓库已存在，跳过"

echo "☁️ 安装 cloudflared..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O cloudflared.deb
dpkg -i cloudflared.deb || true

echo
echo "🌐 即将打开浏览器进行 Cloudflare 账户授权"
echo "👉 请在浏览器中选择你要绑定的主域名（如 example.com）"
echo "⚠️ 这一步只需执行一次，成功后将在本地生成 ~/.cloudflared/cert.pem"
echo "✅ 登录成功后，回到终端继续执行即可"
echo
cloudflared login

read -p "请输入要绑定的子域名前缀（如 blog）: " SUBDOMAIN
read -p "请输入 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME

echo "⌛ 创建 Cloudflare Tunnel..."
cloudflared tunnel create "$TUNNEL_NAME" --output json > tunnel.json
TUNNEL_ID=$(jq -r '.TunnelID' tunnel.json)
CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

BASE_DOMAIN=$(grep -oP '(?<=CN=)[^ ]+' ~/.cloudflared/cert.pem)
DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"

echo "⚙️ 配置 Caddy（限速 + 日志）..."
cat <<CADDY_EOF > /etc/caddy/Caddyfile
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
CADDY_EOF

mkdir -p /var/log/caddy
systemctl restart caddy

echo "📝 写入 cloudflared 配置文件..."
mkdir -p ~/.cloudflared
cat <<CONFIG_EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - service: http_status:404
CONFIG_EOF

cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"

echo "📌 配置 cloudflared 后台运行..."
cat <<SERVICE_EOF > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel run $TUNNEL_NAME
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now cloudflared

echo "⏱️ 设置网页每日自动更新（cron）..."
(crontab -l 2>/dev/null; echo "0 */12 * * * cd $WEB_ROOT && git pull --quiet") | crontab -

echo
echo "🎉 部署完成！访问地址：https://${DOMAIN}"
echo "📁 网站目录：$WEB_ROOT"
echo "📜 访问日志：/var/log/caddy/access.log"
echo "🛡️ IP 限流：每 10 秒最多 5 次访问"
DEPLOY_EOF
}

function uninstall_cleanup() {
  echo "⚠️ 警告：该操作将永久删除部署内容及 Cloudflare Tunnel 与 DNS 配置。"
  read -p "输入 YES 确认卸载: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "❌ 取消卸载。"
    return
  fi

  echo "🛑 停止 cloudflared..."
  systemctl stop cloudflared || true
  systemctl disable cloudflared || true
  rm -f /etc/systemd/system/cloudflared.service

  echo "🗑️ 删除 cloudflared 配置和证书..."
  rm -rf ~/.cloudflared
  rm -f cloudflared.deb
  rm -f /usr/local/bin/cloudflared

  echo "🛑 停止并卸载 Caddy..."
  systemctl stop caddy || true
  systemctl disable caddy || true
  apt purge -y caddy
  rm -rf /etc/caddy
  rm -rf /var/log/caddy

  echo "🗑️ 删除网页目录..."
  rm -rf /var/www/mysite

  echo "🧹 清除 Git 自动更新任务..."
  crontab -l 2>/dev/null | grep -v 'git pull' | crontab - || true

  read -p "请输入你要删除的 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME
  read -p "请输入绑定的子域名前缀（如 blog）: " SUBDOMAIN

  if [ -f "$HOME/.cloudflared/cert.pem" ]; then
    BASE_DOMAIN=$(grep -oP '(?<=CN=)[^ ]+' ~/.cloudflared/cert.pem)
    DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"

    echo "🌐 尝试删除 DNS 记录：$DOMAIN"
    cloudflared tunnel route dns delete "$TUNNEL_NAME" "$SUBDOMAIN" || echo "⚠️ DNS 删除失败"

    echo "💀 删除 Cloudflare Tunnel：$TUNNEL_NAME"
    cloudflared tunnel delete "$TUNNEL_NAME" || echo "⚠️ Tunnel 删除失败"
  else
    echo "⚠️ 未找到 Cloudflare 认证凭证，跳过云端清理"
  fi

  echo "✅ 卸载完成。"
}

function show_menu() {
  clear
  echo "=========================="
  echo "  NAT 小鸡管理脚本菜单"
  echo "=========================="
  echo "1) 一键安装部署"
  echo "2) 一键卸载清理"
  echo "3) 退出"
  echo
  read -p "请选择操作 [1-3]: " choice
  case "$choice" in
    1) install_deploy ;;
    2) uninstall_cleanup ;;
    3) echo "退出脚本"; exit 0 ;;
    *) echo "无效选项"; sleep 1; show_menu ;;
  esac
}

while true; do
  show_menu
done
