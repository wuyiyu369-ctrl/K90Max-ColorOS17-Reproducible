$ErrorActionPreference = 'Stop'

$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$archiveRoot = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
if (-not $archiveRoot) { throw 'K90 archive root not found' }
$jarRoot = (Get-ChildItem $archiveRoot -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'jars3') } | Select-Object -First 1).FullName
if (-not $jarRoot) { throw 'Smali tool directory not found' }
$cp = @(
    (Join-Path $jarRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $jarRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $jarRoot 'jars\antlr.jar'),
    (Join-Path $jarRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'

$root = 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage25_perf'
$frameworkIn = Join-Path $root 'framework.device.r3.jar'
$oplusIn = Join-Path $root 'oplus-framework.device.r3.jar'
$frameworkOut = Join-Path $root 'framework.stage25.jar'
$oplusOut = Join-Path $root 'oplus-framework.stage25.jar'
foreach ($p in @($java, $frameworkIn, $oplusIn)) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing input: $p" } }

$work = Join-Path $root 'jar_work'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-ZipEntryBytes([string]$ZipPath, [string]$EntryName) {
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.GetEntry($EntryName)
        if (-not $entry) { throw "$EntryName missing from $ZipPath" }
        $stream = $entry.Open()
        try {
            $memory = New-Object IO.MemoryStream
            $stream.CopyTo($memory)
            return $memory.ToArray()
        } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
}

function Set-ZipEntry([string]$InputZip, [string]$OutputZip, [string]$EntryName, [string]$ReplacementPath) {
    [IO.File]::Copy($InputZip, $OutputZip, $true)
    $zip = [IO.Compression.ZipFile]::Open($OutputZip, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $old = $zip.GetEntry($EntryName)
        if (-not $old) { throw "$EntryName missing from $InputZip" }
        $old.Delete()
        $entry = $zip.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::NoCompression)
        $entry.LastWriteTime = [DateTimeOffset]::new(2009, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $dst = $entry.Open()
        $src = [IO.File]::OpenRead($ReplacementPath)
        try { $src.CopyTo($dst) } finally { $src.Dispose(); $dst.Dispose() }
    } finally { $zip.Dispose() }
}

function Replace-MethodExactlyOnce([string]$Path, [string]$Signature, [string]$Replacement) {
    $text = [IO.File]::ReadAllText($Path)
    $pattern = '(?ms)^\.method ' + [regex]::Escape($Signature) + '\r?\n.*?^\.end method\r?\n'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) { throw "Expected one method $Signature in $Path, got $($matches.Count)" }
    $updated = [regex]::Replace($text, $pattern, ($Replacement.Trim() + "`r`n"), 1)
    [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
}

function Disassemble([string]$Dex, [string]$OutDir) {
    & $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 $Dex -o $OutDir
    if ($LASTEXITCODE -ne 0) { throw "baksmali failed for ${Dex}: $LASTEXITCODE" }
}

function Assemble([string]$SmaliDir, [string]$Dex) {
    & $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 $SmaliDir -o $Dex
    if ($LASTEXITCODE -ne 0) { throw "smali failed for ${SmaliDir}: $LASTEXITCODE" }
}

$frameworkDex = Join-Path $work 'framework-classes3.dex'
$oplusDex = Join-Path $work 'oplus-classes2.dex'
[IO.File]::WriteAllBytes($frameworkDex, (Get-ZipEntryBytes $frameworkIn 'classes3.dex'))
[IO.File]::WriteAllBytes($oplusDex, (Get-ZipEntryBytes $oplusIn 'classes2.dex'))

$frameworkBase = Join-Path $work 'framework-base'
$frameworkSmali = Join-Path $work 'framework-smali'
$oplusBase = Join-Path $work 'oplus-base'
$oplusSmali = Join-Path $work 'oplus-smali'
Disassemble $frameworkDex $frameworkBase
Disassemble $oplusDex $oplusBase
Copy-Item -LiteralPath $frameworkBase -Destination $frameworkSmali -Recurse
Copy-Item -LiteralPath $oplusBase -Destination $oplusSmali -Recurse

$perf = Join-Path $frameworkSmali 'android\os\PerformanceManager.smali'
$uah = Join-Path $oplusSmali 'com\oplus\uah\UAHAdaptHelper.smali'

$perfText = [IO.File]::ReadAllText($perf)
$calls = [regex]::Matches($perfText, 'invoke-static \{\}, Landroid/os/PerformanceManager;->getPerformanceService\(\)Lvendor/oplus/hardware/performance/IPerformance;')
if ($calls.Count -lt 100) { throw "Unexpected PerformanceManager call count: $($calls.Count)" }
$unsafe = 0
foreach ($m in $calls) {
    $tail = $perfText.Substring($m.Index, [Math]::Min(700, $perfText.Length - $m.Index))
    if ($tail -notmatch 'if-eqz') { $unsafe++ }
}
if ($unsafe -ne 0) { throw "Unsafe getPerformanceService callers: $unsafe" }

Replace-MethodExactlyOnce $perf 'private static blacklist getPerformanceService()Lvendor/oplus/hardware/performance/IPerformance;' @'
.method private static blacklist getPerformanceService()Lvendor/oplus/hardware/performance/IPerformance;
    .locals 1

    # K90/Prague has MTK PowerHAL, FPSGO and Xiaomi UniPerf, but no Oplus
    # IPerformance service. Every caller already handles null. Avoid repeated
    # ServiceManager lookups, null asBinder calls and exception stack traces.
    const/4 v0, 0x0

    return-object v0
.end method
'@

Replace-MethodExactlyOnce $uah 'public blacklist getAidlService()Z' @'
.method public blacklist getAidlService()Z
    .locals 1

    # The Oplus URCC HAL is not present on the Xiaomi/MTK vendor stack.
    # Existing callers already use false as the unsupported path; returning it
    # directly prevents repeated stable-AIDL isDeclared checks and SELinux logs.
    const/4 v0, 0x0

    return v0
.end method
'@

$frameworkPatchedDex = Join-Path $work 'framework-classes3.stage25.dex'
$oplusPatchedDex = Join-Path $work 'oplus-classes2.stage25.dex'
Assemble $frameworkSmali $frameworkPatchedDex
Assemble $oplusSmali $oplusPatchedDex
Set-ZipEntry $frameworkIn $frameworkOut 'classes3.dex' $frameworkPatchedDex
Set-ZipEntry $oplusIn $oplusOut 'classes2.dex' $oplusPatchedDex

$frameworkVerifyDex = Join-Path $work 'framework-verify.dex'
$oplusVerifyDex = Join-Path $work 'oplus-verify.dex'
[IO.File]::WriteAllBytes($frameworkVerifyDex, (Get-ZipEntryBytes $frameworkOut 'classes3.dex'))
[IO.File]::WriteAllBytes($oplusVerifyDex, (Get-ZipEntryBytes $oplusOut 'classes2.dex'))
$frameworkVerify = Join-Path $work 'framework-verify'
$oplusVerify = Join-Path $work 'oplus-verify'
Disassemble $frameworkVerifyDex $frameworkVerify
Disassemble $oplusVerifyDex $oplusVerify

function Get-ChangedClasses([string]$Before, [string]$After) {
    $changed = @()
    $beforeFiles = Get-ChildItem -LiteralPath $Before -Recurse -Filter '*.smali'
    $afterFiles = Get-ChildItem -LiteralPath $After -Recurse -Filter '*.smali'
    if ($beforeFiles.Count -ne $afterFiles.Count) { throw "Class count changed: $($beforeFiles.Count) -> $($afterFiles.Count)" }
    foreach ($file in $beforeFiles) {
        $relative = $file.FullName.Substring($Before.Length + 1)
        $other = Join-Path $After $relative
        if (-not (Test-Path -LiteralPath $other)) { throw "Missing output class: $relative" }
        if ((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $other).Hash) { $changed += $relative }
    }
    return $changed
}

$frameworkChanged = Get-ChangedClasses $frameworkBase $frameworkVerify
$oplusChanged = Get-ChangedClasses $oplusBase $oplusVerify
if (($frameworkChanged -join ',') -ne 'android\os\PerformanceManager.smali') { throw "Unexpected framework changes: $($frameworkChanged -join ', ')" }
$expectedOplus = @(
    'com\oplus\uah\UAHAdaptHelper.smali',
    'com\oplus\util\OplusLog.smali',
    'com\oplus\widget\OplusViewPager.smali'
)
if (Compare-Object ($oplusChanged | Sort-Object) ($expectedOplus | Sort-Object)) { throw "Unexpected oplus-framework changes: $($oplusChanged -join ', ')" }

# smali 3.0.10 canonicalizes encoded static boolean false to an omitted value.
# Both forms initialize to false at runtime. Refuse any broader difference in
# the two known classes so this normalization cannot hide a real code change.
$oplusLogBase = [IO.File]::ReadAllText((Join-Path $oplusBase 'com\oplus\util\OplusLog.smali'))
$oplusLogVerify = [IO.File]::ReadAllText((Join-Path $oplusVerify 'com\oplus\util\OplusLog.smali'))
if ($oplusLogBase.Replace('STACK_TRACE:Z = false', 'STACK_TRACE:Z') -ne $oplusLogVerify) { throw 'Unexpected OplusLog normalization' }
$pagerBase = [IO.File]::ReadAllText((Join-Path $oplusBase 'com\oplus\widget\OplusViewPager.smali'))
$pagerVerify = [IO.File]::ReadAllText((Join-Path $oplusVerify 'com\oplus\widget\OplusViewPager.smali'))
if ($pagerBase.Replace('USE_CACHE:Z = false', 'USE_CACHE:Z') -ne $pagerVerify) { throw 'Unexpected OplusViewPager normalization' }

$perfVerify = [IO.File]::ReadAllText((Join-Path $frameworkVerify 'android\os\PerformanceManager.smali'))
$uahVerify = [IO.File]::ReadAllText((Join-Path $oplusVerify 'com\oplus\uah\UAHAdaptHelper.smali'))
if ($perfVerify -match 'Failed to get performance hal service') { throw 'Old IPerformance lookup remains in rebuilt method' }
if ($uahVerify -match 'getAidlService uah urcc service') { throw 'Old URCC lookup remains in rebuilt method' }

$hashes = Get-FileHash $frameworkIn, $frameworkOut, $oplusIn, $oplusOut -Algorithm SHA256
$hashes | ForEach-Object { "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_.Path))" } | Set-Content -LiteralPath (Join-Path $root 'SHA256SUMS.jars.txt') -Encoding utf8
[IO.File]::WriteAllLines((Join-Path $root 'CHANGED_CLASSES.txt'), @($frameworkChanged + $oplusChanged), [Text.UTF8Encoding]::new($false))
$hashes | Format-Table Path, Hash
Write-Output "FRAMEWORK_CLASS_COUNT_OK=$((Get-ChildItem $frameworkBase -Recurse -Filter '*.smali').Count)"
Write-Output "OPLUS_CLASS_COUNT_OK=$((Get-ChildItem $oplusBase -Recurse -Filter '*.smali').Count)"
Write-Output 'STAGE25_PERF_JARS_OK'
