$content = Get-Content '.github\workflows\build_oem.yml' -Raw
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-Android', '${{ github.event.inputs.binaryName }}-Android'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-Windows', '${{ github.event.inputs.binaryName }}-Windows'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-macOS', '${{ github.event.inputs.binaryName }}-macOS'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-Linux', '${{ github.event.inputs.binaryName }}-Linux'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-All-Platforms', '${{ github.event.inputs.binaryName }}-All-Platforms'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-\*', '${{ github.event.inputs.binaryName }}-*'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}\.dmg', '${{ github.event.inputs.binaryName }}.dmg'
$content = $content -replace '\$\{\{ github\.event\.inputs\.appName \}\}-Linux\.tar\.gz', '${{ github.event.inputs.binaryName }}-Linux.tar.gz'
$content | Set-Content '.github\workflows\build_oem.yml' -NoNewline
Write-Host "Done!"
