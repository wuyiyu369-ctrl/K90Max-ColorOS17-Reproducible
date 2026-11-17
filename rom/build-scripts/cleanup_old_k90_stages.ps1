$ErrorActionPreference = 'Stop'
$delivery = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery'
$names = @(
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage42_FANPERF_POLICY',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_FANPERF',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_R1_FANPERF_BOOTFIX',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage45_UNIPERF_FAN',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage48_CPU_SCENE_STATEFIX',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX',
    'K90Max_ColorOS17_Prague_FACTORY_RESET_CANDIDATE_Stage49',
    'K90Max_ColorOS17_Prague_KEEPDATA_Stage51_NAME_CHARGE_FAN',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage52_FAN_AOD_SIM',
    'K90Max_ColorOS17_Stage48_正式发布包',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR_failed_install'
)

$rootFull = [IO.Path]::GetFullPath($delivery).TrimEnd('\') + '\'
foreach ($name in $names) {
    $target = [IO.Path]::GetFullPath((Join-Path $delivery $name))
    if (-not $target.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside delivery: $target"
    }
    if ($name -match 'Stage5[356]') {
        throw "Refusing protected stage: $target"
    }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Missing cleanup target: $target"
    }
}

foreach ($name in $names) {
    $target = Join-Path $delivery $name
    Write-Output "Deleting $target"
    Remove-Item -LiteralPath $target -Recurse -Force
}
Write-Output 'OLD_K90_DELIVERIES_DELETED'
