$out = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\policy_inputs_coloros17_matching'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$files = @{
  plat = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\trees\pmb_system\system\etc\selinux\plat_sepolicy.cil'
  platmap = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\trees\pmb_system\system\etc\selinux\mapping\202504.cil'
  platcompat = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\trees\pmb_system\system\etc\selinux\mapping\202504.compat.cil'
  vendor = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\trees\pmb_vendor\etc\selinux\vendor_sepolicy.cil'
  odm = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\trees\k90_odm\etc\selinux\odm_sepolicy.cil'
  vers = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\trees\pmb_vendor\etc\selinux\plat_sepolicy_vers.txt'
}
foreach ($key in $files.Keys) { Copy-Item -LiteralPath $files[$key] -Destination (Join-Path $out ($key + '.cil')) -Force }
Get-ChildItem $out | Select-Object Name,Length
