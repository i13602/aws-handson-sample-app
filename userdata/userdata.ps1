<powershell>
# User data for the hands-on web server (Windows Server).
# Installs IIS, ASP.NET and Git. The application itself is deployed by hand:
#   git clone --branch v1.0.1 https://github.com/i13602/aws-handson-sample-app.git C:\handson-app
#   C:\handson-app\setup.ps1
# Log: C:\handson-userdata.log
# Note: keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
Start-Transcript -Path 'C:\handson-userdata.log' -Append

try {
    Write-Output 'Installing IIS and ASP.NET...'
    Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Console | Out-Null

    Write-Output 'Installing Git for Windows...'
    # The version is pinned so that every learner gets the same Git.
    # To change it, update both lines below to the same release.
    # Release list: https://github.com/git-for-windows/git/releases
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $gitVersion = '2.56.0.windows.2'
    $installerUrl = 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/Git-2.56.0.2-64-bit.exe'
    Write-Output ('Git version: ' + $gitVersion)
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
