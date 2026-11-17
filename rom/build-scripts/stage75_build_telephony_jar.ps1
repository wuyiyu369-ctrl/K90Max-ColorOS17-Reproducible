$ErrorActionPreference = 'Stop'

$toolRoot = 'D:\K90Max_ColorOS17_完整迁移_20261028\06_WSL关键产物_虚拟磁盘不迁移\工具JAR'
$java = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\temurin17-jre\jdk-17.0.21+9-jre\bin\java.exe'
$work = 'D:\K90_AOD_STAGE75_WORK'
$baseSmali = Join-Path $work 'telephony_smali'
$verifySmali = Join-Path $work 'telephony_smali_verify'
$sourceJar = Join-Path $work 'telephony-common.jar'
$outputJar = Join-Path $work 'telephony-common.stage75.jar'
$outputDex = Join-Path $work 'telephony.classes.patched.dex'

$classpath = @(
    (Join-Path $toolRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $toolRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $toolRoot 'jars\antlr.jar'),
    (Join-Path $toolRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'

Remove-Item -LiteralPath $outputDex -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $outputJar -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $verifySmali -Recurse -Force -ErrorAction SilentlyContinue

& $java -cp $classpath com.android.tools.smali.smali.Main assemble --api 34 $baseSmali -o $outputDex
if ($LASTEXITCODE -ne 0) { throw "smali failed: $LASTEXITCODE" }

Copy-Item -LiteralPath $sourceJar -Destination $outputJar
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($outputJar, [IO.Compression.ZipArchiveMode]::Update)
try {
    $oldEntry = $archive.GetEntry('classes.dex')
    if (-not $oldEntry) { throw 'classes.dex is missing from telephony-common.jar' }
    $oldEntry.Delete()
    $newEntry = $archive.CreateEntry('classes.dex', [IO.Compression.CompressionLevel]::Optimal)
    $stream = $newEntry.Open()
    try {
        $bytes = [IO.File]::ReadAllBytes($outputDex)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }
} finally {
    $archive.Dispose()
}

& $java -cp $classpath com.android.tools.smali.baksmali.Main disassemble --api 34 $outputJar -o $verifySmali
if ($LASTEXITCODE -ne 0) { throw "verification baksmali failed: $LASTEXITCODE" }

$beforeFiles = Get-ChildItem -LiteralPath $baseSmali -Recurse -Filter '*.smali'
$afterFiles = Get-ChildItem -LiteralPath $verifySmali -Recurse -Filter '*.smali'
if ($beforeFiles.Count -ne $afterFiles.Count) {
    throw "class count changed: $($beforeFiles.Count) -> $($afterFiles.Count)"
}

$changed = foreach ($file in $beforeFiles) {
    $relative = $file.FullName.Substring($baseSmali.Length + 1)
    $verified = Join-Path $verifySmali $relative
    if (-not (Test-Path -LiteralPath $verified)) { throw "missing class: $relative" }
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne
        (Get-FileHash -LiteralPath $verified).Hash) {
        $relative
    }
}

$expected = @(
    'com\android\internal\telephony\ServiceStateTracker.smali',
    'com\android\internal\telephony\subscription\SubscriptionManagerService.smali'
)
if ((Compare-Object @($changed | Sort-Object) @($expected | Sort-Object))) {
    throw "unexpected changed classes: $($changed -join ', ')"
}

$verifiedText = [IO.File]::ReadAllText((Join-Path $verifySmali $expected[1]))
$needle = 'invoke-static {v2}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z'
if (-not $verifiedText.Contains($needle)) { throw 'empty display-name guard is missing' }
$carrierNeedle = 'invoke-virtual {v0, p1, p2}, Lcom/android/internal/telephony/subscription/SubscriptionDatabaseManager;->setDisplayName(ILjava/lang/String;)V'
if (-not $verifiedText.Contains($carrierNeedle)) { throw 'dynamic carrier display-name fallback is missing' }
$trackerText = [IO.File]::ReadAllText((Join-Path $verifySmali $expected[0]))
if ($trackerText -notmatch 'CarrierDisplayNameData;->equals\(Ljava/lang/Object;\)Z[\s\S]{0,80}move-result v2[\s\S]{0,80}goto :goto_30') {
    throw 'carrier display refresh early-return fix is missing'
}

Get-FileHash -Algorithm SHA256 $sourceJar, $outputJar, $outputDex
Write-Output "CLASS_COUNT_OK=$($beforeFiles.Count)"
Write-Output "CHANGED_CLASSES_OK=$($expected -join ',')"
