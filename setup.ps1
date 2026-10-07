#Requires -RunAsAdministrator
<#
.SYNOPSIS
    構成確認ページを IIS に配置する。

.DESCRIPTION
    1. IIS と ASP.NET の機能が入っていなければ、入れる。
    2. site フォルダの中身を C:\inetpub\handson にコピーする。
    3. IIS の既定のサイト（Default Web Site）が、そのフォルダを表示するようにする。
    4. http://localhost/health.html が応答することを確かめる。

    何度実行しても同じ結果になる。DB の接続情報（connection.config）は、
    すでにある場合は上書きしない。

.EXAMPLE
    C:\handson-app\setup.ps1
#>
$ErrorActionPreference = 'Stop'

$SourceDir = Join-Path $PSScriptRoot 'site'
$TargetDir = 'C:\inetpub\handson'
$SiteName = 'Default Web Site'

Write-Host '[1/4] IIS と ASP.NET の機能を確認します...'
$featureNames = @('Web-Server', 'Web-Asp-Net45', 'Web-Mgmt-Console')
$missing = @(Get-WindowsFeature -Name $featureNames | Where-Object { -not $_.Installed })
if ($missing.Count -gt 0) {
    Write-Host ('      入っていない機能を入れます: ' + (($missing | ForEach-Object { $_.Name }) -join ', '))
    Install-WindowsFeature -Name ($missing | ForEach-Object { $_.Name }) | Out-Null
}

Write-Host "[2/4] ファイルを $TargetDir にコピーします..."
if (-not (Test-Path $SourceDir)) {
    throw "コピー元のフォルダが見つかりません: $SourceDir"
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
Get-ChildItem -Path $SourceDir -File | Where-Object { $_.Name -ne 'connection.config' } | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $TargetDir -Force
}
$connectionConfig = Join-Path $TargetDir 'connection.config'
if (Test-Path $connectionConfig) {
    Write-Host '      DB の接続情報は、すでにあるものをそのまま使います。'
} else {
    Copy-Item -Path (Join-Path $SourceDir 'connection.config') -Destination $connectionConfig
}

Write-Host "[3/4] IIS のサイト「$SiteName」の表示先を切り替えます..."
Import-Module WebAdministration
Set-ItemProperty -Path "IIS:\Sites\$SiteName" -Name physicalPath -Value $TargetDir
if ((Get-Website -Name $SiteName).State -ne 'Started') {
    Start-Website -Name $SiteName
}

Write-Host '[4/4] 動作を確かめます...'
Start-Sleep -Seconds 2
$response = Invoke-WebRequest -Uri 'http://localhost/health.html' -UseBasicParsing -TimeoutSec 30
if ($response.StatusCode -ne 200) {
    throw "health.html が応答しません（状態コード: $($response.StatusCode)）"
}

Write-Host ''
Write-Host '配置が終わりました。' -ForegroundColor Green
Write-Host 'このサーバーのブラウザで http://localhost/ を開いて、構成確認ページを確認してください。'
