<#
Builds the signed Android bundle for Google Play from the tip of main and copies it to -Out as
LazyScan_<version>.aab. Build it on this PC; the bundle is not a CI artifact. Signing reads the upload key
from ~/.gradle/gradle.properties (lazyscanKeystore, lazyscanStorePassword, lazyscanKeyAlias,
lazyscanKeyPassword); without them Gradle builds an unsigned bundle and this script stops.
#>
param(
    [Parameter(Mandatory)] [string] $Out
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
& (Join-Path $PSScriptRoot 'check_main_green.ps1')
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$props = Join-Path $HOME '.gradle\gradle.properties'
if (-not (Test-Path $props) -or -not (Select-String -Path $props -Pattern '^lazyscanKeystore=' -Quiet)) {
    throw "$props has no lazyscanKeystore: the bundle would be unsigned."
}

Push-Location (Join-Path $root 'android')
try {
    & .\gradlew.bat bundleRelease --console=plain
    if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item (Join-Path $root 'android\app\build\outputs\bundle\release\app-release.aab') (Join-Path $Out "LazyScan_$version.aab") -Force
