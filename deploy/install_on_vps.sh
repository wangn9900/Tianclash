#!/bin/bash

# ==============================================================================
# TianClash 下载站一键部署脚本 (HTTPS 增强版)
# ==============================================================================
# 功能：
# 1. 自动安装 Nginx
# 2. 自动部署静态下载页
# 3. (可选) 自动申请 SSL 证书并开启 HTTPS (8888端口)
# ==============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ 错误: 请以 root 用户运行此脚本。建议使用 'sudo -i' 切换。${NC}"
  exit 1
fi

echo -e "${GREEN}🚀 开始部署 TianClash 下载站...${NC}"

# 1. 检测并安装 Nginx
echo "----------------------------------------------------------------"
echo -e "${YELLOW}📦 [1/5] 检查/安装 Nginx...${NC}"
echo "----------------------------------------------------------------"
export DEBIAN_FRONTEND=noninteractive
if ! command -v nginx &> /dev/null; then
    apt-get update -qq
    apt-get install -y nginx -qq
else
    echo "✅ Nginx 已安装，跳过安装步骤。"
fi

# 2. 询问域名（用于 SSL）
echo "----------------------------------------------------------------"
echo -e "${YELLOW}🌐 [2/5] 配置域名 (用于 HTTPS)...${NC}"
echo "----------------------------------------------------------------"
echo -e "如果您有域名解析到了这台服务器，我们可以尝试自动申请免费 SSL 证书。"
echo -e "如果没有域名，将仅使用 HTTP 协议。"
echo ""
read -p "👉 请输入您的域名 (留空则跳过 SSL 配置): " DOMAIN_NAME

# 3. 创建目录和文件
echo "----------------------------------------------------------------"
echo -e "${YELLOW}📂 [3/5] 部署网页文件...${NC}"
echo "----------------------------------------------------------------"

WEB_ROOT="/var/www/tianclash/download"
mkdir -p "$WEB_ROOT"

