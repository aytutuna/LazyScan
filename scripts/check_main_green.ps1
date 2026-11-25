# Stops unless HEAD is the tip of origin/main, the working tree is clean and ci.yml passed on the commit.
# The Store package and the Android bundle are built on this PC, so they check here what the upload
# workflows check in scripts/check_main_green.sh.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$head = (git -C $root rev-parse HEAD).Trim()
git -C $root fetch origin main --quiet
$tip = (git -C $root rev-parse origin/main).Trim()
if ($head -ne $tip) { throw "Not building: $head is not the tip of origin/main ($tip)." }
if (git -C $root status --porcelain) { throw 'Not building: the working tree has changes.' }
$passed = gh run list --repo aytutuna/LazyScan --workflow ci.yml --commit $head --status success --json databaseId --jq length
if ([int]$passed -lt 1) { throw "Not building: no passing ci.yml run on $head." }
