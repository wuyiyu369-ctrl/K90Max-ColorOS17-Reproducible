$ErrorActionPreference = 'Stop'
$archive = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$main = (Get-ChildItem -LiteralPath $archive -Directory | Where-Object { $_.Name -like '01_*' } | Select-Object -First 1).FullName
$delivery = Join-Path $main 'K90_A17_PORT_WORK\delivery'
$base = Join-Path $delivery 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_BRIGHTNESS_CURVE_R4\images\super.img'
$candidate = Join-Path $delivery 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R2\images\super.img'
$lpunpack = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpunpack.exe' | Select-Object -First 1).FullName
$lpdump = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpdumps.exe' | Select-Object -First 1).FullName
$out = Join-Path $PSScriptRoot 'sms_r2_final_extract'
if (Test-Path $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
& $lpdump $base | Set-Content -LiteralPath (Join-Path $out 'base-lpdump.txt') -Encoding utf8
& $lpdump $candidate | Set-Content -LiteralPath (Join-Path $out 'candidate-lpdump.txt') -Encoding utf8
if ((Get-FileHash (Join-Path $out 'base-lpdump.txt')).Hash -ne (Get-FileHash (Join-Path $out 'candidate-lpdump.txt')).Hash) { throw 'logical partition layout changed' }
& $lpunpack -p system_a_a $candidate $out
if ($LASTEXITCODE -ne 0) { throw "lpunpack failed: $LASTEXITCODE" }
$image = Join-Path $out 'system_a_a.img'
if ((Get-Item $image).Length -ne 1061134336) { throw 'extracted system size mismatch' }
Write-Output "TRUE_SYSTEM=$image"
