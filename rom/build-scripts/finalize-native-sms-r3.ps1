$ErrorActionPreference = 'Stop'

$archive = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
$main = (Get-ChildItem -LiteralPath $archive -Directory | Where-Object { $_.Name -like '01_*' } | Select-Object -First 1).FullName
$deliveryRoot = Join-Path $main 'K90_A17_PORT_WORK\delivery'
$base = Join-Path $deliveryRoot 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R2'
$out = Join-Path $deliveryRoot 'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R3'
$system = '\\wsl.localhost\Ubuntu-24.04-K90\root\k90_sms_native_r3_system\out\system.img'
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
$hash = (Get-FileHash -LiteralPath $super -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS.txt'), "$hash  images\super.img`r`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $out 'STATUS.txt'), "R3_BUILT; FINAL_LOGICAL_PARTITION_VERIFICATION_PENDING; DO_NOT_FLASH_YET`r`n", [Text.UTF8Encoding]::new($false))
Write-Output "DELIVERY=$out"
Write-Output "SHA256=$hash"
