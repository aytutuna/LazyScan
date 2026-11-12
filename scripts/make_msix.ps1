<#
Publishes Lazy Scan self-contained for Windows, packs it as Store packages with the Windows SDK's tools and
writes LazyScan_<version>.msixupload to -Out. With both architectures the upload holds a bundle of the two
packages, with one just that package. Build it on this PC; the package is not a CI artifact.

  pwsh scripts/make_msix.ps1 -Out <folder> [-Arch x64,arm64] -IdentityName Aytu.LazyScan
       -Publisher 'CN=54BA56B9-1B6C-4B6E-886D-07694CF02BF5' -PublisherDisplayName Aytu

The identity values are the ones in Partner Center, Product identity. They default to the STORE_IDENTITY_NAME,
STORE_PUBLISHER and STORE_PUBLISHER_DISPLAY_NAME environment variables. The script stops without all three: a
package with placeholder names would only be refused by the Store.

The app and the helper are published with the shipping languages. The manifest's Resource list is written
from l10n/out/languages.win.txt, which the publish generates, and the script stops if a language folder is
missing from the package or the helper's folders differ from the app's.

The corner model (scripts/fetch_docaligner.sh) and THIRD-PARTY-NOTICES.txt must be in the checkout.

The app is published without a reference to the 32-bit TWAIN helper (SkipTwainHelper), which is published on
its own for win-x86 and goes into the package's Twain folder. Both packages also get the 64-bit helper
(win-x64, Twain64 folder), which runs every 64-bit TWAIN driver; on Windows on Arm it runs under emulation.
#>
param(
    [Parameter(Mandatory)] [string] $Out,
    [ValidateSet('x64', 'arm64')] [string[]] $Arch = @('x64', 'arm64'),
    [string] $IdentityName = $env:STORE_IDENTITY_NAME,
    [string] $Publisher = $env:STORE_PUBLISHER,
    [string] $PublisherDisplayName = $env:STORE_PUBLISHER_DISPLAY_NAME
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$store = Join-Path $root 'store\windows'
$props = [xml](Get-Content (Join-Path $root 'windows\Directory.Build.props'))
$version = $props.Project.PropertyGroup.Version
$packageVersion = "$version.0"
if (-not ($IdentityName -and $Publisher -and $PublisherDisplayName)) {
    throw 'Give -IdentityName, -Publisher and -PublisherDisplayName (or set STORE_IDENTITY_NAME, STORE_PUBLISHER and STORE_PUBLISHER_DISPLAY_NAME): they come from Partner Center, Product identity.'
}
$notices = Join-Path $root 'THIRD-PARTY-NOTICES.txt'
if (-not (Test-Path $notices)) { throw "$notices is missing" }
$model = Join-Path $root 'Sources\LazyScanModel\Models\fastvit_t8_h_e_bifpn_256_fp32.onnx'
if (-not (Test-Path $model)) { throw "$model is missing; run scripts/fetch_docaligner.sh" }

function Find-SdkTool([string] $name) {
    $kits = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\bin'
    $found = Get-ChildItem (Join-Path $kits "*\x64\$name") -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
    if (-not $found) { throw "$name is not in the Windows SDK under $kits" }
    $found.FullName
}

$makeappx = Find-SdkTool 'makeappx.exe'
$makepri = Find-SdkTool 'makepri.exe'
$nuget = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $HOME '.nuget\packages' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('lazyscan-msix-' + [guid]::NewGuid().ToString('N'))

function Invoke-Tool([string] $tool, [string[]] $arguments) {
    & $tool @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $tool -Leaf) failed with exit code $LASTEXITCODE" }
}

function Publish([string] $project, [string] $rid, [string] $to, [string[]] $extra = @()) {
    Invoke-Tool 'dotnet' (@('publish', (Join-Path $root $project), '-c', 'Release', '-r', $rid, '--self-contained', '-o', $to, '-p:L10nShip=true') + $extra)
}

# The folders that hold a satellite assembly, named by culture.
function Get-LanguageFolders([string] $folder) {
    @(Get-ChildItem $folder -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName '*.resources.dll') } |
        ForEach-Object Name | Sort-Object)
}

