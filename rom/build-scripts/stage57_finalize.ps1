$ErrorActionPreference = 'Stop'

$base = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage56_FAN_PERF'
$out = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage57_FAN_CONTROL_FIX'
$candidate = Join-Path $out 'images\super.img.candidate'
$final = Join-Path $out 'images\super.img'
$failed = Join-Path $out 'images\super.img.building'
$expectedSize = 13421772800L

if (-not (Test-Path -LiteralPath $candidate)) { throw 'Stage57 candidate is missing.' }
if ((Get-Item -LiteralPath $candidate).Length -ne $expectedSize) { throw 'Stage57 candidate size is wrong.' }
if (Test-Path -LiteralPath $final) { throw 'Refusing to overwrite an existing final super.img.' }

Move-Item -LiteralPath $candidate -Destination $final
Copy-Item -LiteralPath (Join-Path $base 'platform-tools') -Destination $out -Recurse
Copy-Item -LiteralPath (Join-Path $base 'FLASH_KEEP_DATA.ps1') -Destination $out
Copy-Item -LiteralPath (Join-Path $base 'START_UPDATE.cmd') -Destination $out
New-Item -ItemType Directory -Path (Join-Path $out 'audit') -Force | Out-Null

$hash = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  images/super.img" | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt') -Encoding Ascii

@'
Stage57 fan control fix candidate
Base: booted Stage56 FAN_PERF
Changed partitions: system (services.jar only), ODM (native bridge only)
Data wipe: no

Fixes:
- Prefer cooling_fan_mode_v3 over the stale legacy cooling_fan_mode value.
- Observe V3 mode and the actual 1..8 stepless fan level.
- Publish fan settings after observer initialization and on every setting change.
- Map custom level 1..8 to PWM 12/25/37/50/62/74/87/99.
- Add system_server publication logging for runtime diagnosis.

Offline validation passed:
- DEX class count remains 6867; only two intended classes changed.
- Other services.jar members are byte-identical.
- Native fan policy passed 13 host self-tests.
- Rebuilt system EROFS fsck and AVB verification passed.
- Rebuilt ODM EROFS fsck passed.
- No rebuilt system/ODM file or directory is missing an SELinux label.
- Camera-critical odm/lib64/libc++_shared.so remains vendor_file.
- All bytes outside the system and ODM extents match Stage56.

Runtime mode/request/PWM evidence is still required after keep-data flashing.
Only super.img is flashed; no boot-chain, radio, calibration, or user-data
partition is touched.
'@ | Set-Content -LiteralPath (Join-Path $out 'STATUS.txt') -Encoding UTF8

@'
AUDIT_OK
Base super SHA-256: 3037215052f11be72f49cff526fafbc6d3ffeef8d6ce029279dcd0626311640b
Stage57 super size: 13421772800
System offset/length: 1048576 / 1061134336
ODM offset/length: 10713300992 / 1724530688
System and ODM readback matched their rebuilt images byte-for-byte.
System AVB verification passed; system and ODM EROFS fsck passed.
All three unchanged ranges matched Stage56 byte-for-byte.
Final component labels:
  services.jar = u:object_r:system_file:s0
  k90_native_bridge = u:object_r:vendor_touch_init_shell_exec:s0
  odm/lib64/libc++_shared.so = u:object_r:vendor_file:s0
'@ | Set-Content -LiteralPath (Join-Path $out 'INDEPENDENT_AUDIT.txt') -Encoding Ascii

@'
1. The Stage56 native bridge could already write PWM 99; mailbox access was not
   the remaining fault.
2. The existing legacy cooling_fan_mode=0 overwrote mode_v3=2 in system_server.
3. The observer listened to legacy keys instead of the active V3/stepless keys.
4. Stage57 makes V3 authoritative, observes the active keys, and maps levels
   1..8 to the UI's eight-step PWM ladder.
5. Only services.jar in system and k90_native_bridge in ODM were changed.
'@ | Set-Content -LiteralPath (Join-Path $out 'audit\CHANGES.txt') -Encoding UTF8

if (Test-Path -LiteralPath $failed) {
    Remove-Item -LiteralPath $failed -Force
}

Write-Output "STAGE57_FINALIZED"
Write-Output "SUPER_SHA256=$hash"
