<powershell>
# User data for the hands-on web server (Windows Server).
# Installs IIS, ASP.NET and Git. The application itself is deployed by hand:
#   git clone --branch v1.0.0 https://github.com/i13602/aws-handson-sample-app.git C:\handson-app
#   C:\handson-app\setup.ps1
# Log: C:\handson-userdata.log
# Note: keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
Start-Transcript -Path 'C:\handson-userdata.log' -Append

try {
    Write-Output 'Installing IIS and ASP.NET...'
    Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Console | Out-Null

    Write-Output 'Installing Git for Windows...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $fallbackUrl = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe'
    $installerUrl = $fallbackUrl
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -match '^Git-[0-9.]+-64-bit\.exe$' } | Select-Object -First 1
        if ($asset) { $installerUrl = $asset.browser_download_url }
    } catch {
        Write-Output ('Could not look up the latest release. Using the fallback version. ' + $_.Exception.Message)
    }
    Write-Output ('Downloading ' + $installerUrl)
    $installer = Join-Path $env:TEMP 'git-installer.exe'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $installerUrl -OutFile $installer -UseBasicParsing
    $process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw ('Git installer failed. Exit code: ' + $process.ExitCode) }
    Remove-Item $installer -Force

    Write-Output 'Done.'
} catch {
    Write-Output ('FAILED: ' + $_.Exception.Message)
    throw
} finally {
    Stop-Transcript
}
</powershell>
