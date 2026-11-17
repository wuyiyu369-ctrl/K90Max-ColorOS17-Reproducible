$ErrorActionPreference = 'Stop'
$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$archive = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$jarRoot = (Get-ChildItem $archive -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'jars3') } | Select-Object -First 1).FullName
$cp = @(
    (Join-Path $jarRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $jarRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $jarRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'
$root = Join-Path $PSScriptRoot 'sms_native_r2'
$verify = Join-Path $root 'verify_smali'
if (Test-Path $verify) { Remove-Item -LiteralPath $verify -Recurse -Force }
& $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 (Join-Path $root 'telephony-common.native-sms-r2.jar') -o $verify
if ($LASTEXITCODE -ne 0) { throw 'patched JAR baksmali verification failed' }
$before = (Get-ChildItem (Join-Path $root 'smali') -Recurse -Filter '*.smali').Count
$after = (Get-ChildItem $verify -Recurse -Filter '*.smali').Count
if ($before -ne $after) { throw "class count changed: $before -> $after" }
$gsm = Get-Content (Join-Path $verify 'com\android\internal\telephony\gsm\GsmInboundSmsHandler.smali') -Raw
$cdma = Get-Content (Join-Path $verify 'com\android\internal\telephony\cdma\CdmaInboundSmsHandler.smali') -Raw
$needle = 'invoke-virtual {v0, v1}, Lcom/android/internal/telephony/StateMachine;->sendMessage(I)V'
if (([regex]::Matches($gsm, [regex]::Escape($needle))).Count -ne 1) { throw 'GSM native start patch missing or duplicated' }
if (([regex]::Matches($cdma, [regex]::Escape($needle))).Count -ne 1) { throw 'CDMA native start patch missing or duplicated' }
Write-Output "CLASS_COUNT_OK=$before"
Write-Output 'GSM_PATCH_OK'
Write-Output 'CDMA_PATCH_OK'
