<#
Writes the Microsoft Store screenshots: start.png, queue.png, photo-review.png and saved.png, each 1920x1080, into
-Out (store/windows/Listing by default). The app runs on the Demo Scanner in a temporary profile and save folder,
so no personal path or file shows in them. Run it on this PC; it builds the tests first.

  pwsh scripts/make_store_shots.ps1 [-Out <folder>] [-Artifacts <folder>]

-Artifacts is the build output folder, for when Smart App Control blocks the one in the tree.
#>
param(
    [string] $Out,
    [string] $Artifacts
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if (-not $Out) { $Out = Join-Path $root 'store\windows\Listing' }
$Out = [IO.Path]::GetFullPath($Out)
$names = 'start', 'queue', 'photo-review', 'saved'
foreach ($name in $names) { Remove-Item (Join-Path $Out "$name.png") -ErrorAction Ignore }

$env:LAZYSCAN_STORE_SHOTS_DIR = $Out
try {
    $arguments = @('test', (Join-Path $root 'windows\LazyScan.App.Tests'), '-c', 'Debug', '--filter', 'FullyQualifiedName~StoreShotsTests')
    if ($Artifacts) { $arguments += @('--artifacts-path', $Artifacts) }
    & dotnet @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "dotnet test failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item Env:\LAZYSCAN_STORE_SHOTS_DIR
}

Add-Type -AssemblyName System.Drawing
foreach ($name in $names) {
    $path = Join-Path $Out "$name.png"
    if (-not (Test-Path $path)) { throw "$path was not written" }
    $image = [System.Drawing.Image]::FromFile($path)
    try {
        if ($image.Width -ne 1920 -or $image.Height -ne 1080) { throw "$path is $($image.Width)x$($image.Height), not 1920x1080" }
    }
    finally {
        $image.Dispose()
    }
}
Write-Host "Wrote $($names.Count) screenshots to $Out"
