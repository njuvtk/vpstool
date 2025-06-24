

# 🌐 VPS Web Deploy Tool

一个适用于 Debian 系统的 VPS 静态网页一键部署脚本，整合 Caddy + Cloudflared Tunnel，支持 GitHub Pages 自动同步、定时更新、开机自启、卸载清理等功能，适用于低内存 NAT 机或小型云主机。

## ✨ 功能特色

- ✅ 一键部署静态网页（托管于 GitHub 仓库）
- ✅ 自动安装 Caddy + Cloudflared
- ✅ 自动配置 Cloudflare Tunnel 并绑定子域名
- ✅ 支持开机自启、日志输出、自动更新网页内容
- ✅ 支持卸载脚本、重复部署检测与回退

## 🚀 快速开始

> 建议使用 Debian 11+/Ubuntu 20.04+ 运行

```bash
curl -fsSL https://raw.githubusercontent.com/njuvtk/vpstool/main/web.sh | bash
```

执行后将出现菜单，选择【7】进行一键部署，或按步骤逐项安装。

## 📁 示例网页仓库结构

```bash
https://github.com/yourname/yourpage.git
├── index.html
├── style.css
└── ...
```

> 建议使用 GitHub Pages 架构，支持 `git pull` 同步

## 🔧 脚本功能菜单

| 选项 | 功能说明                           |
| -- | ------------------------------ |
| 1  | 安装依赖（curl/git/cron/wget/gnupg） |
| 2  | 安装并配置 Caddy                    |
| 3  | 自动生成 Caddyfile 配置              |
| 4  | 克隆 GitHub 仓库 + 添加定时任务          |
| 5  | 安装 cloudflared + 创建 Tunnel     |
| 6  | 启动服务并设置 systemd 开机自启           |
| 7  | 🚀 一键部署所有步骤                    |
| 8  | 🗑️ 一键卸载部署环境                   |

## 🌐 部署结果示意

成功后你的网站将自动通过 Cloudflare Tunnel 访问，如：

```
https://subdomain.example.com
```

## 📦 卸载方法

运行脚本并选择【8】即可删除所有部署内容（含服务、文件、依赖等）。