function New-Package([string] $arch, [string] $helper, [string] $helper64) {
    $publish = Join-Path $work "publish-$arch"
    Publish 'windows\LazyScan.App\LazyScan.App.csproj' "win-$arch" $publish @('-p:SkipTwainHelper=true')
    if (-not (Test-Path (Join-Path $publish 'LazyScan.exe'))) { throw "LazyScan.exe is not in $publish" }
    foreach ($file in 'Models\fastvit_t8_h_e_bifpn_256_fp32.onnx', 'Models\DocAligner-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', 'LICENSE.txt', 'ONNXRuntime-THIRD-PARTY-NOTICES.txt') {
        if (-not (Test-Path (Join-Path $publish $file))) { throw "$file is not in $publish" }
    }

    $list = Join-Path $root 'l10n\out\languages.win.txt'
    $languages = @(Get-Content $list | Where-Object { $_ })
    $folders = Get-LanguageFolders $publish
    $other = @($languages | Where-Object { $_ -ne 'en' } | Sort-Object)
    if (($folders -join ' ') -ne ($other -join ' ')) { throw "$publish holds the languages ($folders) but $list lists ($other)" }
    $helperFolders = Get-LanguageFolders $helper
    if (($helperFolders -join ' ') -ne ($folders -join ' ')) { throw "The TWAIN helper holds the languages ($helperFolders), the app ($folders)" }
    $helper64Folders = Get-LanguageFolders $helper64
    if (($helper64Folders -join ' ') -ne ($folders -join ' ')) { throw "The 64-bit TWAIN helper holds the languages ($helper64Folders), the app ($folders)" }

    $stage = Join-Path $work "stage-$arch"
    robocopy $publish $stage /E /XF *.pdb *.lib /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    robocopy $helper (Join-Path $stage 'Twain') /E /XF *.pdb *.lib /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    robocopy $helper64 (Join-Path $stage 'Twain64') /E /XF *.pdb *.lib /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    Copy-Item (Join-Path $store 'Assets') (Join-Path $stage 'Assets') -Recurse

    # The runtime's own third-party notices, from the runtime pack named in the publish's deps.json.
    $deps = Get-Content (Join-Path $publish 'LazyScan.deps.json') -Raw | ConvertFrom-Json
    $runtime = @($deps.libraries.PSObject.Properties.Name) | Where-Object { $_ -like "runtimepack.Microsoft.NETCore.App.Runtime.win-$arch/*" } | Select-Object -First 1
    if (-not $runtime) { throw "LazyScan.deps.json in $publish names no runtime pack for win-$arch" }
    $pack = Join-Path $nuget "microsoft.netcore.app.runtime.win-$arch\$($runtime.Split('/')[1])\THIRD-PARTY-NOTICES.TXT"
    if (-not (Test-Path $pack)) { throw "$pack is missing" }
    Copy-Item $pack (Join-Path $stage 'DOTNET-THIRD-PARTY-NOTICES.txt')

    $resources = ($languages | ForEach-Object { "    <Resource Language=`"$(if ($_ -eq 'en') { 'en-US' } else { $_ })`" />" }) -join "`n"
    $manifest = Get-Content (Join-Path $store 'Package.appxmanifest') -Raw
    $manifest = $manifest.Replace('Version="1.0.0.0"', "Version=`"$packageVersion`"").Replace('ProcessorArchitecture="x64"', "ProcessorArchitecture=`"$arch`"")
    $manifest = [regex]::Replace($manifest, '(?s)(<Resources>\r?\n).*?(\r?\n  </Resources>)', { param($m) $m.Groups[1].Value + $resources + $m.Groups[2].Value })
    $manifest = $manifest.Replace('PartnerCenterIdentityName', $IdentityName).Replace('CN=PartnerCenterPublisher', $Publisher).Replace('PartnerCenterPublisherDisplayName', $PublisherDisplayName)
    [IO.File]::WriteAllText((Join-Path $stage 'AppxManifest.xml'), $manifest, (New-Object Text.UTF8Encoding $false))

    # The scale and target size variants of the logos are found through resources.pri. It is built from the
    # assets alone, so the runtime's files and its language folders are not indexed as resources.
    $index = Join-Path $work "index-$arch"
    New-Item -ItemType Directory -Path $index | Out-Null
    Copy-Item (Join-Path $stage 'Assets') (Join-Path $index 'Assets') -Recurse
    Copy-Item (Join-Path $stage 'AppxManifest.xml') $index
    $config = Join-Path $work "priconfig-$arch.xml"
    Invoke-Tool $makepri @('createconfig', '/cf', $config, '/dq', 'en-US', '/o')
    # One package: the config would otherwise split the PRI by language and scale into resource packs.
    $xml = [xml](Get-Content $config)
    if ($xml.resources.packaging) { [void]$xml.resources.RemoveChild($xml.resources.packaging); $xml.Save($config) }
    Invoke-Tool $makepri @('new', '/pr', $index, '/cf', $config, '/mn', (Join-Path $index 'AppxManifest.xml'), '/of', (Join-Path $stage 'resources.pri'), '/o')

    $msix = Join-Path $work "LazyScan_${version}_$arch.msix"
    Invoke-Tool $makeappx @('pack', '/d', $stage, '/p', $msix, '/o')
    $msix
}

New-Item -ItemType Directory -Path $work, $Out -Force | Out-Null
try {
    # The helpers are the same for both packages.
    $helper = Join-Path $work 'twain-x86'
    Publish 'windows\LazyScan.TwainHelper\LazyScan.TwainHelper.csproj' 'win-x86' $helper
    $helper64 = Join-Path $work 'twain-x64'
    Publish 'windows\LazyScan.TwainHelper64\LazyScan.TwainHelper64.csproj' 'win-x64' $helper64

    $packages = @($Arch | ForEach-Object { New-Package $_ $helper $helper64 })

    $upload = Join-Path $work 'upload'
    New-Item -ItemType Directory -Path $upload | Out-Null
    if ($packages.Count -eq 1) {
        Copy-Item $packages[0] $upload
    } else {
        $parts = Join-Path $work 'parts'
        New-Item -ItemType Directory -Path $parts | Out-Null
        Copy-Item $packages $parts
        Invoke-Tool $makeappx @('bundle', '/d', $parts, '/bv', $packageVersion, '/p', (Join-Path $upload "LazyScan_$version.msixbundle"), '/o')
    }
    $zip = Join-Path $work "LazyScan_$version.zip"
    Compress-Archive -Path (Join-Path $upload '*') -DestinationPath $zip
    $target = Join-Path $Out "LazyScan_$version.msixupload"
    Move-Item $zip $target -Force
    Copy-Item $packages $Out -Force
    Write-Host "wrote $target"
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
