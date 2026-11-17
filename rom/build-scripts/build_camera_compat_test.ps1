$ErrorActionPreference = 'Stop'

$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$keytool = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\keytool.exe'
$sdk = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\android-sdk\build-tools\35.0.0'
$zipalign = Join-Path $sdk 'zipalign.exe'
$apksigner = Join-Path $sdk 'apksigner.bat'
$root = 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo'
$decoded = Join-Path $root 'xiaomi_camera_a17\decoded'
$official = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\xiaomi_a17_extract\trees\product_a\priv-app\MiuiCamera\MiuiCamera.apk'
$out = Join-Path $root 'stage29_camera_apk\system_compat_test'

$archiveRoot = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
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

New-Item -ItemType Directory -Path $out -Force | Out-Null
$dex = Join-Path $out 'classes4.dex'
$unsigned = Join-Path $out 'MiuiCamera.compat-unsigned.apk'
$aligned = Join-Path $out 'MiuiCamera.compat-aligned.apk'
$signed = Join-Path $out 'MiuiCamera.compat-test.apk'
$keystore = Join-Path $out 'camera-test.jks'

& $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 (Join-Path $decoded 'smali_classes4') -o $dex
if ($LASTEXITCODE -ne 0) { throw "smali failed: $LASTEXITCODE" }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.File]::Copy($official, $unsigned, $true)
$zip = [IO.Compression.ZipFile]::Open($unsigned, [IO.Compression.ZipArchiveMode]::Update)
try {
    $old = $zip.GetEntry('classes4.dex')
    if (-not $old) { throw 'classes4.dex missing from official APK' }
    $old.Delete()
    $entry = $zip.CreateEntry('classes4.dex', [IO.Compression.CompressionLevel]::NoCompression)
    $dst = $entry.Open()
    $src = [IO.File]::OpenRead($dex)
    try { $src.CopyTo($dst) } finally { $src.Dispose(); $dst.Dispose() }
} finally { $zip.Dispose() }

foreach ($path in @($aligned, $signed)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
& $zipalign -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { throw "zipalign failed: $LASTEXITCODE" }

if (-not (Test-Path -LiteralPath $keystore)) {
    & $keytool -genkeypair -keystore $keystore -storepass k90camera -keypass k90camera -alias k90camera -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=K90 Camera Test,O=K90Max,C=CN'
    if ($LASTEXITCODE -ne 0) { throw "keytool failed: $LASTEXITCODE" }
}
& $apksigner sign --ks $keystore --ks-key-alias k90camera --ks-pass pass:k90camera --key-pass pass:k90camera --out $signed $aligned
if ($LASTEXITCODE -ne 0) { throw "apksigner failed: $LASTEXITCODE" }
& $apksigner verify --verbose --print-certs $signed
if ($LASTEXITCODE -ne 0) { throw "signature verification failed: $LASTEXITCODE" }
Get-FileHash -Algorithm SHA256 -LiteralPath $signed
