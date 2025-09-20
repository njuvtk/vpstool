#!/bin/bash

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo "无法检测操作系统类型"
        exit 1
    fi
}

# 安装MariaDB (适配多系统)
install_mariadb() {
    echo "=== 检查MariaDB状态 ==="
    
    # 不同系统的MariaDB客户端命令可能不同
    if command_exists mysql || command_exists mariadb; then
        echo "MariaDB已安装"
        read -p "是否重新安装MariaDB? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过MariaDB安装"
            return 0
        fi
    fi

    echo "开始安装MariaDB..."
    
    # 根据操作系统选择安装方式
    if [[ $OS == *"Debian"* || $OS == *"Ubuntu"* ]]; then
        # Debian/Ubuntu 系统
        sudo apt update
        sudo apt install -y mariadb-server
        
        # 服务管理
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    elif [[ $OS == *"CentOS"* && $VER == "7" ]]; then
        # CentOS 7 系统
        sudo yum install -y mariadb-server mariadb
        
        # 服务管理
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    else
        echo "不支持的操作系统: $OS $VER"
        return 1
    fi
    
    # 运行安全配置（带详细交互说明）
    echo -e "\n===== MariaDB安全配置向导即将启动 ====="
    echo "生产环境强烈建议完成所有安全配置步骤，请仔细阅读每个提示！"
    echo -e "\n配置步骤说明："
    echo "1. 输入当前root密码：新安装的MariaDB默认无密码，直接按回车即可"
    echo "2. 切换到unix_socket认证：推荐输入 'n' 保持密码认证方式"
    echo "3. 修改root密码：强烈建议输入 'y' 并设置强密码"
    echo "   - 输入新密码（输入时不会显示）"
    echo "   - 再次输入新密码确认"
    echo "4. 移除匿名用户：强烈建议输入 'y' 提高安全性"
    echo "5. 禁止root远程登录：强烈建议输入 'y' 仅允许本地登录"
    echo "6. 移除测试数据库：强烈建议输入 'y' 删除默认测试库"
    echo "7. 重新加载权限表：输入 'y' 使所有配置立即生效"
    read -p "按Enter键进入安全配置..."
    
    # 不同系统可能使用mysql_secure_installation或mariadb-secure-installation
    if command_exists mysql_secure_installation; then
        sudo mysql_secure_installation
    elif command_exists mariadb-secure-installation; then
        sudo mariadb-secure-installation
    else
        echo "未找到安全配置工具，跳过安全配置"
        return 1
    fi
    
    # 验证安装
    if command_exists mysql || command_exists mariadb; then
        echo "MariaDB安装成功"
    else
        echo "MariaDB安装失败"
        return 1
    fi
}

# 安装Redis (适配多系统)
install_redis() {
    echo -e "\n=== 检查Redis状态 ==="
    
    if command_exists redis-server; then
        echo "Redis已安装"
        read -p "是否重新安装Redis? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过Redis安装"
            return 0
        fi
    fi

    echo "开始安装Redis..."
    
    # 根据操作系统选择安装方式
    if [[ $OS == *"Debian"* || $OS == *"Ubuntu"* ]]; then
        # Debian/Ubuntu 系统
        sudo apt update
        sudo apt install -y redis-server
        
        # 服务管理
        sudo systemctl start redis-server
        sudo systemctl enable redis-server
    elif [[ $OS == *"CentOS"* && $VER == "7" ]]; then
        # CentOS 7 系统
        sudo yum install -y epel-release  # Redis在EPEL源中
        sudo yum install -y redis
        
        # 服务管理
        sudo systemctl start redis
        sudo systemctl enable redis
    else
        echo "不支持的操作系统: $OS $VER"
        return 1
    fi
    
    # 验证安装
    if redis-cli ping | grep -q "PONG"; then
        echo "Redis安装成功"
    else
        echo "Redis安装失败"
        return 1
    fi
}

# 主程序
echo "===== MariaDB和Redis多系统安装工具 ====="
detect_os
echo "已检测到操作系统: $OS $VER"

read -p "是否安装MariaDB? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    install_mariadb
fi

read -p "是否安装Redis? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    install_redis
fi

echo -e "\n===== 操作完成 ====="
    