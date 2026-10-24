param(
    [string]$Dotnet = 'dotnet',
    [string]$Iscc = 'ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$project = Join-Path $repo 'windows\AndroLaunch.WinUI\AndroLaunch.WinUI.csproj'
$version = ([xml](Get-Content $project -Raw)).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
if (-not $version) { throw 'The Windows project must declare a release version.' }
$release = Join-Path $repo "build\windows\v$version"
$publish = Join-Path $release 'AndroLaunch'
if (Test-Path $publish) { throw "Release output already exists: $publish. Choose a new release version or archive the previous generated output first." }
New-Item $publish -ItemType Directory -Force | Out-Null
& $Dotnet publish $project -c Release -r win-x64 --self-contained true -o $publish -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw 'WinUI publish failed.' }
$zip = Join-Path $release "v$version-windows.zip"
Compress-Archive -Path $publish -DestinationPath $zip -Force
& $Iscc /Qp "/DPublishDir=$publish" "/DReleaseDir=$release" "/DAppVersion=$version" (Join-Path $repo 'windows\AndroLaunch.WinUI\installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed.' }
Get-FileHash $zip, (Join-Path $release "AndroLaunch-$version-windows-x64-setup.exe") -Algorithm SHA256
