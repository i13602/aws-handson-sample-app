#Requires -RunAsAdministrator
<#
.SYNOPSIS
    構成確認ページに、DB の接続情報を設定する。

.DESCRIPTION
    1. Parameter Store から、DB の接続先、ユーザー名、パスワードを読み取る。
       読み取りには、このサーバーに付けた IAM ロールの権限を使う（アクセスキーは使わない）。
    2. DB に接続し、アプリ用のデータベースがなければ作る。
    3. 接続情報を C:\inetpub\handson\connection.config に書き込む。
    4. 構成確認ページが DB に接続できることを確かめる。

    Parameter Store には、次の3つを登録しておく（既定の場合）。
        /dkt/db/endpoint   DB の接続先（RDS のエンドポイント）
        /dkt/db/username   DB のユーザー名
        /dkt/db/password   DB のパスワード（SecureString）

.PARAMETER ParameterPrefix
    Parameter Store の名前の先頭部分。既定は /dkt/db

.PARAMETER DatabaseName
    アプリ用のデータベースの名前。既定は handson。英数字とアンダースコアだけが使える。

.EXAMPLE
    C:\handson-app\setup-db.ps1
#>
param(
    [string]$ParameterPrefix = '/dkt/db',
    [string]$DatabaseName = 'handson'
)
$ErrorActionPreference = 'Stop'

$TargetDir = 'C:\inetpub\handson'
$MetadataBase = 'http://169.254.169.254/latest'

function Test-DatabaseName {
    # データベース名を SQL 文に埋め込むので、使える文字を限定する。
    param([string]$Name)
    return ($Name -match '^[A-Za-z][A-Za-z0-9_]{0,62}$')
}

function ConvertTo-DataSource {
    # 「ホスト名:ポート」の形で登録されていた場合は、SQL Server の書き方（ホスト名,ポート）に直す。
    param([string]$Endpoint)
    $value = $Endpoint.Trim()
    if ($value -match '^(?<host>[^:,]+):(?<port>\d+)$') {
        return ($Matches['host'] + ',' + $Matches['port'])
    }
    return $value
}

function New-ConnectionString {
    param([string]$DataSource, [string]$UserName, [string]$Password, [string]$Database)
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $DataSource
    $builder['Initial Catalog'] = $Database
    $builder['User ID'] = $UserName
    $builder['Password'] = $Password
    $builder['Connect Timeout'] = 5
    # 通信は暗号化する。研修用の簡略化として、サーバー証明書の検証は省略している。
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    return $builder.ConnectionString
}

function Save-ConnectionConfig {
    # 記号を含むパスワードでも壊れないよう、XML の機能を使って書き出す。
    param([string]$Path, [string]$ConnectionString)
    $xml = New-Object System.Xml.XmlDocument
    [void]$xml.AppendChild($xml.CreateXmlDeclaration('1.0', 'utf-8', $null))
    $root = $xml.CreateElement('connectionStrings')
    [void]$xml.AppendChild($root)
    $add = $xml.CreateElement('add')
    $add.SetAttribute('name', 'handson')
    $add.SetAttribute('connectionString', $ConnectionString)
    $add.SetAttribute('providerName', 'System.Data.SqlClient')
    [void]$root.AppendChild($add)
    $xml.Save($Path)
}

function Get-InstanceRegion {
    $token = Invoke-RestMethod -Method Put -Uri "$MetadataBase/api/token" `
        -Headers @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '60' } -TimeoutSec 5
    return (Invoke-RestMethod -Uri "$MetadataBase/meta-data/placement/region" `
        -Headers @{ 'X-aws-ec2-metadata-token' = $token } -TimeoutSec 5)
}

function Invoke-Main {
    if (-not (Test-DatabaseName -Name $DatabaseName)) {
        throw "データベース名に使えない文字が含まれています: $DatabaseName"
    }
    if (-not (Test-Path $TargetDir)) {
        throw "$TargetDir が見つかりません。先に setup.ps1 を実行してください。"
    }
    if (-not (Get-Command -Name Get-SSMParameter -ErrorAction SilentlyContinue)) {
        throw 'Get-SSMParameter が使えません。AWS Tools for PowerShell が入っているか確認してください。'
    }

    Write-Host '[1/4] Parameter Store から接続情報を読み取ります...'
    $region = Get-InstanceRegion
    $prefix = $ParameterPrefix.TrimEnd('/')
    try {
        $endpoint = (Get-SSMParameter -Name "$prefix/endpoint" -Region $region).Value
        $userName = (Get-SSMParameter -Name "$prefix/username" -Region $region).Value
        $password = (Get-SSMParameter -Name "$prefix/password" -WithDecryption $true -Region $region).Value
    } catch {
        throw ("Parameter Store から読み取れません。パラメータの名前（$prefix/endpoint、$prefix/username、$prefix/password）と、" +
               "このサーバーの IAM ロールの権限を確認してください。詳細: " + $_.Exception.Message)
    }
    $dataSource = ConvertTo-DataSource -Endpoint $endpoint
    Write-Host "      接続先: $dataSource"

    Write-Host "[2/4] DB に接続し、データベース「$DatabaseName」を用意します..."
    $masterConnection = New-Object System.Data.SqlClient.SqlConnection (
        New-ConnectionString -DataSource $dataSource -UserName $userName -Password $password -Database 'master')
    try {
        $masterConnection.Open()
        $command = $masterConnection.CreateCommand()
        $command.CommandText = "IF DB_ID(N'$DatabaseName') IS NULL CREATE DATABASE [$DatabaseName];"
        [void]$command.ExecuteNonQuery()
    } catch {
        throw ("DB に接続できません。DB が起動しているか、Security Group でこのサーバーからの接続が許可されているか、" +
               "ユーザー名とパスワードが正しいかを確認してください。詳細: " + $_.Exception.Message)
    } finally {
        $masterConnection.Dispose()
    }

    Write-Host '[3/4] 接続情報を書き込みます...'
    $connectionString = New-ConnectionString -DataSource $dataSource -UserName $userName -Password $password -Database $DatabaseName
    Save-ConnectionConfig -Path (Join-Path $TargetDir 'connection.config') -ConnectionString $connectionString

    Write-Host '[4/4] 構成確認ページを確かめます...'
    Start-Sleep -Seconds 3
    $response = Invoke-WebRequest -Uri 'http://localhost/' -UseBasicParsing -TimeoutSec 60
    if ($response.Content -notmatch 'badge ok') {
        throw '構成確認ページが DB に接続できていません。http://localhost/ を開いて、エラーの内容を確認してください。'
    }

    Write-Host ''
    Write-Host 'DB の設定が終わりました。' -ForegroundColor Green
    Write-Host 'http://localhost/ を開いて、DB の状態が「接続できた」になっていることを確認してください。'
}

# 別のスクリプトから関数だけを読み込む場合（. .\setup-db.ps1）は、本体を実行しない。
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main
}
