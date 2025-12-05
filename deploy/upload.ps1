# 配置部分
$ServerIP = "your_vps_ip"
$ServerUser = "root"
$RemotePath = "/var/www/tianclash/download"
$LocalBuildPath = "..\build" # 假设脚本在 deploy 目录，build 在上一级

# 检查是否提供了 IP
if ($ServerIP -eq "your_vps_ip") {
    Write-Host "⚠️ 请先用文本编辑器打开此脚本，将 `$ServerIP` 修改为你的 VPS IP 地址！" -ForegroundColor Red
    exit
}

Write-Host "🚀 开始连接 $ServerIP (Debian 11)..."

# 0. 上传并执行初始化脚本 (只需执行一次)
Write-Host "🛠️ 上传服务器初始化脚本..."
scp .\server_setup.sh "${ServerUser}@${ServerIP}:/root/"
Write-Host "🔧 正在执行服务器初始化 (安装 Nginx 等)..."
ssh "${ServerUser}@${ServerIP}" "chmod +x /root/server_setup.sh && /root/server_setup.sh"

Write-Host "`n📦 开始上传文件..."

# 1. 上传 index.html
Write-Host "📄 上传页面文件..."
scp .\download\index.html "${ServerUser}@${ServerIP}:${RemotePath}/"

# 2. 上传 Android APK
$AndroidPath = "$LocalBuildPath\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $AndroidPath) {
    Write-Host "📱 上传 Android APK..."
    scp $AndroidPath "${ServerUser}@${ServerIP}:${RemotePath}/android-release.apk"
}
else {
    Write-Host "⚠️ 未找到 Android APK (跳过): $AndroidPath" -ForegroundColor Yellow
}

# 3. 上传 Windows EXE
$WindowsPath = "$LocalBuildPath\windows\runner\Release\TianClash_Setup.exe" # 需确认生成路径
if (Test-Path $WindowsPath) {
    Write-Host "💻 上传 Windows Installer..."
    scp $WindowsPath "${ServerUser}@${ServerIP}:${RemotePath}/windows-setup.exe"
}
else {
    Write-Host "⚠️ 未找到 Windows Installer (跳过): $WindowsPath" -ForegroundColor Yellow
}

# 4. 上传 macOS DMG (如果存在)
$MacPath = "$LocalBuildPath\macos\Build\Products\Release\TianClash.dmg"
if (Test-Path $MacPath) {
    Write-Host "🍎 上传 macOS Image..."
    scp $MacPath "${ServerUser}@${ServerIP}:${RemotePath}/macos-installer.dmg"
}

# 5. 上传 Linux AppImage (如果存在)
$LinuxPath = "$LocalBuildPath\linux\out\TianClash.AppImage"
if (Test-Path $LinuxPath) {
    Write-Host "🐧 上传 Linux AppImage..."
    scp $LinuxPath "${ServerUser}@${ServerIP}:${RemotePath}/linux-appimage.AppImage"
}

Write-Host "✅ 所有操作完成！" -ForegroundColor Green
