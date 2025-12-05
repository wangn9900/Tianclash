# 部署指南 (一键脚本版)

本指南提供了一个单文件、全功能的一键部署脚本，适用于 Debian 11 / Ubuntu 系统。

## 🚀 极简部署步骤

### 1. 将脚本上传到 VPS
你可以使用任何你喜欢的 SFTP 工具（如 Xshell, FinalShell, Termius）登录 VPS。

将 `deploy/install_on_vps.sh` 这个文件拖进去 (例如传到 `/root/` 目录)。

### 2. 执行安装命令
在 VPS 的终端中执行这两行命令：

```bash
# 赋予执行权限
chmod +x install_on_vps.sh

# 运行脚本
./install_on_vps.sh
```

脚本运行完毕后，会显示访问地址，例如 `http://1.2.3.4:8888`。

### 3. 上传应用安装包
脚本会自动创建目录：`/var/www/tianclash/download`。

请将构建好的应用包上传到该目录，并**重命名**为以下对应的文件名（网页中写死了这几个名字）：

*   **Android**: `android-release.apk`
*   **Windows**: `windows-setup.exe`
*   **macOS**: `macos-installer.dmg`
*   **Linux**: `linux-appimage.AppImage`

上传完成后，无需重启服务，刷新网页即可点击下载。

---

### (可选) 进阶：如何远程从 GitHub 拉取构建
如果你的构建在 GitHub Actions 完成并发布（Release），你可以在 VPS 上直接下载，不需要从本地上传。

```bash
cd /var/www/tianclash/download
# 替换为你的 Release 链接
wget -O android-release.apk https://github.com/wxfyes/TianClash/releases/download/xxx/app-release.apk
```
