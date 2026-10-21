param(
    [string]$Dotnet = 'dotnet',
    [string]$Iscc = 'ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$project = Join-Path $repo 'windows\AndroLaunch.WinUI\AndroLaunch.WinUI.csproj'
$release = Join-Path $repo 'build\windows'
$publish = Join-Path $release 'AndroLaunch'
if (Test-Path $publish) { Remove-Item $publish -Recurse -Force }
New-Item $publish -ItemType Directory -Force | Out-Null
& $Dotnet publish $project -c Release -r win-x64 --self-contained true -o $publish -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw 'WinUI publish failed.' }
$zip = Join-Path $release 'v0.3.9-windows.zip'
Compress-Archive -Path $publish -DestinationPath $zip -Force
& $Iscc /Qp "/DPublishDir=$publish" "/DReleaseDir=$release" (Join-Path $repo 'windows\AndroLaunch.WinUI\installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed.' }
Get-FileHash $zip, (Join-Path $release 'AndroLaunch-0.3.9-windows-x64-setup.exe') -Algorithm SHA256
