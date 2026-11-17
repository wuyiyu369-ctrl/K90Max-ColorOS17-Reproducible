$ErrorActionPreference = 'Stop'
$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$archiveRoot = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
if (-not $archiveRoot) { throw 'K90 archive root not found' }
$jarRoot = (Get-ChildItem $archiveRoot -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'jars3') } | Select-Object -First 1).FullName
if (-not $jarRoot) { throw 'tool jar directory not found' }
$cp = ((Get-ChildItem (Join-Path $jarRoot 'jars3') -Filter '*.jar' | ForEach-Object FullName) + (Join-Path $jarRoot 'lspwork\guava-31.1-jre.jar') + (Join-Path $jarRoot 'lspwork\jcommander-1.78.jar')) -join ';'
$out = Join-Path $PSScriptRoot 'sms_device_extract\telephony_smali'
if (Test-Path $out) { Remove-Item -LiteralPath $out -Recurse -Force }
& $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 (Join-Path $PSScriptRoot 'sms_device_extract\telephony-common.jar') -o $out
if ($LASTEXITCODE -ne 0) { throw "baksmali failed: $LASTEXITCODE" }
