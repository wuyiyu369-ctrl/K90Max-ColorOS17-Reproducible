$ErrorActionPreference = 'Stop'
$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$archiveRoot = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
if (-not $archiveRoot) { throw 'K90 archive root not found' }
$jarRoot = (Get-ChildItem $archiveRoot -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'jars3') } | Select-Object -First 1).FullName
if (-not $jarRoot) { throw 'tool jar directory not found' }
$cp = @(
    (Join-Path $jarRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $jarRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $jarRoot 'jars\antlr.jar'),
    (Join-Path $jarRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'
$smali = Join-Path $PSScriptRoot 'sms_device_extract\telephony_smali'
$dex = Join-Path $PSScriptRoot 'sms_device_extract\classes.patched.dex'
if (Test-Path $dex) { Remove-Item -LiteralPath $dex -Force }
& $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 $smali -o $dex
if ($LASTEXITCODE -ne 0) { throw "smali failed: $LASTEXITCODE" }
Write-Output (Get-Item $dex | Select-Object FullName,Length | Out-String)
