$ErrorActionPreference = 'Stop'

$root = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo'
$tools = 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\tools\smali3'
$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$sdk = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\android-sdk\build-tools\35.0.0'
$out = Join-Path $root 'stage29_camera_mtk_test'
$sourceApk = Join-Path $root 'stage29_camera_recover_test\MiuiCamera.recover-test.apk'
$smaliDir = Join-Path $root 'stage29_classes5_mtk'
$dex = Join-Path $out 'classes5.dex'
$unsigned = Join-Path $out 'MiuiCamera.mtk-unsigned.apk'
$aligned = Join-Path $out 'MiuiCamera.mtk-aligned.apk'
$signed = Join-Path $out 'MiuiCamera.mtk-test.apk'
$keystore = 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage29_camera_apk\system_compat_test\camera-test.jks'
$cp = ((Get-ChildItem -Path (Join-Path $tools '*.jar')).FullName -join ';')

New-Item -ItemType Directory -Force -Path $out | Out-Null
& $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 $smaliDir -o $dex
if ($LASTEXITCODE -ne 0) { throw "smali failed: $LASTEXITCODE" }

Copy-Item -LiteralPath $sourceApk -Destination $unsigned -Force
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($unsigned, [IO.Compression.ZipArchiveMode]::Update)
try {
    $old = $zip.GetEntry('classes5.dex')
    if (-not $old) { throw 'classes5.dex missing' }
    $old.Delete()
    $entry = $zip.CreateEntry('classes5.dex', [IO.Compression.CompressionLevel]::NoCompression)
    $dst = $entry.Open()
    $src = [IO.File]::OpenRead($dex)
    try { $src.CopyTo($dst) } finally { $src.Dispose(); $dst.Dispose() }
} finally { $zip.Dispose() }

Remove-Item -LiteralPath $aligned, $signed -Force -ErrorAction SilentlyContinue
& (Join-Path $sdk 'zipalign.exe') -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { throw "zipalign failed: $LASTEXITCODE" }

$env:JAVA_HOME = Split-Path (Split-Path $java -Parent) -Parent
& (Join-Path $sdk 'apksigner.bat') sign --ks $keystore --ks-key-alias k90camera --ks-pass pass:k90camera --key-pass pass:k90camera --out $signed $aligned
if ($LASTEXITCODE -ne 0) { throw "apksigner failed: $LASTEXITCODE" }
& (Join-Path $sdk 'apksigner.bat') verify --verbose --print-certs $signed
if ($LASTEXITCODE -ne 0) { throw "signature verification failed: $LASTEXITCODE" }
Get-FileHash -Algorithm SHA256 -LiteralPath $signed
