$ErrorActionPreference = 'Stop'

$archive = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$main = (Get-ChildItem -LiteralPath $archive -Directory | Where-Object { $_.Name -like '01_*' } | Select-Object -First 1).FullName
$deliveryRoot = Join-Path $main 'K90_A17_PORT_WORK\delivery'
$base = Join-Path $deliveryRoot 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R3'
$out = Join-Path $deliveryRoot 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage25_PERF_POWER_R1'
$system = '\\wsl.localhost\Ubuntu-24.04-K90\root\k90_stage25_perf_system\out\system.img'
$offset = [int64]256 * 4096
$length = [int64]1061134336
$superLength = [int64]13421772800
$baseSuper = Join-Path $base 'images\super.img'
foreach ($p in @($base, $baseSuper, $system)) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing input: $p" } }
if ((Get-Item -LiteralPath $system).Length -ne $length) { throw 'system image size mismatch' }
if (Test-Path -LiteralPath $out) { throw "Refusing to overwrite: $out" }

New-Item -ItemType Directory -Path $out, (Join-Path $out 'images'), (Join-Path $out 'audit') | Out-Null
Get-ChildItem -LiteralPath $base | Where-Object Name -ne 'images' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $out -Recurse -Force
}
$super = Join-Path $out 'images\super.img'
[IO.File]::Copy($baseSuper, $super, $false)
$buffer = New-Object byte[] (16MB)
$src = [IO.File]::OpenRead($system)
$dst = [IO.File]::Open($super, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $dst.Position = $offset
    while (($n = $src.Read($buffer, 0, $buffer.Length)) -gt 0) { $dst.Write($buffer, 0, $n) }
    $dst.Flush($true)
} finally { $src.Dispose(); $dst.Dispose() }
if ((Get-Item -LiteralPath $super).Length -ne $superLength) { throw 'super size mismatch' }

function Get-RegionHash([string]$Path, [int64]$Start, [int64]$Count) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $buf = New-Object byte[] (16MB)
    try {
        $stream.Position = $Start
        $left = $Count
        while ($left -gt 0) {
            $want = [int][Math]::Min([int64]$buf.Length, $left)
            $n = $stream.Read($buf, 0, $want)
            if ($n -le 0) { throw 'Unexpected EOF during region hash' }
            [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
            $left -= $n
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-', '')
    } finally { $sha.Dispose(); $stream.Dispose() }
}

$end = $offset + $length
if ((Get-RegionHash $baseSuper 0 $offset) -ne (Get-RegionHash $super 0 $offset)) { throw 'super prefix changed' }
if ((Get-RegionHash $baseSuper $end ($superLength - $end)) -ne (Get-RegionHash $super $end ($superLength - $end))) { throw 'super suffix changed' }
$baseSystemHash = Get-RegionHash $baseSuper $offset $length
$newSystemHash = Get-RegionHash $super $offset $length
$sourceSystemHash = (Get-FileHash -LiteralPath $system -Algorithm SHA256).Hash
if ($newSystemHash -ne $sourceSystemHash) { throw 'Inserted system region hash mismatch' }
if ($baseSystemHash -eq $newSystemHash) { throw 'System region did not change' }

$hash = (Get-FileHash -LiteralPath $super -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS.txt'), "$hash  images\super.img`r`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $out 'STATUS.txt'), "STAGE25_PERF_POWER_R1_BUILT; STATIC_VERIFICATION_PASSED; DEVICE_FLASH_PENDING`r`n", [Text.UTF8Encoding]::new($false))

$audit = Join-Path $out 'audit'
Copy-Item -LiteralPath 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage25_perf\SHA256SUMS.jars.txt' -Destination $audit
Copy-Item -LiteralPath 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage25_perf\CHANGED_CLASSES.txt' -Destination $audit
Copy-Item -LiteralPath 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\build-stage25-perf-jars.ps1' -Destination $audit
Copy-Item -LiteralPath 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\build-stage25-perf-system.sh' -Destination $audit

$readme = @"
Stage25 性能/耗电 R1

基线：Stage24 SMS_NATIVE_R3（短信实机通过）
仅修改 system 逻辑分区中的：
- /system/framework/framework.jar
- /system/framework/oplus-framework.jar

修复：
- IPerformance 不存在时反复 ServiceManager 查询、null asBinder NPE 和完整堆栈洪水。
- IUrcc 不存在时反复 stable-AIDL isDeclared/SELinux denied 查询。

明确保留：
- MTK PowerHAL、FPSGO、Xiaomi UniPerf/MiPower、温控和 GPU DVFS。
- Stage24 R3 的 telephony-common.jar，SHA-256 仍为 235f3189ba172e3fce471aeba7c7e9a9cc2f88c19c5986ffb8a459675fea146f。

明确未做：
- 不锁 CPU/GPU 最高频，不关闭温控，不伪造 Oplus HAL，不重建 vendor。
- 静态校验通过不等于实机性能/续航已通过，刷机后必须复验日志、短信和游戏启动 boost。
"@
[IO.File]::WriteAllText((Join-Path $out 'README_STAGE25.txt'), $readme, [Text.UTF8Encoding]::new($true))
Write-Output "DELIVERY=$out"
Write-Output "BASE_SYSTEM_SHA256=$($baseSystemHash.ToLowerInvariant())"
Write-Output "NEW_SYSTEM_SHA256=$($newSystemHash.ToLowerInvariant())"
Write-Output "SUPER_SHA256=$hash"
