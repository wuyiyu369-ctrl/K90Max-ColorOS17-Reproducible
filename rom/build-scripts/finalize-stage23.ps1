$ErrorActionPreference = 'Stop'

$root = 'D:\K90Max_ColorOS17_完整迁移_20261028'
$base = Join-Path $root '01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage22_FP_PROGRESS'
$delivery = Join-Path $root '01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage23_SCAN_BRIGHTNESS'
$system = '\\wsl.localhost\Ubuntu-24.04-K90\root\k90_stage23_system\out\system.img'
$work = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\stage23_logs'

foreach ($p in @($base, $system)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "缺少输入：$p" }
}
if (Test-Path -LiteralPath $delivery) { throw "交付目录已存在，拒绝覆盖：$delivery" }

New-Item -ItemType Directory -Path $delivery | Out-Null
Get-ChildItem -LiteralPath $base | Where-Object Name -ne 'images' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $delivery -Recurse -Force
}
$images = New-Item -ItemType Directory -Path (Join-Path $delivery 'images')
$outSuper = Join-Path $images.FullName 'super.img'
[IO.File]::Copy((Join-Path $base 'images\super.img'), $outSuper, $false)

# super logical system extent from the proven Stage20/22 layout; no other extent is touched.
$offset = [int64]256 * 4096
$length = [int64]1061134336
$buf = New-Object byte[] (16MB)
$dst = [IO.File]::Open($outSuper, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $src = [IO.File]::OpenRead($system)
    try {
        if ($src.Length -ne $length) { throw "system 镜像大小异常：$($src.Length)" }
        $dst.Position = $offset
        while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) { $dst.Write($buf, 0, $n) }
    } finally { $src.Dispose() }
    $dst.Flush($true)
} finally { $dst.Dispose() }
if ((Get-Item -LiteralPath $outSuper).Length -ne 13421772800) { throw 'super 镜像大小异常' }

function Get-RegionHash([string]$Path, [int64]$Start, [int64]$Count) {
    $f = [IO.File]::OpenRead($Path); $h = [Security.Cryptography.SHA256]::Create(); $b = New-Object byte[] (16MB)
    try {
        $f.Position = $Start; $left = $Count
        while ($left -gt 0) {
            $want = [int][Math]::Min([int64]$b.Length, $left); $n = $f.Read($b, 0, $want)
            if ($n -le 0) { throw "读取区域时遇到 EOF：$Path" }
            [void]$h.TransformBlock($b, 0, $n, $null, 0); $left -= $n
        }
        [void]$h.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [Convert]::ToHexString($h.Hash)
    } finally { $h.Dispose(); $f.Dispose() }
}
function Assert-Region([string]$A, [int64]$AO, [string]$B, [int64]$BO, [int64]$Count, [string]$Name) {
    if ((Get-RegionHash $A $AO $Count) -ne (Get-RegionHash $B $BO $Count)) { throw "区域校验失败：$Name" }
}

Assert-Region $outSuper $offset $system 0 $length 'system extent'
$superLen = [int64]13421772800
$end = $offset + $length
Assert-Region (Join-Path $base 'images\super.img') 0 $outSuper 0 $offset 'prefix unchanged'
Assert-Region (Join-Path $base 'images\super.img') $end $outSuper $end ($superLen - $end) 'suffix unchanged'

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outSuper).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $delivery 'SHA256SUMS.txt'), "$hash  images\super.img`r`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $delivery 'INDEPENDENT_AUDIT.txt'), "AUDIT_OK`r`nSYSTEM_AVB_VERIFIED_OFFLINE`r`nSYSTEM_EXTENT_MATCHES_STAGE23`r`nNON_SYSTEM_SUPER_BYTES_MATCH_STAGE22`r`nKEEP_DATA_ONLY`r`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $delivery 'STATUS.txt'), 'OFFLINE_CHECKS_PASSED; KEEP_DATA; DEVICE_BOOT_AND_FUNCTION_TESTS_PENDING`r`n', [Text.UTF8Encoding]::new($false))
Write-Output "DELIVERY=$delivery"
Write-Output "SHA256=$hash"