# 写入 index.html
cat > "$WEB_ROOT/index.html" <<'HTML_EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TianClash - 跨平台代理客户端</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Inter', sans-serif; }
        .glass {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
    </style>
</head>
<body class="bg-gradient-to-br from-indigo-900 via-purple-900 to-black min-h-screen text-white flex flex-col">
    <nav class="p-6">
        <div class="container mx-auto flex justify-between items-center">
            <div class="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-purple-400">TianClash</div>
        </div>
    </nav>
    <main class="flex-grow flex items-center justify-center px-4">
        <div class="text-center max-w-4xl">
            <h1 class="text-5xl md:text-7xl font-bold mb-6 tracking-tight">连接世界，<br/><span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-emerald-400">自由无界</span></h1>
            <p class="text-gray-300 text-xl mb-12 max-w-2xl mx-auto">基于 ClashMeta 的下一代跨平台代理客户端。</p>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 max-w-4xl mx-auto">
                <a href="./android-release.apk" class="glass rounded-xl p-6 hover:bg-white/10 transition duration-300 flex flex-col items-center group"><span class="font-semibold">Android</span><span class="text-xs text-gray-400 mt-1">APK</span></a>
                <a href="./windows-setup.exe" class="glass rounded-xl p-6 hover:bg-white/10 transition duration-300 flex flex-col items-center group"><span class="font-semibold">Windows</span><span class="text-xs text-gray-400 mt-1">.exe</span></a>
                <a href="./macos-installer.dmg" class="glass rounded-xl p-6 hover:bg-white/10 transition duration-300 flex flex-col items-center group"><span class="font-semibold">macOS</span><span class="text-xs text-gray-400 mt-1">.dmg</span></a>
                <a href="./linux-appimage.AppImage" class="glass rounded-xl p-6 hover:bg-white/10 transition duration-300 flex flex-col items-center group"><span class="font-semibold">Linux</span><span class="text-xs text-gray-400 mt-1">AppImage</span></a>
            </div>
            <div class="mt-8 text-sm text-gray-500"><p>请将安装包上传至服务器 <code>/var/www/tianclash/download</code></p></div>
        </div>
    </main>
    <footer class="p-6 text-center text-gray-500 text-sm">&copy; 2025 TianClash.</footer>
</body>
</html>
HTML_EOF

chown -R www-data:www-data /var/www/tianclash
chmod -R 755 /var/www/tianclash

# 4. 生成 Nginx 基础配置 (HTTP)
echo "----------------------------------------------------------------"
echo -e "${YELLOW}⚙️ [4/5] 生成 Nginx 基础配置...${NC}"
echo "----------------------------------------------------------------"

NGINX_CONF="/etc/nginx/conf.d/tianclash-download.conf"

# 这里如果用户输入了域名，就用域名，否则用 _
SERVER_NAME_VAL="_"
if [ -n "$DOMAIN_NAME" ]; then
    SERVER_NAME_VAL="$DOMAIN_NAME"
fi

cat > "$NGINX_CONF" <<CONF_EOF
server {
    listen 8888;
    server_name $SERVER_NAME_VAL;

    root /var/www/tianclash/download;
    index index.html;

    gzip on;
    gzip_types text/plain application/javascript text/css;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(apk|hap|exe|dmg|AppImage|zip|tar\.gz)$ {
        sendfile on;
        expires 30d;
    }
}
CONF_EOF

# 5. 尝试 SSL 申请
echo "----------------------------------------------------------------"
echo -e "${YELLOW}🔒 [5/5] 尝试 SSL 证书申请...${NC}"
echo "----------------------------------------------------------------"

SSL_SUCCESS=0

if [ -n "$DOMAIN_NAME" ]; then
    echo "检测到域名: $DOMAIN_NAME，正在安装 Certbot..."
    apt-get install -y certbot python3-certbot-nginx -qq

    echo "正在申请证书 (使用 Nginx 插件)..."
    echo "⚠️ 注意: 这需要您的域名 $DOMAIN_NAME 已解析到本机 IP，且本机 Nginx 配置无冲突。"
    
    # 使用 certonly --nginx，这样 certbot 会自动利用现有的 Nginx (80/443) 进行验证
    # 即使我们的 server 在 8888，certbot 会临时添加一个 80 的验证配置
    if certbot certonly --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --email admin@$DOMAIN_NAME; then
        echo -e "${GREEN}✅ 证书申请成功！正在更新 Nginx 配置以启用 HTTPS...${NC}"
        
        # 获取证书路径
        CERT_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        KEY_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"

        # 重写配置以开启 SSL
cat > "$NGINX_CONF" <<SSL_CONF_EOF
server {
    listen 8888 ssl;
    server_name $DOMAIN_NAME;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    # SSL 优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/tianclash/download;
    index index.html;

    gzip on;
    gzip_types text/plain application/javascript text/css;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(apk|hap|exe|dmg|AppImage|zip|tar\.gz)$ {
        sendfile on;
        expires 30d;
    }
}
SSL_CONF_EOF
        SSL_SUCCESS=1
    else
        echo -e "${RED}❌ 证书申请失败。可能原因：域名未解析到本机，或 Nginx 80 端口验证冲突。${NC}"
        echo "我们将回退到 HTTP 模式。"
    fi
else
    echo "未提供域名，跳过 SSL 配置。"
fi

# 重启 Nginx
if nginx -t; then
    systemctl restart nginx
    
    IP=$(curl -s4 ifconfig.me || hostname -I | awk '{print $1}')
    
    echo ""
    echo "================================================================"
    echo -e "${GREEN}🎉 部署完成！${NC}"
    echo "================================================================"
    
    if [ "$SSL_SUCCESS" -eq 1 ]; then
        echo -e "🔗 访问地址: ${GREEN}https://$DOMAIN_NAME:8888${NC}"
    else
        if [ -n "$DOMAIN_NAME" ]; then
             echo -e "🔗 访问地址: http://$DOMAIN_NAME:8888"
        else
             echo -e "🔗 访问地址: http://$IP:8888"
        fi
    fi
    
    echo "📂 文件目录: $WEB_ROOT"
    echo "💡 请记得将 .apk/.exe 等文件上传到该目录。"
    echo "================================================================"
else
    echo -e "${RED}❌ Nginx 配置文件有误，请检查 /var/log/nginx/error.log${NC}"
fi
