$ErrorActionPreference = 'Stop'

$deliveryRoot = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery'
$approvedTopLevel = @(
    'D:\K90_Stage80_EXTRACT_TEST_20261111',
    'D:\K90_AOD_STAGE75_WORK',
    'D:\K90_STAGE79_WORK_V1',
    'D:\K90_stage79_live'
)
$targets = @(
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage53_LABELS_FAN',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage55_FAN_EXEC',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage56_FAN_PERF',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage57_FAN_CONTROL_FIX',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage58_FAN_BRANCH_FIX',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage74_URCC_FULL_CLIENT',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage75_AOD_CARRIER',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage75_AOD_CARRIER_FINAL',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage76_NANDSWAP_CARRIER',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage77_INTEGRATED',
    'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage79_MODEL_SIM_COLOR_PERF',
    'D:\K90_Stage80_EXTRACT_TEST_20261111',
    'D:\K90_AOD_STAGE75_WORK',
    'D:\K90_STAGE79_WORK_V1',
    'D:\K90_stage79_live'
)

$validated = foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Missing directory: $target"
    }
    $item = Get-Item -LiteralPath $target -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing reparse point: $target"
    }
    $full = $item.FullName
    $insideDelivery = $full.StartsWith($deliveryRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    $approvedRoot = $approvedTopLevel -contains $full
    if (-not ($insideDelivery -or $approvedRoot)) {
        throw "Path escaped cleanup whitelist: $full"
    }
    $bytes = (Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum
    [pscustomobject]@{ Path = $full; Bytes = [int64]$bytes }
}

$before = (Get-PSDrive D).Free
$validated | ForEach-Object {
    Write-Host ("DELETE {0:N2} GB  {1}" -f ($_.Bytes / 1GB), $_.Path)
}
foreach ($entry in $validated) {
    Remove-Item -LiteralPath $entry.Path -Recurse -Force
}
$after = (Get-PSDrive D).Free
Write-Host ("FREED_GB={0:N2}" -f (($after - $before) / 1GB))
Write-Host ("FREE_GB={0:N2}" -f ($after / 1GB))
foreach ($entry in $validated) {
    Write-Host ("EXISTS={0} PATH={1}" -f (Test-Path -LiteralPath $entry.Path), $entry.Path)
}
