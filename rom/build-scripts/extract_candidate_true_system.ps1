$ErrorActionPreference = 'Stop'
$archive = (Get-ChildItem -LiteralPath 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$tool = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'lpunpack.exe' | Select-Object -First 1).FullName
$src = (Get-ChildItem -LiteralPath $archive -Recurse -File -Filter 'super.img' | Where-Object { $_.FullName -like '*Stage24_SMS_NATIVE\images*' } | Select-Object -First 1).FullName
$out = Join-Path $PSScriptRoot 'candidate_true_extract'
if (Test-Path $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
& $tool -p system_a_a $src $out
if ($LASTEXITCODE -ne 0) { throw "lpunpack failed: $LASTEXITCODE" }
Get-ChildItem -LiteralPath $out | Select-Object FullName,Length
