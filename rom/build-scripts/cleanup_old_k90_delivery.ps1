$root = (Resolve-Path 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery').Path
$names = @(
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage13_COMBINED',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_R3',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage26_AOD_R1',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage31_MI_CAMERA_CACHEFIX_R1',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage33_CAMERA_PERF_AOD_R1',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_BOOTFIX_R2',
  'K90Max_ColorOS17_Prague_KEEPDATA_Rev2_1_SAFE',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_R1',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage35_CAMERA_RETURN_PERF_SAFE_R1',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_BOOTFIX_R2_INCOMPLETE_DO_NOT_FLASH_2',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_BOOTFIX_R2_INCOMPLETE_DO_NOT_FLASH',
  'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage8_FINAL'
)
foreach ($name in $names) {
  $path = Join-Path $root $name
  if (Test-Path -LiteralPath $path) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if (-not $resolved.StartsWith($root + '\')) { throw "越界路径: $resolved" }
    Write-Output "删除历史目录: $resolved"
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
Get-PSDrive D | Select-Object Name,Free,Used
