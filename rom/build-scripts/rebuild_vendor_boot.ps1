$ErrorActionPreference = 'Stop'

$Stock = 'D:\K90Max_ColorOS17_完整迁移_20261028\04_原始底包与参考包\BAO\RedmiK90Max_OS4.0.0.14_17.0\zhuimeng\vendor_boot.img'
$Ramdisk = 'D:\vbtmp\ramdisk_modified.lz4'
$Recovery = 'D:\vbtmp\recovery.lz4'
$Output = 'D:\vbtmp\vendor_boot_rebuilt.img'

$HeaderRamdiskSizeOffset = 24L
$RamdiskStart = 4096L
$DtbStart = 52965376L
$TableStart = 53616640L
$EntrySize = 108L

$RamdiskBytes = [IO.File]::ReadAllBytes($Ramdisk)
$RecoveryBytes = [IO.File]::ReadAllBytes($Recovery)
$TotalRamdiskSize = $RamdiskBytes.LongLength + $RecoveryBytes.LongLength
if ($TotalRamdiskSize -gt ($DtbStart - $RamdiskStart)) {
    throw '重建后的 vendor ramdisk 超过原镜像预留空间。'
}

Copy-Item -LiteralPath $Stock -Destination $Output -Force
$Stream = [IO.File]::Open($Output, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $Stream.Position = $HeaderRamdiskSizeOffset
    $Bytes = [BitConverter]::GetBytes([uint32]$TotalRamdiskSize)
    $Stream.Write($Bytes, 0, $Bytes.Length)

    $Stream.Position = $RamdiskStart
    $Stream.Write($RamdiskBytes, 0, $RamdiskBytes.Length)
    $Stream.Write($RecoveryBytes, 0, $RecoveryBytes.Length)

    $Remaining = $DtbStart - $Stream.Position
    if ($Remaining -gt 0) {
        $Zeros = New-Object byte[] ([int]$Remaining)
        $Stream.Write($Zeros, 0, $Zeros.Length)
    }

    $Stream.Position = $TableStart
    $Bytes = [BitConverter]::GetBytes([uint32]$RamdiskBytes.Length)
    $Stream.Write($Bytes, 0, $Bytes.Length)

    $Stream.Position = $TableStart + $EntrySize + 4
    $Bytes = [BitConverter]::GetBytes([uint32]$RamdiskBytes.Length)
    $Stream.Write($Bytes, 0, $Bytes.Length)
} finally {
    $Stream.Dispose()
}

$Hash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
[pscustomobject]@{
    Output = $Output
    Bytes = (Get-Item -LiteralPath $Output).Length
    RamdiskSize = $RamdiskBytes.Length
    RecoverySize = $RecoveryBytes.Length
    TotalRamdiskSize = $TotalRamdiskSize
    SHA256 = $Hash
}
