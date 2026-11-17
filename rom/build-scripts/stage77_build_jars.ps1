$ErrorActionPreference = 'Stop'

$toolRoot = 'D:\K90Max_ColorOS17_完整迁移_20261028\06_WSL关键产物_虚拟磁盘不迁移\工具JAR'
$java = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\temurin17-jre\jdk-17.0.21+9-jre\bin\java.exe'
$work = 'D:\K90_AOD_STAGE75_WORK'
$artifactRoot = Join-Path $work 'stage77_artifacts'
$outputRoot = Join-Path $work 'stage77_jars'

$classpath = @(
    (Join-Path $toolRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $toolRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $toolRoot 'jars\antlr.jar'),
    (Join-Path $toolRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'

function Invoke-SmaliAssemble {
    param([string]$Source, [string]$Output)
    & $java -cp $classpath com.android.tools.smali.smali.Main assemble --api 34 $Source -o $Output
    if ($LASTEXITCODE -ne 0) { throw "smali failed for ${Source}: $LASTEXITCODE" }
}

function Invoke-Baksmali {
    param([string]$Dex, [string]$Output)
    Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
    & $java -cp $classpath com.android.tools.smali.baksmali.Main disassemble --api 34 $Dex -o $Output
    if ($LASTEXITCODE -ne 0) { throw "baksmali failed for ${Dex}: $LASTEXITCODE" }
}

function Replace-ZipEntry {
    param([string]$ArchivePath, [string]$EntryName, [string]$SourcePath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($ArchivePath, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $oldEntry = $archive.GetEntry($EntryName)
        if (-not $oldEntry) { throw "$EntryName is missing from $ArchivePath" }
        $oldEntry.Delete()
        $newEntry = $archive.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
        $stream = $newEntry.Open()
        try {
            $bytes = [IO.File]::ReadAllBytes($SourcePath)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $archive.Dispose()
    }
}

function Get-ZipEntryHashes {
    param([string]$ArchivePath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $result = @{}
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            $stream = $entry.Open()
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try {
                    $result[$entry.FullName] = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
                } finally {
                    $sha.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
    return $result
}

function Assert-OnlyTargetClassChanged {
    param([string]$Before, [string]$After, [string]$Target)
    $beforeFiles = @(Get-ChildItem -LiteralPath $Before -Recurse -Filter '*.smali')
    $afterFiles = @(Get-ChildItem -LiteralPath $After -Recurse -Filter '*.smali')
    if ($beforeFiles.Count -ne $afterFiles.Count) {
        throw "class count changed: $($beforeFiles.Count) -> $($afterFiles.Count)"
    }
    $changed = @()
    foreach ($file in $beforeFiles) {
        $relative = $file.FullName.Substring($Before.Length + 1)
        $verified = Join-Path $After $relative
        if (-not (Test-Path -LiteralPath $verified)) { throw "missing class: $relative" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash -ne
            (Get-FileHash -Algorithm SHA256 -LiteralPath $verified).Hash) {
            $changed += $relative
        }
    }
    if ($changed.Count -ne 1 -or $changed[0] -ne $Target) {
        throw "unexpected changed classes: $($changed -join ', ')"
    }
    return $beforeFiles.Count
}

function Convert-ToFileNewlines {
    param([string]$Value, [string]$Reference)
    $newline = if ($Reference.Contains("`r`n")) { "`r`n" } else { "`n" }
    return (($Value -replace "`r`n", "`n") -replace "`n", $newline)
}

Remove-Item -LiteralPath $outputRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $outputRoot | Out-Null

# Carrier-name fallback: preserve the standard SPN/PLMN calculation and only
# use ServiceState operator alpha when the calculated result is empty.
$telephonySourceJar = Join-Path $work 'telephony-common.stage76.jar'
$telephonyBaseSmali = Join-Path $work 'telephony_smali_stage76_verify'
$telephonyPatchedSmali = Join-Path $outputRoot 'telephony_smali'
$telephonyVerifySmali = Join-Path $outputRoot 'telephony_verify'
$telephonyDex = Join-Path $outputRoot 'telephony.classes.dex'
$telephonyOutputJar = Join-Path $outputRoot 'telephony-common.stage77.jar'
$telephonyClass = 'com\android\internal\telephony\ServiceStateTracker.smali'

Copy-Item -LiteralPath $telephonyBaseSmali -Destination $telephonyPatchedSmali -Recurse
$telephonyTarget = Join-Path $telephonyPatchedSmali $telephonyClass
$text = [IO.File]::ReadAllText($telephonyTarget)
$start = $text.IndexOf('.method private blacklist getCarrierName(Lcom/android/internal/telephony/cdnr/CarrierDisplayNameData;)Ljava/lang/String;')
if ($start -lt 0) { throw 'getCarrierName method not found' }
$end = $text.IndexOf('.end method', $start)
if ($end -lt 0) { throw 'getCarrierName method end not found' }
$end += '.end method'.Length
$method = $text.Substring($start, $end - $start)
if ($method -notmatch '(?m)^    \.registers 5\r?$') { throw 'unexpected getCarrierName register count' }
$method = $method -replace '(?m)^    \.registers 5\r?$', '    .registers 6'
$anchor = '    .line 2462'
$prefix = @'
    # Stage77: cache the modem-derived alpha before p0 is reused below.
    iget-object v3, p0, Lcom/android/internal/telephony/ServiceStateTracker;->mSS:Landroid/telephony/ServiceState;

    invoke-virtual {v3}, Landroid/telephony/ServiceState;->getOperatorAlphaLong()Ljava/lang/String;

    move-result-object v3

'@
$prefix = Convert-ToFileNewlines $prefix $method
if (($method.Split($anchor).Count - 1) -ne 1) { throw 'unexpected carrier method entry anchor' }
$method = $method.Replace($anchor, $prefix + $anchor)
$tail = @'
    :goto_4d
    invoke-static {v2}, Landroid/text/TextUtils;->emptyIfNull(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p0

    return-object p0
'@
$replacement = @'
    :goto_4d
    invoke-static {v2}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z

    move-result p1

    if-eqz p1, :stage77_carrier_ready

    invoke-static {v3}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z

    move-result p1

    if-nez p1, :stage77_carrier_ready

    move-object v2, v3

    :stage77_carrier_ready
    invoke-static {v2}, Landroid/text/TextUtils;->emptyIfNull(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p0

    return-object p0
'@
$tail = Convert-ToFileNewlines $tail $method
$replacement = Convert-ToFileNewlines $replacement $method
if (($method.Split($tail).Count - 1) -ne 1) { throw 'unexpected carrier method tail' }
$method = $method.Replace($tail, $replacement)
$text = $text.Substring(0, $start) + $method + $text.Substring($end)
[IO.File]::WriteAllText($telephonyTarget, $text, [Text.UTF8Encoding]::new($false))

Invoke-SmaliAssemble $telephonyPatchedSmali $telephonyDex
Copy-Item -LiteralPath $telephonySourceJar -Destination $telephonyOutputJar
Replace-ZipEntry $telephonyOutputJar 'classes.dex' $telephonyDex
Invoke-Baksmali $telephonyDex $telephonyVerifySmali
$telephonyCount = Assert-OnlyTargetClassChanged $telephonyBaseSmali $telephonyVerifySmali $telephonyClass

# Color mode translation belongs to oplus-services.jar. The ColorOS logical
# setting remains unchanged; only the mode sent to SurfaceFlinger is mapped to
# this MTK panel's advertised Native/sRGB/Display-P3 values (0/7/9).
$oplusSourceJar = Join-Path $artifactRoot 'oplus-services.stage76.jar'
$oplusBaseSmali = Join-Path $work 'oplus_smali_base'
$oplusPatchedSmali = Join-Path $outputRoot 'oplus_smali'
$oplusVerifySmali = Join-Path $outputRoot 'oplus_verify'
$oplusDex = Join-Path $outputRoot 'oplus-services.classes.dex'
$oplusOutputJar = Join-Path $outputRoot 'oplus-services.stage77.jar'
$oplusClass = 'com\android\server\display\color\feature\OplusFeatureColorMode.smali'

Copy-Item -LiteralPath $oplusBaseSmali -Destination $oplusPatchedSmali -Recurse
$oplusTarget = Join-Path $oplusPatchedSmali $oplusClass
$text = [IO.File]::ReadAllText($oplusTarget)
$needle = @'
    .local v2, "intent":I
    :goto_48
    iget-object v3, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mCdsExt:Lcom/android/server/display/color/IColorDisplayServiceExt;

    invoke-interface {v3, v2}, Lcom/android/server/display/color/IColorDisplayServiceExt;->setColorModeExt(I)V
'@
$mapped = @'
    .local v2, "intent":I
    :goto_48
    # Stage77: translate ColorOS logical modes to modes advertised by MTK SF.
    const/4 v3, 0x1
    if-eq p1, v3, :stage77_color_srgb
    const/16 v3, 0xa
    if-eq p1, v3, :stage77_color_srgb
    const/16 v3, 0x14
    if-eq p1, v3, :stage77_color_srgb
    const/4 v3, 0x3
    if-eq p1, v3, :stage77_color_p3
    const/16 v3, 0xb
    if-eq p1, v3, :stage77_color_p3
    const/16 v3, 0x15
    if-eq p1, v3, :stage77_color_p3
    const/4 v2, 0x0
    goto :stage77_color_apply

    :stage77_color_srgb
    const/4 v2, 0x7
    goto :stage77_color_apply

    :stage77_color_p3
    const/16 v2, 0x9

    :stage77_color_apply
    iget-object v3, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mCdsExt:Lcom/android/server/display/color/IColorDisplayServiceExt;

    invoke-interface {v3, v2}, Lcom/android/server/display/color/IColorDisplayServiceExt;->setColorModeExt(I)V
'@
$needle = Convert-ToFileNewlines $needle $text
$mapped = Convert-ToFileNewlines $mapped $text
if (($text.Split($needle).Count - 1) -ne 1) { throw 'unexpected updateColorMode1 apply site' }
$text = $text.Replace($needle, $mapped)
[IO.File]::WriteAllText($oplusTarget, $text, [Text.UTF8Encoding]::new($false))

Invoke-SmaliAssemble $oplusPatchedSmali $oplusDex
Copy-Item -LiteralPath $oplusSourceJar -Destination $oplusOutputJar
Replace-ZipEntry $oplusOutputJar 'classes.dex' $oplusDex
Invoke-Baksmali $oplusDex $oplusVerifySmali
$oplusCount = Assert-OnlyTargetClassChanged $oplusBaseSmali $oplusVerifySmali $oplusClass

# Every non-target archive member must remain byte-identical.
$before = Get-ZipEntryHashes $oplusSourceJar
$after = Get-ZipEntryHashes $oplusOutputJar
foreach ($name in $before.Keys) {
    if ($name -eq 'classes.dex') { continue }
    if (-not $after.ContainsKey($name) -or $before[$name] -ne $after[$name]) {
        throw "oplus-services non-target member changed: $name"
    }
}
$before = Get-ZipEntryHashes $telephonySourceJar
$after = Get-ZipEntryHashes $telephonyOutputJar
foreach ($name in $before.Keys) {
    if ($name -eq 'classes.dex') { continue }
    if (-not $after.ContainsKey($name) -or $before[$name] -ne $after[$name]) {
        throw "telephony-common non-target member changed: $name"
    }
}

Get-FileHash -Algorithm SHA256 $telephonyOutputJar, $oplusOutputJar, $telephonyDex, $oplusDex
Write-Output "TELEPHONY_CLASS_COUNT_OK=$telephonyCount"
Write-Output "OPLUS_SERVICES_CLASS_COUNT_OK=$oplusCount"
Write-Output 'STAGE77_JARS_BUILD_PASSED'
