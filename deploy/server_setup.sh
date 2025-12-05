#!/bin/bash

# 确保以 root 运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请以 root 身份运行此脚本: sudo ./server_setup.sh"
  exit 1
fi

echo "🚀 开始在 Debian 11 上配置 Nginx 下载站..."

# 1. 更新源并安装 Nginx
echo "📦 [1/4] 更新系统并安装 Nginx..."
apt update -q
apt install -y nginx -q

# 2. 创建网站目录
echo "📂 [2/4] 创建网站目录 /var/www/tianclash/download..."
mkdir -p /var/www/tianclash/download
# 创建一个空的 index.html 以防 403 错误（之后会被上传的文件覆盖）
if [ ! -f /var/www/tianclash/download/index.html ]; then
    echo "<h1>Site is ready, please upload files.</h1>" > /var/www/tianclash/download/index.html
fi

# 设置权限 (Debian 上 Nginx 默认用户通常是 www-data)
chown -R www-data:www-data /var/www/tianclash
chmod -R 755 /var/www/tianclash

# 3. 写入 Nginx 配置
echo "⚙️ [3/4] 写入 Nginx 配置文件..."
cat > /etc/nginx/conf.d/tianclash-download.conf <<EOF
server {
    listen 8888;
    server_name _;

    # 开启 gzip 压缩
    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_comp_level 5;
    gzip_types text/plain application/javascript application/x-javascript text/css application/xml text/javascript application/x-httpd-php image/jpeg image/gif image/png;
    gzip_vary on;

    # 静态文件根目录
    root /var/www/tianclash/download;
    index index.html;

    # 允许跨域 (如果需要)
    add_header Access-Control-Allow-Origin *;

    location / {
        try_files \$uri \$uri/ =404;
        # 首页不缓存，确保用户看到最新版本
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # 针对大文件的优化配置
    location ~* \.(apk|hap|exe|dmg|AppImage|zip|tar\.gz)$ {
        # 开启大文件下载支持
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        
        # 强缓存配置，因为版本通常会变文件名
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
EOF

# 4. 验证并重启
echo "🔄 [4/4] 验证配置并重启服务..."
nginx -t
if [ $? -eq 0 ]; then
    systemctl enable nginx
    systemctl restart nginx
    echo "✅ Nginx 重启成功！"
    
    # 获取本机公网 IP (尝试获取，如果失败则提示用户手动查看)
    IP=$(curl -s ifconfig.me || echo "Your-Server-IP")
    echo ""
    echo "🎉 部署完成！"
    echo "👉 您的下载页地址: http://$IP:8888"
    echo "⚠️ 请确保防火墙（如系统自带防火墙或云服务商的安全组）已放行 TCP 8888 端口。"
else
    echo "❌ Nginx 配置验证失败，请检查 /etc/nginx/conf.d/tianclash-download.conf"
    exit 1
fi
