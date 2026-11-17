$ErrorActionPreference = 'Stop'

# Resolve everything relative to this project. The whole directory can be moved
# without editing machine-specific absolute paths.
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'src'
$releaseDir = Join-Path $projectRoot 'releases'
$moduleProp = Join-Path $sourceDir 'module.prop'

if (-not (Test-Path -LiteralPath $moduleProp)) {
    throw "Missing module metadata: $moduleProp"
}

$versionLine = Get-Content -LiteralPath $moduleProp |
    Where-Object { $_ -like 'version=*' } |
    Select-Object -First 1
if (-not $versionLine) {
    throw 'module.prop does not contain version='
}

$version = ($versionLine -replace '^version=', '') -replace '[^0-9A-Za-z._-]', '_'
$outputName = "K90Max_Game_System_Fix_$version.zip"
$outputPath = Join-Path $releaseDir $outputName
# tar.exe -a selects the archive format from the final extension, so the
# temporary file must still end in .zip.
$temporaryPath = Join-Path $releaseDir "K90Max_Game_System_Fix_$version.building.zip"

New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
if (Test-Path -LiteralPath $temporaryPath) {
    Remove-Item -LiteralPath $temporaryPath -Force
}

Push-Location $sourceDir
try {
    & "$env:SystemRoot\System32\tar.exe" -a -c -f $temporaryPath *
    if ($LASTEXITCODE -ne 0) {
        throw "tar create failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$entries = & "$env:SystemRoot\System32\tar.exe" -tf $temporaryPath
if ($LASTEXITCODE -ne 0) {
    throw "tar list failed with exit code $LASTEXITCODE"
}

$required = @(
    'module.prop',
    'post-fs-data.sh',
    'service.sh',
    'bin/perf_bridge',
    'bin/pq_bridge.jar',
    'config/game_profiles',
    'config/thermal_safe',
    'config/oplus_vrr_config.json',
    'META-INF/com/google/android/update-binary',
    'META-INF/com/google/android/updater-script'
)
$missing = $required | Where-Object { $entries -notcontains $_ }
$invalidEntries = $entries | Where-Object {
    $_ -match '\\' -or $_ -match '(^|/)\.\.(/|$)' -or $_ -match '^[A-Za-z]:'
}

if ($missing.Count -gt 0) {
    Remove-Item -LiteralPath $temporaryPath -Force
    throw "Missing ZIP entries: $($missing -join ', ')"
}
if ($invalidEntries.Count -gt 0) {
    Remove-Item -LiteralPath $temporaryPath -Force
    throw "Invalid ZIP entries: $($invalidEntries -join ', ')"
}

$customize = Get-Content -LiteralPath (Join-Path $sourceDir 'customize.sh') -Raw
if ($customize -notmatch '(?m)^SKIPMOUNT=true\s*$') {
    Remove-Item -LiteralPath $temporaryPath -Force
    throw 'Safety contract requires SKIPMOUNT=true'
}
if ($customize -notmatch '(?m)^touch "\$MODPATH/skip_mount" \|\| abort ') {
    Remove-Item -LiteralPath $temporaryPath -Force
    throw 'Safety contract requires an explicit skip_mount marker'
}
$partitionPayloads = @('system/', 'system_ext/', 'vendor/', 'product/', 'odm/')
$mountedEntries = $entries | Where-Object {
    $entry = $_
    $partitionPayloads | Where-Object { $entry.StartsWith($_) -and $entry -ne $_ }
}
if ($mountedEntries.Count -gt 0) {
    Remove-Item -LiteralPath $temporaryPath -Force
    throw "Partition overlay payload is forbidden: $($mountedEntries -join ', ')"
}

if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
}
Move-Item -LiteralPath $temporaryPath -Destination $outputPath

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath
[pscustomobject]@{
    Path = $outputPath
    Length = (Get-Item -LiteralPath $outputPath).Length
    SHA256 = $hash.Hash
    EntryCount = $entries.Count
}
