$ErrorActionPreference = 'Stop'

$archive = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$main = (Get-ChildItem -LiteralPath $archive -Directory | Where-Object { $_.Name -like '01_*' } | Select-Object -First 1).FullName
$delivery = Join-Path $main 'K90_A17_PORT_WORK\delivery'
$base = Join-Path $delivery 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R2\images\super.img'
$candidate = Join-Path $delivery 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R3\images\super.img'
$lpunpack = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpunpack.exe' | Select-Object -First 1).FullName
$lpdump = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpdumps.exe' | Select-Object -First 1).FullName
$out = Join-Path $PSScriptRoot 'sms_r3_final_extract'
foreach ($p in @($base, $candidate, $lpunpack, $lpdump)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing input: $p" }
}
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

& $lpdump $base | Set-Content -LiteralPath (Join-Path $out 'base-lpdump.txt') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "base lpdump failed: $LASTEXITCODE" }
& $lpdump $candidate | Set-Content -LiteralPath (Join-Path $out 'candidate-lpdump.txt') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "candidate lpdump failed: $LASTEXITCODE" }
if ((Get-FileHash (Join-Path $out 'base-lpdump.txt')).Hash -ne (Get-FileHash (Join-Path $out 'candidate-lpdump.txt')).Hash) {
    throw 'logical partition layout changed'
}

& $lpunpack -p system_a_a $candidate $out
if ($LASTEXITCODE -ne 0) { throw "lpunpack failed: $LASTEXITCODE" }
$image = Join-Path $out 'system_a_a.img'
if ((Get-Item -LiteralPath $image).Length -ne 1061134336) { throw 'extracted system size mismatch' }
Write-Output "TRUE_SYSTEM=$image"
Write-Output 'LOGICAL_LAYOUT_UNCHANGED'
