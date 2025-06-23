#!/bin/bash
set -e

function install_deploy() {
  echo "🚀 开始安装部署流程..."

  apt update
  apt install -y git curl wget jq gnupg2

  echo "📥 导入 Caddy 公钥..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor > /usr/share/keyrings/caddy-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/caddy-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy.list

  apt update
  apt install -y caddy

  echo "🌐 克隆网页仓库..."
  read -p "请输入 Git 仓库地址（如 https://github.com/user/repo.git）: " GIT_REPO
  WEB_ROOT="/var/www/mysite"
  if [ ! -d "$WEB_ROOT" ]; then
    git clone --depth=1 "$GIT_REPO" "$WEB_ROOT"
  else
    echo "⚠️ 目录 $WEB_ROOT 已存在，跳过克隆"
  fi

  echo "☁️ 安装 cloudflared..."
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O cloudflared.deb
  dpkg -i cloudflared.deb || true

  echo "🌐 请在浏览器中完成 Cloudflare 登录授权..."
  cloudflared login

  read -p "请输入子域名前缀（如 blog）: " SUBDOMAIN
  read -p "请输入 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME

  cloudflared tunnel create "$TUNNEL_NAME" --output json > tunnel.json
  TUNNEL_ID=$(jq -r '.TunnelID' tunnel.json)
  CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

  BASE_DOMAIN=$(grep -oP '(?<=CN=)[^ ]+' ~/.cloudflared/cert.pem)
  DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"

  echo "📝 写入 Caddy 配置..."
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

  echo "📝 写入 cloudflared 配置..."
  mkdir -p ~/.cloudflared
  cat > ~/.cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

  cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"

  echo "🛠️ 配置 cloudflared systemd 服务..."
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

  systemctl daemon-reload
  systemctl enable --now cloudflared

  echo "📅 添加自动拉取更新任务..."
  (crontab -l 2>/dev/null; echo "0 */12 * * * cd $WEB_ROOT && git pull --quiet") | crontab -

  echo "✅ 部署完成！访问：https://${DOMAIN}"
}

function uninstall_cleanup() {
  echo "⚠️ 将卸载部署内容和 DNS/Tunnel 配置"
  read -p "确认请输入 YES: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "❌ 取消卸载"
    return
  fi

  read -p "请输入 Tunnel 名称（如 mytunnel）: " TUNNEL_NAME
  read -p "请输入子域名前缀（如 blog）: " SUBDOMAIN

  systemctl stop cloudflared || true
  systemctl disable cloudflared || true
  rm -f /etc/systemd/system/cloudflared.service

  rm -rf ~/.cloudflared
  rm -f cloudflared.deb
  rm -f /usr/local/bin/cloudflared

  systemctl stop caddy || true
  systemctl disable caddy || true
  apt purge -y caddy
  rm -rf /etc/caddy /var/log/caddy

  rm -rf /var/www/mysite
  crontab -l | grep -v 'git pull' | crontab -

  if [ -f ~/.cloudflared/cert.pem ]; then
    BASE_DOMAIN=$(grep -oP '(?<=CN=)[^ ]+' ~/.cloudflared/cert.pem)
    cloudflared tunnel route dns delete "$TUNNEL_NAME" "$SUBDOMAIN"
    cloudflared tunnel delete "$TUNNEL_NAME"
  fi

  echo "✅ 卸载完成"
}

function show_menu() {
  echo
  echo "======================="
  echo "  NAT 小鸡管理工具"
  echo "======================="
  echo "1) 一键安装部署"
  echo "2) 一键卸载清理"
  echo "3) 退出"
  read -p "请选择操作 [1-3]: " choice
  case "$choice" in
    1) install_deploy ;;
    2) uninstall_cleanup ;;
    3) exit 0 ;;
    *) echo "无效选项" ;;
  esac
}

while true; do
  show_menu
done
