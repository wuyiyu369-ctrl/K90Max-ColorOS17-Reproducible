param([int]$WaitSeconds=180)
$ErrorActionPreference='Continue'
$Adb='D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_R1_FANPERF_BOOTFIX\platform-tools\adb.exe'
$Serial=$env:ANDROID_SERIAL
if ([string]::IsNullOrWhiteSpace($Serial)) { throw '请先设置 ANDROID_SERIAL 环境变量' }
$Destination=Join-Path $PSScriptRoot 'stage44_r1_runtime'
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$Deadline=[DateTime]::UtcNow.AddSeconds($WaitSeconds)
$Completed=$false
do {
    $Devices=& $Adb devices
    if ($Devices -match ($Serial+'\s+device\s*$')) {
        $Boot=& $Adb -s $Serial shell getprop sys.boot_completed
        if (($Boot | Out-String).Trim() -eq '1') { $Completed=$true;break }
    }
    Start-Sleep -Seconds 3
} while ([DateTime]::UtcNow -lt $Deadline)
if (-not $Completed) { Write-Output 'BOOT_COMPLETED_NOT_CONFIRMED'; $Devices;exit 2 }
& $Adb -s $Serial shell 'getprop sys.boot_completed; getprop init.svc.k90-stage44-native; pidof system_server; uptime; ps -A -Z | grep -E "k90|system_server"' 2>&1 | Tee-Object -FilePath (Join-Path $Destination 'boot_and_services.txt')
& $Adb -s $Serial shell '/odm/bin/k90_native_bridge --self-test' 2>&1 | Tee-Object -FilePath (Join-Path $Destination 'native_selftest.txt')
& $Adb -s $Serial logcat -b all -d 2>&1 | Out-File -LiteralPath (Join-Path $Destination 'logcat_all.txt') -Encoding utf8
& $Adb -s $Serial shell dmesg 2>&1 | Out-File -LiteralPath (Join-Path $Destination 'dmesg.txt') -Encoding utf8
& $Adb -s $Serial shell 'for key in cooling_fan_main_switch cooling_fan_mode_v3 cooling_fan_customize_level cooling_fan_game_switch cooling_fan_charge_switch; do echo $key; settings get system $key; done; ls -lZ /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty /sys/devices/platform/odm/odm:xiaomi_fan/target_level; cat /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty /sys/devices/platform/odm/odm:xiaomi_fan/real_speed; cat /sys/class/thermal/thermal_message/board_sensor_temp /sys/class/thermal/thermal_message/screen_state /sys/class/thermal/thermal_message/foreground_app_name; for p in /sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy4 /sys/devices/system/cpu/cpufreq/policy7; do echo $p; cat $p/scaling_cur_freq $p/scaling_max_freq; done' 2>&1 | Out-File -LiteralPath (Join-Path $Destination 'fan_and_frequency.txt') -Encoding utf8
Write-Output 'RUNTIME_SNAPSHOT_CAPTURED'
