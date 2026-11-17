$ErrorActionPreference = 'Stop'

$toolRoot = 'D:\K90Max_ColorOS17_完整迁移_20261028\06_WSL关键产物_虚拟磁盘不迁移\工具JAR'
$java = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\temurin17-jre\jdk-17.0.21+9-jre\bin\java.exe'
$work = 'D:\K90_AOD_STAGE75_WORK'
$baseSmali = Join-Path $work 'telephony_smali_verify'
$patchedSmali = Join-Path $work 'telephony_smali_stage76'
$verifySmali = Join-Path $work 'telephony_smali_stage76_verify'
$sourceJar = Join-Path $work 'telephony-common.stage75.jar'
$outputJar = Join-Path $work 'telephony-common.stage76.jar'
$outputDex = Join-Path $work 'telephony.classes.stage76.dex'

$classpath = @(
    (Join-Path $toolRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $toolRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $toolRoot 'jars\antlr.jar'),
    (Join-Path $toolRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $toolRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'

Remove-Item -LiteralPath $patchedSmali -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $verifySmali -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $outputDex, $outputJar -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $baseSmali -Destination $patchedSmali -Recurse

$relative = 'com\android\internal\telephony\IOplusServiceStateTracker.smali'
$target = Join-Path $patchedSmali $relative
$text = [IO.File]::ReadAllText($target)
$new = @'
.method public blacklist isNotNeedToUpdateSpn()Z
    .registers 1

    # The no-extension fallback must preserve the standard Android SPN/PLMN
    # update path. Returning true suppresses all carrier-name publication.
    const/4 p0, 0x0

    return p0
.end method
'@
$pattern = '(?ms)^\.method public blacklist isNotNeedToUpdateSpn\(\)Z\r?\n' +
    '    \.registers 1\r?\n\r?\n' +
    '    const/4 p0, 0x1\r?\n\r?\n' +
    '    return p0\r?\n' +
    '\.end method\r?\n'
$matches = [regex]::Matches($text, $pattern)
if ($matches.Count -ne 1) {
    throw 'Expected exactly one default SPN gate method'
}
$patched = [regex]::Replace($text, $pattern, ($new.TrimStart("`r", "`n") + "`r`n"), 1)
[IO.File]::WriteAllText($target, $patched, [Text.UTF8Encoding]::new($false))

& $java -cp $classpath com.android.tools.smali.smali.Main assemble --api 34 $patchedSmali -o $outputDex
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
    $path = $file.FullName.Substring($baseSmali.Length + 1)
    $verified = Join-Path $verifySmali $path
    if (-not (Test-Path -LiteralPath $verified)) { throw "missing class: $path" }
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne
        (Get-FileHash -LiteralPath $verified).Hash) {
        $path
    }
}
$changedList = @($changed)
if ($changedList.Count -ne 1 -or $changedList[0] -ne $relative) {
    throw "unexpected changed classes: $($changed -join ', ')"
}

$verifiedText = [IO.File]::ReadAllText((Join-Path $verifySmali $relative))
if ($verifiedText -notmatch 'isNotNeedToUpdateSpn\(\)Z[\s\S]{0,100}const/4 p0, 0x0') {
    throw 'default SPN gate fix is missing from rebuilt jar'
}

Get-FileHash -Algorithm SHA256 $sourceJar, $outputJar, $outputDex
Write-Output "CLASS_COUNT_OK=$($beforeFiles.Count)"
Write-Output "CHANGED_CLASS_OK=$relative"
