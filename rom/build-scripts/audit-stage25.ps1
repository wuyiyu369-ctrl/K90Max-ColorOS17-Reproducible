$ErrorActionPreference = 'Stop'

$archive = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$main = (Get-ChildItem -LiteralPath $archive -Directory | Where-Object { $_.Name -like '01_*' } | Select-Object -First 1).FullName
$delivery = Join-Path $main 'K90_A17_PORT_WORK\delivery'
$base = Join-Path $delivery 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R3\images\super.img'
$candidateRoot = Join-Path $delivery 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage25_PERF_POWER_R1'
$candidate = Join-Path $candidateRoot 'images\super.img'
$lpunpack = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpunpack.exe' | Select-Object -First 1).FullName
$lpdump = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpdumps.exe' | Select-Object -First 1).FullName
$out = 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage25_perf\final_extract'
foreach ($p in @($base, $candidate, $lpunpack, $lpdump)) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing input: $p" } }
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

& $lpdump $base | Set-Content -LiteralPath (Join-Path $out 'base-lpdump.txt') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "base lpdump failed: $LASTEXITCODE" }
& $lpdump $candidate | Set-Content -LiteralPath (Join-Path $out 'candidate-lpdump.txt') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "candidate lpdump failed: $LASTEXITCODE" }
if ((Get-FileHash (Join-Path $out 'base-lpdump.txt')).Hash -ne (Get-FileHash (Join-Path $out 'candidate-lpdump.txt')).Hash) { throw 'Logical partition layout changed' }

& $lpunpack -p system_a_a $candidate $out
if ($LASTEXITCODE -ne 0) { throw "lpunpack failed: $LASTEXITCODE" }
$image = Join-Path $out 'system_a_a.img'
if ((Get-Item -LiteralPath $image).Length -ne 1061134336) { throw 'Extracted system size mismatch' }

wsl -d Ubuntu-24.04-K90 -u root -e bash /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/verify-stage25-system.sh
if ($LASTEXITCODE -ne 0) { throw "WSL system verification failed: $LASTEXITCODE" }

$audit = @"
AUDIT_OK
STAGE25_PERF_POWER_R1
LOGICAL_PARTITION_LAYOUT_MATCHES_R3
SYSTEM_AVB_HASHTREE_VERIFIED
SYSTEM_EROFS_NO_CORRUPTION
SYSTEM_ROOTFS_LABEL_VERIFIED
SYSTEM_UUID_PRESERVED
EMBEDDED_FRAMEWORK_AND_OPLUS_FRAMEWORK_MATCH_STAGE25
EMBEDDED_TELEPHONY_JAR_SHA256_235F3189BA172E3FCE471AEBA7C7E9A9CC2F88C19C5986FFB8A459675FEA146F
ONLY_SYSTEM_REGION_CHANGED_FROM_R3
KEEP_DATA_ONLY
DEVICE_FLASH_PENDING
"@
[IO.File]::WriteAllText((Join-Path $candidateRoot 'INDEPENDENT_AUDIT.txt'), $audit, [Text.UTF8Encoding]::new($false))
Write-Output "TRUE_SYSTEM=$image"
Write-Output 'STAGE25_INDEPENDENT_AUDIT_OK'
